//
//  ContentView.swift
//  WorldHeritageExplorer
//
//  Created by Jane Lee on 10/18/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("didImportCSV") private var didImportCSV = false

    var body: some View {
        TabView {
            ListView()
                .tabItem { Label("List", systemImage: "list.bullet") }
            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }
            MineView()
                .tabItem { Label("Mine", systemImage: "person.crop.circle") }
            SettingsAboutView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
}
