//  MineView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.
//

import SwiftUI
import CoreData
import UIKit

#if canImport(FlagKit)
import FlagKit
#endif

struct MineView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var heritages: FetchedResults<NSManagedObject>

    init() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Heritage")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        _heritages = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var totalCount: Int { heritages.count }
    private var visitedCount: Int {
        heritages.reduce(0) { $0 + (((( $1.value(forKey: "isVisited") as? Bool) ?? false) ? 1 : 0)) }
    }

    private var culturalTotal: Int { heritages.reduce(0) { $0 + (((($1.value(forKey: "category") as? String)?.lowercased().contains("cultural") ?? false) ? 1 : 0)) } }
    private var naturalTotal: Int { heritages.reduce(0) { $0 + (((($1.value(forKey: "category") as? String)?.lowercased().contains("natural") ?? false) ? 1 : 0)) } }
    private var mixedTotal: Int { heritages.reduce(0) { $0 + (((($1.value(forKey: "category") as? String)?.lowercased().contains("mixed") ?? false) ? 1 : 0)) } }

    private var culturalVisited: Int { heritages.reduce(0) { $0 + (((($1.value(forKey: "category") as? String)?.lowercased().contains("cultural") ?? false) && ((( $1.value(forKey: "isVisited") as? Bool) ?? false)) ) ? 1 : 0) } }
    private var naturalVisited: Int { heritages.reduce(0) { $0 + (((($1.value(forKey: "category") as? String)?.lowercased().contains("natural") ?? false) && ((( $1.value(forKey: "isVisited") as? Bool) ?? false)) ) ? 1 : 0) } }
    private var mixedVisited: Int { heritages.reduce(0) { $0 + (((($1.value(forKey: "category") as? String)?.lowercased().contains("mixed") ?? false) && ((( $1.value(forKey: "isVisited") as? Bool) ?? false)) ) ? 1 : 0) } }

    // Regions to display under "By Region"
    private let regions: [String] = [
        "Africa",
        "Arab States",
        "Asia and the Pacific",
        "Europe and North America",
        "Latin America and the Caribbean"
    ]

    private func regionTotal(_ name: String) -> Int {
        let key = name.lowercased()
        return heritages.reduce(0) { acc, obj in
            let region = (obj.value(forKey: "region") as? String)?.lowercased() ?? ""
            return acc + ((region == key) ? 1 : 0)
        }
    }

    private func regionVisited(_ name: String) -> Int {
        let key = name.lowercased()
        return heritages.reduce(0) { acc, obj in
            let region = (obj.value(forKey: "region") as? String)?.lowercased() ?? ""
            let visited = (obj.value(forKey: "isVisited") as? Bool) ?? false
            return acc + ((region == key && visited) ? 1 : 0)
        }
    }

    private func colorForRegion(_ name: String) -> Color {
        switch name {
        case "Africa": return Color.blue
        case "Arab States": return Color.green
        case "Asia and the Pacific": return Color.orange
        case "Europe and North America": return Color.purple
        case "Latin America and the Caribbean": return Color.pink
        default: return Color.gray
        }
    }

    private func percentString(_ visited: Int, _ total: Int) -> String {
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", (Double(visited) / Double(total)) * 100.0)
    }

    // List of unique visited country ISO codes (uppercase, two-letter)
    private var visitedCountryISOs: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for obj in heritages {
            let visited = (obj.value(forKey: "isVisited") as? Bool) ?? false
            guard visited else { continue }
            if let iso = (obj.value(forKey: "isoCode") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), iso.count == 2 {
                let up = iso.uppercased()
                if !seen.contains(up) {
                    seen.insert(up)
                    list.append(up)
                }
            }
        }
        return list
    }

    // Convert ISO country code (2-letter) to flag emoji
    private func flagEmoji(for iso: String) -> String {
        let code = iso.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return "🏳️" }
        var flag = ""
        for scalar in code.unicodeScalars {
            if let uni = UnicodeScalar(127397 + scalar.value) {
                flag.unicodeScalars.append(uni)
            }
        }
        return flag
    }

    // MARK: - FlagKit snapshot helpers and local-first loader
    private static let flagCache = NSCache<NSString, UIImage>()

    private func snapshot<V: View>(_ view: V, size: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        var image: UIImage?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            image = renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.0)
        return image
    }

    #if canImport(FlagKit)
    private func tryFlagKitSnapshot(countryCode: String) -> UIImage? {
        // Avoid directly constructing Flag view (API varies between integrations and
        // may not conform to SwiftUI.View in some setups). Instead prefer loading
        // packaged flag images from the FlagKit bundle (or the app bundle when
        // assets were copied in).
        let candidates = [countryCode, countryCode.lowercased(), countryCode.uppercased(), "flag_\(countryCode)", "flag_\(countryCode.lowercased())"]
        let candidateClassNames = ["FKFlag", "FlagKit", "Flag"]

        for cn in candidateClassNames {
            if let cls = NSClassFromString(cn) {
                let bundle = Bundle(for: cls)
                for name in candidates {
                    if let img = UIImage(named: name, in: bundle, compatibleWith: nil) { return img }
                    if let path = bundle.path(forResource: name, ofType: "png"), let img = UIImage(contentsOfFile: path) { return img }
                }
            }
        }

        // Also try the main app bundle in case assets were copied into the app's
        // Assets.xcassets (common workflow when including FlagKit assets manually).
        for name in candidates {
            if let img = UIImage(named: name) { return img }
        }

        return nil
    }
    #endif

    private func flagUIImage(for iso: String) -> UIImage? {
        let code = iso.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty else { return nil }
        if let cached = MineView.flagCache.object(forKey: code as NSString) { return cached }

        // 1) Prefer FlagKit SwiftUI rendering when available
        #if canImport(FlagKit)
        if let fkImage = tryFlagKitSnapshot(countryCode: code) {
            MineView.flagCache.setObject(fkImage, forKey: code as NSString)
            return fkImage
        }
        #endif

        // 2) Try main bundle and framework bundles for a named asset (png/jpg)
        if let img = UIImage(named: code) {
            MineView.flagCache.setObject(img, forKey: code as NSString)
            return img
        }

        let bundles = Array(Set(Bundle.allBundles + Bundle.allFrameworks))
        for bundle in bundles {
            if let img = UIImage(named: code, in: bundle, compatibleWith: nil) {
                MineView.flagCache.setObject(img, forKey: code as NSString)
                return img
            }
            if let path = bundle.path(forResource: code, ofType: "png"), let img = UIImage(contentsOfFile: path) {
                MineView.flagCache.setObject(img, forKey: code as NSString)
                return img
            }
        }

        // 3) Fallback to emoji rendering
        let emoji = flagEmoji(for: iso)
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            UIColor.clear.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14), .paragraphStyle: paragraph]
            let att = NSAttributedString(string: emoji, attributes: attrs)
            let rect = CGRect(x: 0, y: (size.height - 18) / 2.0, width: size.width, height: 18)
            att.draw(in: rect)
        }
        MineView.flagCache.setObject(img, forKey: code as NSString)
        return img
    }

    // Compute per-country visited percent (0.0 - 1.0) based on Core Data `heritages` fetch
    private func countryVisitPercent(_ iso: String) -> Double {
        let code = iso.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return 0.0 }
        let items = heritages.filter { ((($0.value(forKey: "isoCode") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) == code) }
        let total = items.count
        if total == 0 { return 0.0 }
        let visited = items.reduce(0) { $0 + ( ((( $1.value(forKey: "isVisited") as? Bool) ?? false) ? 1 : 0) ) }
        return Double(visited) / Double(total)
    }

    // Return (visited, total) counts for a given country ISO
    private func countryVisitCounts(_ iso: String) -> (visited: Int, total: Int) {
        let code = iso.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return (0, 0) }
        let items = heritages.filter { ((($0.value(forKey: "isoCode") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) == code) }
        let total = items.count
        if total == 0 { return (0, 0) }
        let visited = items.reduce(0) { $0 + ( ((( $1.value(forKey: "isVisited") as? Bool) ?? false) ? 1 : 0) ) }
        return (visited, total)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    // Title row
                    HStack {
                        Text("My Info")
                            .font(.title2)
                            .bold()
                        Spacer()
                    }
                    .padding(.horizontal, 10)

                    // First layer: large card with circular percent and text
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)

                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("You visited")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(visitedCount)/ \(totalCount) of the inscribed sites")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.leading, 16)

                            Spacer()

                            CircularPercentView(visited: visitedCount, total: totalCount)
                                .frame(width: 120, height: 120)
                                .padding(.trailing, 16)
                        }
                    }
                    .frame(height: 150)
                    .padding(.horizontal, 10)

                    // Second layer: two white cards (side-by-side)
                    HStack(spacing: 10) {
                        CardPlaceholder(title: "Visited")
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                        CardPlaceholder(title: "Favorites")
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 150)
                    .padding(.bottom, 10) // ensure space before the "By category" title

                    // Title and category box (ensure box is entirely below the title)
                    VStack(spacing: 8) {
                        HStack {
                            Text("By category")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal, 10)

                        // Category breakdown box (below the title) — increased height and tighter spacing
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                            .overlay(
                                VStack(spacing: 6) {
                                    // Cultural
                                    categoryRow(title: "Cultural", visited: culturalVisited, total: culturalTotal)
                                    progressBar(color: Color.blue, progress: (culturalTotal > 0 ? Double(culturalVisited) / Double(culturalTotal) : 0.0))

                                    // Natural
                                    categoryRow(title: "Natural", visited: naturalVisited, total: naturalTotal)
                                    progressBar(color: Color.green, progress: (naturalTotal > 0 ? Double(naturalVisited) / Double(naturalTotal) : 0.0))

                                    // Mixed
                                    categoryRow(title: "Mixed", visited: mixedVisited, total: mixedTotal)
                                    // purple progress under Mixed
                                    progressBar(color: Color.purple, progress: (mixedTotal > 0 ? Double(mixedVisited) / Double(mixedTotal) : 0.0))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                            )
                            .frame(height: 200)
                            .padding(.horizontal, 10)
                    }
                    .padding(.top, 0)

                    // By Region title
                    HStack {
                        Text("By Region")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 10)

                    // Region breakdown box (white rounded rectangle, height 350)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                        .overlay(
                            VStack(spacing: 8) {
                                ForEach(regions, id: \.self) { reg in
                                    let tot = regionTotal(reg)
                                    let vis = regionVisited(reg)
                                    categoryRow(title: reg, visited: vis, total: tot)
                                    progressBar(color: colorForRegion(reg), progress: (tot > 0 ? Double(vis) / Double(tot) : 0.0))
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                        )
                        .frame(height: 350)
                        .padding(.horizontal, 10)

                    // Flag Collection title
                    HStack {
                        Text("Flag Collection")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 10)

                    // Flag Collection box: white, borderless, same horizontal inset and a height of 300
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
                        .overlay(
                            // Put the grid inside a vertical ScrollView so content can scroll when items exceed the visible capacity
                            ScrollView(.vertical, showsIndicators: true) {
                                Group {
                                    if visitedCountryISOs.isEmpty {
                                        VStack {
                                            Spacer()
                                            Text("No visited countries yet")
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                    } else {
                                        let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                            ForEach(visitedCountryISOs, id: \.self) { iso in
                                                NavigationLink(destination: CountryHeritageListView(iso: iso)) {
                                                    HStack(spacing: 8) {
                                                        let counts = countryVisitCounts(iso)
                                                        let percent = (counts.total > 0) ? Double(counts.visited) / Double(counts.total) : 0.0
                                                        let percentText = String(format: "%.1f%%", percent * 100.0)

                                                        // Flag with circular progress ring
                                                        ZStack {
                                                            // outer ring size slightly larger than image to avoid overlap
                                                            Circle()
                                                                .stroke(Color.gray.opacity(0.18), lineWidth: 2)
                                                                .frame(width: 28, height: 28)

                                                            Circle()
                                                                .trim(from: 0, to: CGFloat(min(max(percent, 0.0), 1.0)))
                                                                .stroke(
                                                                    // solid color: orange for <100%, green for 100%
                                                                    (percent >= 1.0 ? Color.green : Color.orange),
                                                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                                                )
                                                                .rotationEffect(.degrees(-90))
                                                                .frame(width: 28, height: 28)

                                                            if let ui = flagUIImage(for: iso) {
                                                                Image(uiImage: ui)
                                                                    .resizable()
                                                                    .scaledToFill()
                                                                    .frame(width: 24, height: 24)
                                                                    .clipShape(Circle())
                                                            } else {
                                                                let emoji = flagEmoji(for: iso)
                                                                ZStack {
                                                                    Circle()
                                                                        .fill(Color(.systemGray6))
                                                                    Text(emoji)
                                                                        .font(.system(size: 12))
                                                                }
                                                                .frame(width: 24, height: 24)
                                                            }
                                                        }

                                                        // caption: localized country name + (visited/total percent)
                                                        let countryName = Locale.current.localizedString(forRegionCode: iso) ?? iso
                                                        VStack(alignment: .leading, spacing: 0) {
                                                            Text(countryName)
                                                                .font(.caption2)
                                                                .lineLimit(1)
                                                                .foregroundColor(.primary)
                                                            Text("(\(counts.visited)/\(counts.total) \(percentText))")
                                                                .font(.caption2)
                                                                .foregroundColor(.primary)
                                                        }
                                                        .fixedSize(horizontal: false, vertical: true)
                                                    }
                                                    .padding(.vertical, 4)
                                                }
                                            }
                                        }
                                        .padding(.top, 8) // ensure grid starts near the top
                                        .padding(.horizontal, 8)
                                    }
                                }
                            }
                            , alignment: .topLeading
                        )
                        .frame(height: 300)
                        .padding(.horizontal, 10)

                    Spacer(minLength: 20)
                }
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGray6).ignoresSafeArea())
        }
    }

    // New: list view showing Heritage sites for one country
    private struct CountryHeritageListView: View {
        let iso: String
        @Environment(\.managedObjectContext) private var viewContext
        @FetchRequest private var items: FetchedResults<NSManagedObject>

        init(iso: String) {
            self.iso = iso
            let req = NSFetchRequest<NSManagedObject>(entityName: "Heritage")
            req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            req.predicate = NSPredicate(format: "isoCode ==[c] %@", iso)
            _items = FetchRequest(fetchRequest: req, animation: .default)
        }

        var body: some View {
            List {
                if items.isEmpty {
                    Text("No sites for \(Locale.current.localizedString(forRegionCode: iso) ?? iso)")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(items, id: \.objectID) { obj in
                        // Safely read attributes to avoid valueForUndefinedKey crashes
                        let name = (obj.entity.attributesByName.keys.contains("name") ? (obj.value(forKey: "name") as? String) : nil) ?? "Unknown"
                        let location = (obj.entity.attributesByName.keys.contains("location") ? (obj.value(forKey: "location") as? String) : nil)

                        HStack {
                            VStack(alignment: .leading) {
                                Text(name)
                                    .font(.body)
                                if let loc = location, !loc.isEmpty {
                                    Text(loc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if (obj.entity.attributesByName.keys.contains("isVisited") ? ((obj.value(forKey: "isVisited") as? Bool) ?? false) : false) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle(Locale.current.localizedString(forRegionCode: iso) ?? iso)
        }
    }

    @ViewBuilder
    private func categoryRow(title: String, visited: Int, total: Int) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text("\(visited)/\(max(total, 0))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(percentString(visited, max(total, 1)))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
    
    @ViewBuilder
    private func progressBar(color: Color, progress: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(.systemGray5))
                .frame(height: 6)
            Capsule()
                .fill(color)
                .frame(height: 6)
                .scaleEffect(x: max(0.0, CGFloat(progress)), y: 1.0, anchor: .leading)
                .shadow(color: color.opacity(0.25), radius: 2, x: 0, y: 1)
        }
        .frame(height: 12)
        .frame(maxWidth: .infinity)
    }
}

private struct CircularPercentView: View {
    let visited: Int
    let total: Int

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(visited) / Double(total))
    }

    private var percentText: String {
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", (Double(visited) / Double(total)) * 100)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            VStack {
                Text(percentText)
                    .font(.headline)
                    .bold()
                Text("visited")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct CardPlaceholder: View {
    let title: String
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .overlay(
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Spacer()
                }
                .padding()
            )
    }
}

#Preview {
    MineView()
}
