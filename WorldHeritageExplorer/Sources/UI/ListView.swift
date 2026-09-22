//  ListView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.
//

import SwiftUI
import CoreData
import Kingfisher
import FlagKit

// Notification used by banner messages
private extension Notification.Name {
    static let heritageAction = Notification.Name("heritageAction")
}

struct ListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("didImportCSV") private var didImportCSV = false

    @FetchRequest private var heritages: FetchedResults<NSManagedObject>

    @State private var showSearch = false
    @State private var searchText = ""
    @State private var prefetcher: ImagePrefetcher? = nil
    @State private var lastPrefetchKeys: Set<String> = []
    @State private var expandedCountries: Set<String> = []
    @State private var selectedItem: NSManagedObject? = nil
    @State private var isActiveDetail: Bool = false

    // Banner state for top notifications
    @State private var bannerText: String? = nil
    @State private var bannerIcon: String = "checkmark.circle"
    @State private var showBanner: Bool = false

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

    // Prefetch top thumbnail images (used by .onAppear/.onChange in body)
    private func prefetchTopImages(limit: Int = 20) {
        let baseList = isSearching ? searchResults : filtered
        // Only prefetch pre-generated thumbnails to avoid downloading/caching large originals
        let urls: [URL] = baseList.prefix(limit).compactMap { obj in
            if let s = obj.value(forKey: "mainThumbURL") as? String, let u = URL(string: s), !s.isEmpty { return u }
            return nil
        }
        let keys = Set(urls.map { $0.absoluteString })
        guard !urls.isEmpty, keys != lastPrefetchKeys else { return }
        lastPrefetchKeys = keys
        prefetcher?.stop()
        let pf = ImagePrefetcher(
            urls: urls,
            options: [.backgroundDecode],
            progressBlock: nil,
            completionHandler: nil
        )
        pf.maxConcurrentDownloads = 6
        prefetcher = pf
        pf.start()
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

                // Hidden navigation link for programmatic navigation (prevents chevrons)
                NavigationLink(destination: Group {
                    if let sel = selectedItem { HeritageDetailView(item: sel) }
                }, isActive: $isActiveDetail) { EmptyView() }
                .hidden()

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
                                    HeritageRow(item: item)
                                        .padding(.vertical, 2)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedItem = item
                                            isActiveDetail = true
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
                                            HeritageRow(item: item)
                                                .padding(.vertical, 2)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    selectedItem = item
                                                    isActiveDetail = true
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
            // Listen for toggle actions from child views and show a brief banner
            .onReceive(NotificationCenter.default.publisher(for: .heritageAction)) { note in
                guard let info = note.userInfo as? [String: Any],
                      let action = info["action"] as? String,
                      let isOn = info["isOn"] as? Bool else { return }

                    switch (action, isOn) {
                    case ("visited", true):
                        bannerIcon = "checkmark.circle"
                        bannerText = "Mark as visited."
                    case ("visited", false):
                        bannerIcon = "xmark.circle"
                        bannerText = "Removed from visited list!"
                    case ("favorite", true):
                        bannerIcon = "checkmark.circle"
                        bannerText = "Mark as favorite."
                    case ("favorite", false):
                        bannerIcon = "xmark.circle"
                        bannerText = "Removed from favorite list!"
                    default:
                        return
                    }

                    withAnimation(.spring()) { showBanner = true }
                    // auto-dismiss after 1.6s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeOut) { showBanner = false }
                    }
            }
            // top overlay banner
            .overlay(alignment: .top) {
                if showBanner, let text = bannerText {
                    HStack(spacing: 10) {
                        Image(systemName: bannerIcon)
                            .foregroundColor(.white)
                        Text(text)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.top, 10)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                }
            }
        }

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

    // Helper: simple category icon + color used by trailing controls
    private func categoryIcon(for category: String?) -> String {
        switch (category ?? "").lowercased() {
        case let s where s.contains("cultural"): return "building.columns.fill"
        case let s where s.contains("natural"): return "leaf.fill"
        case let s where s.contains("mixed"): return "circle.lefthalf.filled"
        default: return "questionmark.circle"
        }
    }

    private func categoryColor(for category: String?) -> Color {
        switch (category ?? "").lowercased() {
        case let s where s.contains("cultural"): return Color.yellow
        case let s where s.contains("natural"): return Color.green
        case let s where s.contains("mixed"): return Color.purple
        default: return Color.secondary
        }
    }

    @ViewBuilder
    private func leadingRowContent(for item: NSManagedObject) -> some View {
        HStack(alignment: .center, spacing: 12) {
            let thumbStr = item.value(forKey: "mainThumbURL") as? String
            let urlStr = (thumbStr?.isEmpty ?? true) ? (item.value(forKey: "mainImageURL") as? String) : thumbStr
            if let urlStr, let url = URL(string: urlStr), !urlStr.isEmpty {
                KFImage(url)
                    .placeholder { RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)).frame(width: 90, height: 90) }
                    .retry(maxCount: 2, interval: .seconds(2))
                    .backgroundDecode()
                    .downsampling(size: CGSize(width: 90 * UIScreen.main.scale, height: 90 * UIScreen.main.scale))
                    .fade(duration: 0.25)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)).frame(width: 90, height: 90)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text((item.value(forKey: "name") as? String) ?? "—")
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                let countryRaw = item.value(forKey: "country") as? String
                Text(countryRaw ?? "—")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 90)
        }
    }

    @ViewBuilder
    private func trailingControls(for item: NSManagedObject) -> some View {
        HStack(spacing: 10) {
            let cat = item.value(forKey: "category") as? String
            Image(systemName: categoryIcon(for: cat))
                .foregroundColor(categoryColor(for: cat))

            let isVisited = (item.value(forKey: "isVisited") as? Bool) ?? false
            Button {
                let new = !isVisited
                item.setValue(new, forKey: "isVisited")
                do { try viewContext.save() } catch { /* ignore */ }
                NotificationCenter.default.post(name: .heritageAction, object: nil, userInfo: ["action": "visited", "isOn": new])
            } label: {
                Image(systemName: isVisited ? "checkmark.seal.fill" : "checkmark.seal")
                    .foregroundColor(isVisited ? .green : .secondary)
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.trailing, 4)

            let isFavorite = (item.value(forKey: "isFavorite") as? Bool) ?? false
            Button {
                let new = !isFavorite
                item.setValue(new, forKey: "isFavorite")
                do { try viewContext.save() } catch { /* ignore */ }
                NotificationCenter.default.post(name: .heritageAction, object: nil, userInfo: ["action": "favorite", "isOn": new])
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(isFavorite ? .red : .secondary)
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.trailing, 2)
        }
        .frame(height: 90)
        .padding(.trailing, 8)
    }

}

