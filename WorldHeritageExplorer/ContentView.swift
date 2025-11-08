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

    @FetchRequest var heritages: FetchedResults<NSManagedObject>

    init() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Heritage")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        _heritages = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        NavigationView {
            Group {
                if !didImportCSV {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在首次导入数据…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    if heritages.isEmpty {
                        VStack(spacing: 8) {
                            Text("没有数据")
                            Text("请确认 CSV 已打包并重启应用")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        List(heritages.prefix(100), id: \.objectID) { item in
                            Text((item.value(forKey: "name") as? String) ?? "—")
                        }
                    }
                }
            }
            .navigationTitle("Heritages (\(heritages.count))")
        }
    }
}

#Preview {
    ContentView()
}
