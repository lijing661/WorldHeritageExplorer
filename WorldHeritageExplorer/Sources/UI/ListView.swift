//  ListView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.
//

import SwiftUI
import CoreData
import Kingfisher
import FlagKit

struct ListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("didImportCSV") private var didImportCSV = false

    @FetchRequest private var heritages: FetchedResults<NSManagedObject>

    @State private var showSearch = false
    @State private var searchText = ""
    @State private var prefetcher: ImagePrefetcher? = nil
    @State private var lastPrefetchKeys: Set<String> = []
    @State private var expandedCountries: Set<String> = []

    init() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Heritage")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        _heritages = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var filtered: [NSManagedObject] {
        let base = Array(heritages)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { obj in
            let name = (obj.value(forKey: "name") as? String)?.lowercased() ?? ""
            let country = (obj.value(forKey: "country") as? String)?.lowercased() ?? ""
            return name.contains(q.lowercased()) || country.contains(q.lowercased())
        }
    }

    // Whether we are actively searching (search bar visible and query non-empty)
    private var isSearching: Bool {
        showSearch && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Results to show in the search result list (already filtered by name/country)
    private var searchResults: [NSManagedObject] {
        filtered // could be further limited if needed
    }

    // Utility to split country strings into tokens used across the list
    private func splitCountries(_ raw: String?) -> [String] {
        guard let raw = raw, !raw.isEmpty else { return ["Unknown"] }
        let separators = CharacterSet(charactersIn: ",，、;/|")
        let parts = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? ["Unknown"] : parts
    }

    // Utility to split ISO codes from CSV (e.g., "AL, ME" -> ["al","me"]) 
    private func splitISOCodes(_ raw: String?) -> [String] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ",;|/ ")
        let parts = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return parts
    }

    private var countryGroups: [(name: String, items: [NSManagedObject], visited: Int, total: Int, isoCode: String?)] {
        // Build groups by splitting multi-country strings and assigning the same heritage into each country bucket
        var buckets: [String: [NSManagedObject]] = [:]
        var countryToISO: [String: String] = [:]

        for obj in Array(heritages) {
            // capture isoCode if present for mapping
            let isoRaw = (obj.value(forKey: "isoCode") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isoTokens = splitISOCodes(isoRaw)
            let countryTokens = splitCountries(obj.value(forKey: "country") as? String)

            // Try to align ISO tokens to country tokens by index when a heritage spans multiple countries.
            // Prefer authoritative country-name -> ISO lookup when available. Fallback to first iso token or raw iso string.
            for (idx, token) in countryTokens.enumerated() {
                buckets[token, default: []].append(obj)

                if countryToISO[token] == nil {
                    if isoTokens.count > idx {
                        countryToISO[token] = isoTokens[idx]
                    } else if let lookup = isoForCountry(token) {
                        // Prefer authoritative name->ISO mapping when available
                        countryToISO[token] = lookup
                    } else if let first = isoTokens.first {
                        countryToISO[token] = first
                    } else if let raw = isoRaw, !raw.isEmpty {
                        // try to pick a candidate from raw iso string
                        let candidates = splitISOCodes(raw)
                        if let c = candidates.first { countryToISO[token] = c }
                        else { countryToISO[token] = raw.lowercased() }
                    }
                }
            }
        }

        // Final pass: for any country bucket still missing an ISO, try the name->ISO lookup on the bucket key
        for key in buckets.keys {
            if countryToISO[key] == nil, let lookup = isoForCountry(key) {
                countryToISO[key] = lookup
            }
        }

        let result: [(name: String, items: [NSManagedObject], visited: Int, total: Int, isoCode: String?)] = buckets.map { (key, list) in
            // Deduplicate by objectID within each bucket (in case of repeated separators or duplicates)
            let uniqueItems: [NSManagedObject] = Dictionary(grouping: list, by: { $0.objectID }).compactMap { $0.value.first }
            let visitedCount = uniqueItems.reduce(0) { $0 + (((( $1.value(forKey: "isVisited") as? Bool) ?? false) ? 1 : 0)) }
            let sortedItems = uniqueItems.sorted { ($0.value(forKey: "name") as? String ?? "") < ($1.value(forKey: "name") as? String ?? "") }
            return (name: key, items: sortedItems, visited: visitedCount, total: uniqueItems.count, isoCode: countryToISO[key])
        }

        return result.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if showSearch {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search name or country", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                }
                Divider()
                // Add 50pt gap between search bar and list when search is visible
                if showSearch {
                    Color.clear.frame(height: 20)
                }

                if !didImportCSV {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在首次导入数据…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            Text("没有数据或无匹配结果")
                            Text("试试更短的关键词，或检查 CSV 导入")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                } else {
                    if isSearching {
                        // Flat search results list under the search bar
                        List {
                            Section(header:
                                        HStack {
                                            Text("匹配结果 (\(searchResults.count))")
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                            ) {
                                ForEach(searchResults, id: \.objectID) { item in
                                    NavigationLink(destination: HeritageDetailView(item: item)) {
                                        HeritageRow(item: item)
                                            .padding(.vertical, 2)
                                    }
                                    .listRowBackground(Color(.systemBackground))
                                }
                            }
                        }
                        .listStyle(.plain)
                        .onAppear { prefetchTopImages() }
                        .onChange(of: searchText) { _ in prefetchTopImages() }
                    } else {
                        List {
                            ForEach(Array(countryGroups.enumerated()), id: \.element.name) { index, group in
                                Group {
                                    CountryRow(index: index + 1, name: group.name, isoCode: group.isoCode, total: group.total, visited: group.visited, expanded: expandedCountries.contains(group.name)) {
                                        if expandedCountries.contains(group.name) {
                                            expandedCountries.remove(group.name)
                                        } else {
                                            expandedCountries.insert(group.name)
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color(.secondarySystemBackground))
                                    .listRowSeparator(.hidden)

                                    if expandedCountries.contains(group.name) {
                                        ForEach(group.items, id: \.objectID) { item in
                                            NavigationLink(destination: HeritageDetailView(item: item)) {
                                                HeritageRow(item: item)
                                                    .padding(.vertical, 2)
                                            }
                                            .listRowBackground(Color(.systemBackground))
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button {
                                                    // Collapse the country when tapping the down arrow
                                                    expandedCountries.remove(group.name)
                                                } label: {
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                        .foregroundColor(.white)
                                                }
                                                .tint(.green)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .onAppear { prefetchTopImages() }
                        .onChange(of: filtered.count) { _ in prefetchTopImages() }
                        .onChange(of: searchText) { _ in prefetchTopImages() }
                    }
                }
            }
        }
    }

    private func prefetchTopImages(limit: Int = 20) {
        let baseList = isSearching ? searchResults : filtered
        let urls: [URL] = baseList.prefix(limit).compactMap { obj in
            // prefer thumb
            if let s = obj.value(forKey: "mainThumbURL") as? String, let u = URL(string: s), !s.isEmpty { return u }
            if let s = obj.value(forKey: "mainImageURL") as? String, let u = URL(string: s), !s.isEmpty { return u }
            return nil
        }
        let keys = Set(urls.map { $0.absoluteString })
        guard !urls.isEmpty, keys != lastPrefetchKeys else { return }
        lastPrefetchKeys = keys
        prefetcher?.stop()
        let pf = ImagePrefetcher(
            urls: urls,
            options: [.backgroundDecode, .cacheOriginalImage],
            progressBlock: nil,
            completionHandler: nil
        )
        pf.maxConcurrentDownloads = 6
        prefetcher = pf
        pf.start()
    }

    private var header: some View {
        HStack {
            Button(action: { withAnimation { showSearch.toggle() } }) {
                Image(systemName: "magnifyingglass")
            }
            Spacer()
            Text("Heritages(\(heritages.count))")
                .font(.headline)
            Spacer()
            Button(action: { /* TODO: filter UI */ }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct HeritageRow: View {
    let item: NSManagedObject

    private func categoryIcon(for category: String?) -> String {
        switch (category ?? "").lowercased() {
        case let s where s.contains("cultural"): return "building.columns.fill"
        case let s where s.contains("natural"): return "leaf.fill"
        case let s where s.contains("mixed"): return "circle.lefthalf.filled"
        default: return "questionmark.circle"
        }
    }

    // New: return a color for the category icon
    private func categoryColor(for category: String?) -> Color {
        switch (category ?? "").lowercased() {
        case let s where s.contains("cultural"): return Color.yellow
        case let s where s.contains("natural"): return Color.green
        case let s where s.contains("mixed"): return Color.purple
        default: return Color.secondary
        }
    }

    // Helper: produce flag emoji from ISO alpha-2 code
    private func flagEmoji(from isoRaw: String?) -> String? {
        guard let iso = isoRaw?.trimmingCharacters(in: .whitespacesAndNewlines), iso.count == 2 else { return nil }
        let upper = iso.uppercased()
        var scalars: [UnicodeScalar] = []
        for ch in upper.unicodeScalars {
            guard let scalar = UnicodeScalar(127397 + ch.value) else { return nil }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    // Simplified flag view: use emoji for maximum compatibility.
    @ViewBuilder private func flagView(for item: NSManagedObject) -> some View {
        if let isoRaw = item.value(forKey: "isoCode") as? String, let emoji = flagEmoji(from: isoRaw) {
            Text(emoji)
                .font(.system(size: 14))
                .frame(width: 20, height: 14)
        } else {
            Rectangle().fill(Color.clear).frame(width: 20, height: 14)
        }
    }

    // Local utility to split country strings (HeritageRow scope)
    private func splitCountriesLocal(_ raw: String?) -> [String] {
        guard let raw = raw, !raw.isEmpty else { return ["Unknown"] }
        let separators = CharacterSet(charactersIn: ",，、;/|")
        let parts = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? ["Unknown"] : parts
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            let thumbStr = item.value(forKey: "mainThumbURL") as? String
            let urlStr = (thumbStr?.isEmpty ?? true) ? (item.value(forKey: "mainImageURL") as? String) : thumbStr
            if let urlStr, let url = URL(string: urlStr), !urlStr.isEmpty {
                KFImage(url)
                    .placeholder { skeleton }
                    .retry(maxCount: 2, interval: .seconds(2))
                    .cacheOriginalImage()
                    .backgroundDecode()
                    .downsampling(size: CGSize(width: 90 * UIScreen.main.scale, height: 90 * UIScreen.main.scale))
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipped()
                    .cornerRadius(8)
            } else {
                skeleton
                    .frame(width: 90, height: 90)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                // First line: name (up to 2 lines, regular weight, priority)
                Text((item.value(forKey: "name") as? String) ?? "—")
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                // Second line: country with flag or globe+count for multi-country
                HStack(spacing: 8) {
                    let countryRaw = item.value(forKey: "country") as? String
                    let countries = splitCountriesLocal(countryRaw)

                    if countries.count > 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            Text("\(countries.count)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Text(countries.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        flagView(for: item)

                        Text(countryRaw ?? "—")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0) // push third line to bottom only

                // Third line: category icon + favorite + visited (larger icons)
                HStack(spacing: 10) {
                    let cat = item.value(forKey: "category") as? String
                    Image(systemName: categoryIcon(for: cat))
                        .foregroundColor(categoryColor(for: cat))
                    Spacer()
                    let isVisited = (item.value(forKey: "isVisited") as? Bool) ?? false
                    Image(systemName: isVisited ? "checkmark.seal.fill" : "checkmark.seal")
                        .foregroundColor(isVisited ? .green : .secondary)
                        .font(.callout)
                    let isFavorite = (item.value(forKey: "isFavorite") as? Bool) ?? false
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .secondary)
                        .font(.callout)
                }
                .padding(.trailing, 2)
            }
            .frame(height: 90)
        }
        .padding(.vertical, 6)
    }

    // 骨架占位
    private var skeleton: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(0.15))
            .overlay(
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .gray.opacity(0.6)))
            )
    }
}

private struct CountryRow: View {
    let index: Int
    let name: String
    let isoCode: String?
    let total: Int
    let visited: Int
    let expanded: Bool
    let onToggle: () -> Void

    private var percentText: String {
        guard total > 0 else { return "0.0%" }
        let p = (Double(visited) / Double(total)) * 100.0
        return String(format: "%.1f%%", p)
    }

    private var indexText: String { String(format: "%03d", index) }

    var body: some View {
        HStack(spacing: 12) {
            Text(indexText)
                .font(.footnote)
                .foregroundColor(.secondary)
                .monospacedDigit()

            // Inline flag emoji between index and country name
            if let emoji = flagEmoji(from: isoCode) {
                Text(emoji)
                    .font(.system(size: 24))
                    .frame(width: 34, height: 24)
            } else {
                // small spacer to keep alignment
                Rectangle().fill(Color.clear).frame(width: 34, height: 24)
            }

            Text(name)
                .font(.body)
            Spacer()
            Text("\(visited)/\(total)  \(percentText)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Button(action: onToggle) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(expanded ? Color(.secondarySystemBackground) : Color.white)
        .if(!expanded) { view in
            view
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 2)
                // reduced spacing to 4pt (~1/12 of height) for tighter card stack
                .padding(.vertical, 4)
        }
        .if(expanded) { view in
            view
                .padding(.horizontal, 0)
                .padding(.vertical, 0)
        }
    }
}

private extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

#Preview {
    ListView()
}
