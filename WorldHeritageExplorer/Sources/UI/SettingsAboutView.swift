//  SettingsAboutView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.
//

import SwiftUI

struct SettingsAboutView: View {
    @AppStorage("didImportCSV") private var didImportCSV = false

    var body: some View {
        NavigationView {
            List {
                Section("Settings") {
                    Toggle("Use Cellular Data", isOn: .constant(true))
                    Toggle("Load Images", isOn: .constant(true))
                    Button(role: .destructive) {
                        Task {
                            await DataImporter.reimportFromCSV()
                            didImportCSV = true // keep flag true after manual reimport
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                            Text("Re-import CSV (reset data)")
                        }
                    }
                }
                Section("About") {
                    HStack { Text("App"); Spacer(); Text("WorldHeritageExplorer").foregroundColor(.secondary) }
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Settings & About")
        }
    }
}

#Preview { SettingsAboutView() }
