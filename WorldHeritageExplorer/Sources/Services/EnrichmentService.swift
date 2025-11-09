//  EnrichmentService.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/8/25.
//
//  Performs background enrichment of missing heritage data (images, gallery, coordinates)
//  using Wikidata, Wikipedia, and Wikimedia Commons.

import Foundation
import CoreData
import CoreLocation

final class EnrichmentService {
    static let shared = EnrichmentService()
    private let session: URLSession
    private let opQueue = OperationQueue()
    private var inProgressObjectIDs = Set<NSManagedObjectID>()
    private var qidCache = [String: String]() // name+country -> qid
    private var commonsCategoryCache = [String: String]()
    private var imageCache = [String: String]() // qid -> image url

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        opQueue.maxConcurrentOperationCount = 3
    }

    func startIfNeeded(container: NSPersistentContainer) {
        opQueue.addOperation { [weak self] in
            self?.runEnrichment(container: container)
        }
    }

    private func runEnrichment(container: NSPersistentContainer) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        do {
            let req = NSFetchRequest<NSManagedObject>(entityName: "Heritage")
            req.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "mainImageURL == nil OR mainImageURL == ''"),
                NSPredicate(format: "galleryImageURLs == nil OR galleryImageURLs == ''"),
                NSPredicate(format: "latitude == nil OR longitude == nil OR (latitude == 0 AND longitude == 0)")
            ])
            let targets = try context.fetch(req)
            if targets.isEmpty {
                print("[Enrichment] No targets.")
                return
            }
            print("[Enrichment] Targets: \(targets.count)")

            var missingReportLines: [String] = ["name,country,needsMainImage,needsGallery,needsCoordinates"]
            var cntMain = 0, cntGallery = 0, cntCoord = 0

            for obj in targets {
                if inProgressObjectIDs.contains(obj.objectID) { continue }
                inProgressObjectIDs.insert(obj.objectID)

                let name = obj.value(forKey: "name") as? String ?? ""
                let country = obj.value(forKey: "country") as? String ?? ""
                let mainVal = (obj.value(forKey: "mainImageURL") as? String ?? "")
                let galleryVal = (obj.value(forKey: "galleryImageURLs") as? String ?? "")
                let latNum = obj.value(forKey: "latitude") as? NSNumber
                let lonNum = obj.value(forKey: "longitude") as? NSNumber
                let hasMain = !mainVal.isEmpty
                let hasGallery = !galleryVal.isEmpty
                let hasCoords = {
                    guard let lat = latNum?.doubleValue, let lon = lonNum?.doubleValue else { return false }
                    return !(lat == 0 && lon == 0)
                }()

                if !hasMain { cntMain += 1 }
                if !hasGallery { cntGallery += 1 }
                if !hasCoords { cntCoord += 1 }

                missingReportLines.append("\(escapeCSV(name)),\(escapeCSV(country)),\(!hasMain),\(!hasGallery),\(!hasCoords)")

                // Resolve QID if needed
                var qid = obj.value(forKey: "wikidataQID") as? String
                if qid == nil || qid!.isEmpty {
                    qid = lookupWikidataQID(name: name, country: country)
                    if let qid = qid { obj.setValue(qid, forKey: "wikidataQID") }
                }

                var bundleCoords: (Double, Double)? = nil
                var bundleImage: ImageInfo? = nil
                var bundleCategory: String? = nil
                if let qid = qid {
                    let bundle = fetchWikidataBundle(qid: qid)
                    bundleCoords = bundle.coords
                    bundleImage = bundle.image
                    bundleCategory = bundle.category
                    if let cat = bundleCategory, !cat.isEmpty {
                        obj.setValue(cat, forKey: "commonsCategory")
                    }
                }

                // Coordinates enrichment
                if !hasCoords {
                    if let (lat, lon) = bundleCoords {
                        obj.setValue(lat, forKey: "latitude")
                        obj.setValue(lon, forKey: "longitude")
                        obj.setValue(Date(), forKey: "enrichedAt")
                        obj.setValue("wikidata", forKey: "dataSource")
                    } else if let (lat, lon) = geocodeApproximate(name: name, country: country) {
                        obj.setValue(lat, forKey: "latitude")
                        obj.setValue(lon, forKey: "longitude")
                        obj.setValue(Date(), forKey: "enrichedAt")
                        obj.setValue("clgeocoder", forKey: "dataSource")
                    }
                }

                // Main image enrichment
                if !hasMain {
                    if let imageInfo = bundleImage {
                        obj.setValue(imageInfo.url, forKey: "mainImageURL")
                        obj.setValue(imageInfo.license, forKey: "imageLicense")
                        obj.setValue(Date(), forKey: "enrichedAt")
                        obj.setValue("wikidata", forKey: "dataSource")
                    } else if let wikiImage = fetchWikipediaImage(name: name, country: country) {
                        obj.setValue(wikiImage.url, forKey: "mainImageURL")
                        if let lic = wikiImage.license { obj.setValue(lic, forKey: "imageLicense") }
                        obj.setValue(Date(), forKey: "enrichedAt")
                        obj.setValue("wikipedia", forKey: "dataSource")
                    }
                }

                // Gallery enrichment (try Commons category images; fallback reuse main image)
                if !hasGallery {
                    if let cat = bundleCategory, !cat.isEmpty {
                        let imgs = fetchCommonsCategoryImages(category: cat)
                        if !imgs.isEmpty {
                            obj.setValue(imgs.joined(separator: ";"), forKey: "galleryImageURLs")
                        }
                    }
                    if ((obj.value(forKey: "galleryImageURLs") as? String)?.isEmpty ?? true), let main = obj.value(forKey: "mainImageURL") as? String, !main.isEmpty {
                        obj.setValue(main, forKey: "galleryImageURLs")
                    }
                }

                // Persist each object immediately to avoid large memory growth
                do { try context.save() } catch { print("[Enrichment] Save error: \(error)") }
                context.refresh(obj, mergeChanges: false)
            }

            exportMissingReport(lines: missingReportLines)
            print("[Enrichment] Missing counts -> main: \(cntMain), gallery: \(cntGallery), coords: \(cntCoord)")
            print("[Enrichment] Completed.")
        } catch {
            print("[Enrichment] Failed: \(error)")
        }
    }

    private func escapeCSV(_ v: String) -> String {
        if v.contains(",") { return "\"\(v)\"" } else { return v }
    }

    private func exportMissingReport(lines: [String]) {
        let csv = lines.joined(separator: "\n")
        do {
            let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("missing_report.csv")
            try csv.data(using: .utf8)?.write(to: url)
            print("[Enrichment] Missing report exported to: \(url.path)")
        } catch {
            print("[Enrichment] Export failed: \(error)")
        }
    }

    // MARK: - Wikidata / Commons / Wikipedia implementations
    private struct ImageInfo { let url: String; let license: String }
    private struct WikiImage { let url: String; let license: String? }

    private func lookupWikidataQID(name: String, country: String) -> String? {
        let key = "\(name.lowercased())|\(country.lowercased())"
        if let cached = qidCache[key] { return cached }
        let query = "\(name) \(country)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://www.wikidata.org/w/api.php?action=wbsearchentities&search=\(query)&language=en&format=json&limit=3&origin=*"
        guard let url = URL(string: urlStr) else { return nil }
        let json = syncGET(url: url)
        guard let obj = json as? [String: Any], let search = obj["search"] as? [[String: Any]] else { return nil }
        // Try to find one containing 'World Heritage' description
        let candidate = search.first { ($0["description"] as? String)?.localizedCaseInsensitiveContains("World Heritage") == true } ?? search.first
        if let id = candidate?["id"] as? String { qidCache[key] = id; return id }
        return nil
    }

    private func fetchWikidataBundle(qid: String) -> (coords: (Double, Double)?, image: ImageInfo?, category: String?) {
        let urlStr = "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json"
        guard let url = URL(string: urlStr) else { return (nil, nil, nil) }
        let json = syncGET(url: url)
        guard
            let root = json as? [String: Any],
            let entities = root["entities"] as? [String: Any],
            let entity = entities[qid] as? [String: Any],
            let claims = entity["claims"] as? [String: Any]
        else { return (nil, nil, nil) }

        var coords: (Double, Double)? = nil
        if let p625 = claims["P625"] as? [[String: Any]], let first = p625.first,
           let snak = first["mainsnak"] as? [String: Any],
           let dv = snak["datavalue"] as? [String: Any],
           let value = dv["value"] as? [String: Any],
           let lat = value["latitude"] as? Double,
           let lon = value["longitude"] as? Double {
            coords = (lat, lon)
        }

        var imageInfo: ImageInfo? = nil
        if let p18 = claims["P18"] as? [[String: Any]], let first = p18.first,
           let snak = first["mainsnak"] as? [String: Any],
           let dv = snak["datavalue"] as? [String: Any],
           let value = dv["value"] as? String {
            imageInfo = fetchCommonsImageInfo(filename: value)
        }

        var category: String? = nil
        if let p373 = claims["P373"] as? [[String: Any]], let first = p373.first,
           let snak = first["mainsnak"] as? [String: Any],
           let dv = snak["datavalue"] as? [String: Any],
           let value = dv["value"] as? String {
            category = value
        }
        return (coords, imageInfo, category)
    }

    private func fetchWikidataCoordinates(qid: String) -> (Double, Double)? { // legacy path kept if called
        return fetchWikidataBundle(qid: qid).coords
    }

    private func fetchWikidataImage(qid: String) -> ImageInfo? { // legacy path kept if called
        return fetchWikidataBundle(qid: qid).image
    }

    private func fetchCommonsImageInfo(filename: String) -> ImageInfo? {
        let encoded = filename.replacingOccurrences(of: " ", with: "_")
        let title = "File:\(encoded)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? encoded
        let urlStr = "https://commons.wikimedia.org/w/api.php?action=query&titles=\(title)&prop=imageinfo&iiprop=url|extmetadata&format=json&origin=*"
        guard let url = URL(string: urlStr) else { return nil }
        let json = syncGET(url: url)
        guard let root = json as? [String: Any], let query = root["query"] as? [String: Any], let pages = query["pages"] as? [String: Any] else { return nil }
        for (_, pageVal) in pages {
            guard let page = pageVal as? [String: Any], let imageinfo = page["imageinfo"] as? [[String: Any]], let first = imageinfo.first, let imgURL = first["url"] as? String else { continue }
            var license = ""
            if let ext = first["extmetadata"] as? [String: Any] {
                if let licShort = (ext["LicenseShortName"] as? [String: Any])?["value"] as? String { license = licShort }
                if license.isEmpty, let licUrl = (ext["LicenseUrl"] as? [String: Any])?["value"] as? String { license = licUrl }
            }
            return ImageInfo(url: imgURL, license: license)
        }
        return nil
    }

    private func fetchCommonsCategoryImages(category: String) -> [String] {
        let cat = category.replacingOccurrences(of: " ", with: "_")
        let title = "Category:\(cat)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cat
        let urlStr = "https://commons.wikimedia.org/w/api.php?action=query&generator=categorymembers&gcmtitle=\(title)&gcmtype=file&gcmlimit=5&prop=imageinfo&iiprop=url&format=json&origin=*"
        guard let url = URL(string: urlStr) else { return [] }
        let json = syncGET(url: url)
        guard let root = json as? [String: Any], let query = root["query"] as? [String: Any], let pages = query["pages"] as? [String: Any] else { return [] }
        var urls: [String] = []
        for (_, val) in pages {
            if let page = val as? [String: Any], let imageinfo = page["imageinfo"] as? [[String: Any]], let first = imageinfo.first, let u = first["url"] as? String { urls.append(u) }
        }
        return urls
    }

    private func fetchWikipediaImage(name: String, country: String) -> WikiImage? {
        let searchQuery = "\(name) \(country)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURLStr = "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(searchQuery)&format=json&origin=*&srlimit=1"
        guard let searchURL = URL(string: searchURLStr) else { return nil }
        let searchJSON = syncGET(url: searchURL)
        guard let root = searchJSON as? [String: Any], let query = root["query"] as? [String: Any], let search = query["search"] as? [[String: Any]], let first = search.first, let title = first["title"] as? String else { return nil }
        let pageTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let summaryURLStr = "https://en.wikipedia.org/api/rest_v1/page/summary/\(pageTitle)"
        guard let summaryURL = URL(string: summaryURLStr) else { return nil }
        let sumJSON = syncGET(url: summaryURL)
        if let obj = sumJSON as? [String: Any], let thumb = obj["thumbnail"] as? [String: Any], let source = thumb["source"] as? String {
            return WikiImage(url: source, license: nil)
        }
        return nil
    }

    // MARK: - Geocoding fallback
    private func geocodeApproximate(name: String, country: String) -> (Double, Double)? {
        let geo = CLGeocoder()
        var result: (Double, Double)?
        let group = DispatchGroup()
        group.enter()
        geo.geocodeAddressString("\(name), \(country)") { placemarks, _ in
            if let loc = placemarks?.first?.location {
                result = (loc.coordinate.latitude, loc.coordinate.longitude)
            }
            group.leave()
        }
        _ = group.wait(timeout: .now() + 10)
        // light pacing to respect rate limits
        Thread.sleep(forTimeInterval: 0.25)
        return result
    }

    // MARK: - Simple synchronous GET
    private func syncGET(url: URL) -> Any? {
        var result: Any? = nil
        let sem = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: url) { data, _, _ in
            defer { sem.signal() }
            guard let data = data else { return }
            result = try? JSONSerialization.jsonObject(with: data, options: [])
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 20)
        // Basic pacing to avoid hammering APIs
        Thread.sleep(forTimeInterval: 0.3)
        return result
    }
}
