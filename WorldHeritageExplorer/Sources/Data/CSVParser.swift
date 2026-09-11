//
//  CSVParser.swift
//  WorldHeritageExplorer
//
//  Created by Jane Lee on 10/31/25.
//

import Foundation
import CoreData
import CSV

struct CSVParser {
    /// Import whc001.csv into Core Data. Maps selected columns to Heritage attributes.
    static func importCSV(from url: URL, into context: NSManagedObjectContext) throws {
        guard let stream = InputStream(url: url) else { return }
        let reader = try CSVReader(stream: stream, hasHeaderRow: true)
        while reader.next() != nil {
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
            obj.setValue(reader["Images"], forKey: "galleryImageURLs")

            // --- new mappings for multilingual and metadata fields ---
            // Names
            obj.setValue(reader["Name FR"], forKey: "nameFR")
            obj.setValue(reader["Name ZH"], forKey: "nameZH")

            // Short descriptions (FR/ZH)
            obj.setValue(reader["Short Description FR"], forKey: "shortDescFR")
            obj.setValue(reader["Short Description ZH"], forKey: "shortDescZH")

            // Justification EN
            obj.setValue(reader["Justification EN"], forKey: "justificationEN")

            // Area (hectares) - try several possible header names
            if let areaStr = (reader["Area hectares"] ?? reader["Area (hectares)"] ?? reader["Area"]), !areaStr.isEmpty {
                let a = areaStr.trimmingCharacters(in: .whitespaces)
                if let areaVal = Double(a) {
                    // Core Data property is NSNumber? so box the double
                    obj.setValue(NSNumber(value: areaVal), forKey: "areaHectares")
                }
            }

            // Criteria - prefer combined 'Criteria' otherwise combine Cultural/Natural
            var crit = reader["Criteria"] ?? ""
            if crit.isEmpty {
                let c1 = reader["Cultural Criteria"] ?? ""
                let c2 = reader["Natural Criteria"] ?? ""
                let parts = [c1, c2].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                crit = parts.joined(separator: ",")
            }
            if !crit.isEmpty { obj.setValue(crit, forKey: "criteria") }

            // ISO code (for FlagKit), common header name: 'ISO Codes' or 'ISO Code'
            if let iso = (reader["ISO Codes"] ?? reader["ISO Code"])?.trimmingCharacters(in: .whitespacesAndNewlines), !iso.isEmpty {
                obj.setValue(iso.lowercased(), forKey: "isoCode")
            }

            // Transboundary - convert common truthy values
            if let tb = (reader["Transboundary"] ?? reader["Transboundary?"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !tb.isEmpty {
                let truthy = ["true", "yes", "1"]
                obj.setValue(truthy.contains(tb), forKey: "transboundary")
            } else {
                // ensure attribute exists but leave nil if empty
                obj.setValue(nil, forKey: "transboundary")
            }

            // Main Image Author
            obj.setValue(reader["Main Image Author"], forKey: "mainImageAuthor")
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

