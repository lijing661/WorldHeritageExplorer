//
//  ContentView.swift
//  WorldHeritageExplorer
//
//  Created by Jane Lee on 10/18/25.
//

import SwiftUI
import CoreData

// Add a shared tab enum so other views (e.g., Map) can switch tabs
enum MainTab: Hashable { case list, map, mine, settings }

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("didImportCSV") private var didImportCSV = false

    // Track selected tab
    @State private var selectedTab: MainTab = .list

    var body: some View {
        TabView(selection: $selectedTab) {
            ListView()
                .tabItem { Label("List", systemImage: "list.bullet") }
                .tag(MainTab.list)

            // Pass selection binding to Map so it can switch back to List
            MapTabView(selectedTab: $selectedTab)
                .tabItem { Label("Map", systemImage: "map") }
                .tag(MainTab.map)

            MineView()
                .tabItem { Label("Mine", systemImage: "person.crop.circle") }
                .tag(MainTab.mine)

            SettingsAboutView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
    }
}

#Preview {
    ContentView()
}