private struct HeritageRow: View {
    @ObservedObject var item: NSManagedObject

    @Environment(\.managedObjectContext) private var viewContext

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
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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

                // Third line: category icon + favorite + visited (larger icons) — now tappable
                HStack(spacing: 4) {
                    let cat = item.value(forKey: "category") as? String
                    Image(systemName: categoryIcon(for: cat))
                        .foregroundColor(categoryColor(for: cat))

                    Spacer()

                    // Use circle variants for visited to get a simple ring + checkmark
                    let isVisited = (item.value(forKey: "isVisited") as? Bool) ?? false
                    Button {
                        let new = !isVisited
                        item.setValue(new, forKey: "isVisited")
                        do { try viewContext.save() } catch { /* ignore */ }
                        NotificationCenter.default.post(name: .heritageAction, object: nil, userInfo: ["action": "visited", "isOn": new])
                    } label: {
                        Image(systemName: isVisited ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(isVisited ? .green : .secondary)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    let isFavorite = (item.value(forKey: "isFavorite") as? Bool) ?? false
                    Button {
                        let new = !isFavorite
                        item.setValue(new, forKey: "isFavorite")
                        do { try viewContext.save() } catch { /* ignore */ }
                        NotificationCenter.default.post(name: .heritageAction, object: nil, userInfo: ["action": "favorite", "isOn": new])
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? .red : .secondary)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
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
