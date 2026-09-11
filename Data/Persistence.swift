// Persistence.swift
// Core Data stack with lightweight migration enabled

import Foundation
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "HeritageExplorer")

        // Enable lightweight migration
        if let desc = container.persistentStoreDescriptions.first {
            desc.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            desc.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            if inMemory {
                desc.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // Replace this with proper error handling for production apps
                fatalError("Unresolved error loading persistent stores: \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                // Handle save error appropriately in app
                fatalError("Unresolved error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
