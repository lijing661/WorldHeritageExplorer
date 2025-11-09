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
        }
        if context.hasChanges {
            try context.save()
        }
    }
}

