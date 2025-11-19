//
//  WorldHeritageExplorerApp.swift
//  WorldHeritageExplorer
//
//  Created by Jane Lee on 10/18/25.
//

import SwiftUI
import CoreData
import Kingfisher

@main
struct WorldHeritageExplorerApp: App {
    private let persistenceController = PersistenceController.shared

    @AppStorage("didImportCSV") private var didImportCSV = false

    init() {
        ImageLoaderConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    if !didImportCSV {
                        await DataImporter.importInitialCSVIfNeeded()
                        didImportCSV = true
                    }
                    // Start enrichment after initial import
                    EnrichmentService.shared.startIfNeeded(container: persistenceController.container)
                }
        }
    }
}
