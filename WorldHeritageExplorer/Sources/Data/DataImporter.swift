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

                    guard let url = Bundle.main.url(forResource: "whc001", withExtension: "csv") else {
                        print("CSV not found in bundle")
                        cont.resume(); return
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

                            inserted += 1
                            if inserted % 200 == 0 { // batch save
                                do { try context.save(); context.reset() } catch { print("Batch save failed: \(error)") }
                            }
                        }
                    }
                    if context.hasChanges { try context.save() }
                    cont.resume()
                } catch {
                    print("CSV import failed: \(error)")
                    cont.resume()
                }
            }
        }
    }
}
