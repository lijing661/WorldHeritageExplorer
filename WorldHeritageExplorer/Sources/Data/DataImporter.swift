//
//  DataImporter.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/1/25.
//

import Foundation
import CoreData
import CSV

enum DataImporter {
    // Extract a 4-digit year from a free-form string, e.g., "1997", "1997-2000", etc.
    private static func extractYear(from text: String?) -> NSNumber? {
        guard let text = text, !text.isEmpty else { return nil }
        do {
            let regex = try NSRegularExpression(pattern: "\\b(1[0-9]{3}|20[0-9]{2})\\b")
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = regex.firstMatch(in: text, options: [], range: range),
               let r = Range(m.range(at: 1), in: text) {
                if let year = Int(text[r]) { return NSNumber(value: year) }
            }
        } catch { /* ignore */ }
        return nil
    }

    static func importInitialCSVIfNeeded() async {
        let container = PersistenceController.shared.container
        // Run entirely on a background context to avoid main-thread hangs
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    let fetch: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "Heritage")
                    fetch.fetchLimit = 1
                    let existing = try context.count(for: fetch)
                    guard existing == 0 else { cont.resume(); return }

                    try self.performImport(into: context)
                    cont.resume()
                } catch {
                    print("CSV import failed: \(error)")
                    cont.resume()
                }
            }
        }
    }

    // Force re-import: delete all Heritage then import again
    static func reimportFromCSV() async {
        let container = PersistenceController.shared.container
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    // Wipe all existing Heritage via batch delete
                    let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Heritage")
                    let delete = NSBatchDeleteRequest(fetchRequest: fetch)
                    delete.resultType = .resultTypeObjectIDs
                    let result = try context.execute(delete) as? NSBatchDeleteResult
                    if let ids = result?.result as? [NSManagedObjectID] {
                        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: ids]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [container.viewContext])
                    }

                    // Import again
                    try self.performImport(into: context)
                    cont.resume()
                } catch {
                    print("CSV re-import failed: \(error)")
                    cont.resume()
                }
            }
        }
    }

    // Shared import routine used by initial import and reimport
    private static func performImport(into context: NSManagedObjectContext) throws {
        guard let url = Bundle.main.url(forResource: "whc001", withExtension: "csv") else {
            print("CSV not found in bundle")
            return
        }
        let stream = InputStream(url: url)!
        let reader = try CSVReader(stream: stream, hasHeaderRow: true)

        var inserted = 0
        while reader.next() != nil {
            autoreleasepool {
                let obj = NSEntityDescription.insertNewObject(forEntityName: "Heritage", into: context)
                obj.setValue(reader["Name EN"], forKey: "name")
                obj.setValue(reader["States Names"], forKey: "country")
                obj.setValue(reader["Region"], forKey: "region")

                if let coord = reader["Coordinates"], !coord.isEmpty {
                    let comps = coord.split(separator: ",")
                    if comps.count == 2 {
                        if let lat = Double(comps[0].trimmingCharacters(in: .whitespaces)),
                           let lon = Double(comps[1].trimmingCharacters(in: .whitespaces)) {
                            obj.setValue(lat, forKey: "latitude")
                            obj.setValue(lon, forKey: "longitude")
                        }
                    }
                }

                obj.setValue(reader["Category"], forKey: "category")
                obj.setValue(reader["Short Description EN"], forKey: "shortDes")
                obj.setValue(reader["Main Image"], forKey: "mainImageURL")
                if let imgs = reader["Images"] { obj.setValue(imgs, forKey: "galleryImageURLs") }

                // Map 'Date inscribed' to yearInscribed; ignore 'Secondary dates'
                let dateCols = ["Date inscribed", "Date Inscribed", "date inscribed"]
                var yearNum: NSNumber? = nil
                for key in dateCols {
                    if let v = reader[key], let y = extractYear(from: v) { yearNum = y; break }
                }
                if let y = yearNum { obj.setValue(y, forKey: "yearInscribed") }

                inserted += 1
                if inserted % 200 == 0 {
                    do { try context.save(); context.reset() } catch { print("Batch save failed: \(error)") }
                }
            }
        }
        if context.hasChanges { try context.save() }
    }
}
