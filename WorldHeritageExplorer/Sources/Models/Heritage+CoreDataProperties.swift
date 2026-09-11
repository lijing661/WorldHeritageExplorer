// Automatically generated Core Data properties for Heritage
// ...existing code...

import Foundation
import CoreData

extension Heritage {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Heritage> {
        return NSFetchRequest<Heritage>(entityName: "Heritage")
    }

    @NSManaged public var category: String?
    @NSManaged public var country: String?
    @NSManaged public var galleryImageURLs: String?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var isVisited: Bool
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var mainImageURL: String?
    @NSManaged public var mainThumbURL: String?
    @NSManaged public var name: String?
    @NSManaged public var region: String?
    @NSManaged public var shortDes: String?
    @NSManaged public var unqiueID: String?
    @NSManaged public var yearInscribed: Int16
    @NSManaged public var enrichedAt: Date?
    @NSManaged public var dataSource: String?
    @NSManaged public var imageLicense: String?
    @NSManaged public var wikidataQID: String?
    @NSManaged public var commonsCategory: String?

    // New multilingual and metadata properties
    @NSManaged public var nameFR: String?
    @NSManaged public var nameZH: String?
    @NSManaged public var shortDescFR: String?
    @NSManaged public var shortDescZH: String?
    @NSManaged public var justificationEN: String?
    @NSManaged public var areaHectares: NSNumber? // Optional Double boxed in NSNumber
    @NSManaged public var criteria: String?
    @NSManaged public var isoCode: String?
    @NSManaged public var transboundary: NSNumber? // Optional Bool boxed in NSNumber
    @NSManaged public var mainImageAuthor: String?
}

extension Heritage : Identifiable {
}