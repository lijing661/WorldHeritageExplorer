//  HeritageDetailView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/15/25.

import SwiftUI
import CoreData
import Kingfisher
import MapKit

struct HeritageDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    private var heritage: NSManagedObject

    @State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10))
    @State private var showFullMap = false
    @State private var mainTimeoutFired = false
    @State private var mainReloadToken = UUID()
    @State private var mediumUIImage: UIImage? = nil
    @State private var mediumLoading = false
    @State private var imageLoaded = false

    private var latitude: Double? { heritage.value(forKey: "latitude") as? Double }
    private var longitude: Double? { heritage.value(forKey: "longitude") as? Double }
    private var hasValidCoordinate: Bool { if let lat = latitude, let lon = longitude { return abs(lat) > 0.00001 || abs(lon) > 0.00001 } else { return false } }

    init(item: NSManagedObject) {
        self.heritage = item
        // Set map region if coordinate exists
        if let lat = item.value(forKey: "latitude") as? Double, let lon = item.value(forKey: "longitude") as? Double { _mapRegion = State(initialValue: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))) }
    }

    private var name: String { heritage.value(forKey: "name") as? String ?? "—" }
    private var country: String { heritage.value(forKey: "country") as? String ?? "—" }
    private var region: String { heritage.value(forKey: "region") as? String ?? "" }
    private var category: String { heritage.value(forKey: "category") as? String ?? "" }
    private var shortDescription: String { heritage.value(forKey: "shortDes") as? String ?? "暂无简介" }
    private var mainImageURL: URL? {
        if let s = heritage.value(forKey: "mainImageURL") as? String, !s.isEmpty { return URL(string: s) } else { return nil }
    }
    private var mainThumbURL: URL? {
        if let s = heritage.value(forKey: "mainThumbURL") as? String, !s.isEmpty { return URL(string: s) } else { return nil }
    }
    // Safe year extraction already implemented below

    private var isFavorite: Bool { (heritage.value(forKey: "isFavorite") as? Bool) ?? false }
    private var isVisited: Bool { (heritage.value(forKey: "isVisited") as? Bool) ?? false }

    private var categoryIconName: String {
        switch category.lowercased() {
        case let s where s.contains("cultural"): return "building.columns.fill"
        case let s where s.contains("natural"): return "leaf.fill"
        case let s where s.contains("mixed"): return "circle.lefthalf.filled"
        default: return "questionmark.circle"
        }
    }

    private var categoryColor: Color {
        switch category.lowercased() {
        case let s where s.contains("cultural"): return Color.yellow
        case let s where s.contains("natural"): return Color.green
        case let s where s.contains("mixed"): return Color.purple
        default: return Color.gray
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let url = mainImageURL {
                    // Prefer a small thumb if available; otherwise show the main image but downsample
                    let thumbURL = mainThumbURL
                    let displayURL = thumbURL ?? mainImageURL
                    // Use a fixed, prominent height near ~2/3 screen width (choose 320pt)
                    let imageHeight: CGFloat = 320
                    ZStack(alignment: .bottomTrailing) {
                        // 1) Always show the small thumb (if present) or the main image as fallback
                        KFImage(displayURL)
                            .placeholder { mainSkeleton }
                            .retry(maxCount: 2, interval: .seconds(2))
                            .backgroundDecode()
                            .downsampling(size: CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale, height: imageHeight * UIScreen.main.bounds.height * UIScreen.main.scale))
                            .onFailure { _ in mainTimeoutFired = true }
                            .onSuccess { _ in
                                imageLoaded = true
                                mainTimeoutFired = false
                            }
                            .resizable()
                            .scaledToFill()
                            .id(mainReloadToken)
                            .frame(width: UIScreen.main.bounds.width, height: imageHeight)
                            .clipped()

                        // 2) If we have already fetched a medium image (higher quality), show it on top with a fade
                        if let img = mediumUIImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: UIScreen.main.bounds.width, height: imageHeight)
                                .clipped()
                                .transition(.opacity)
                        }

                        if mainTimeoutFired { mainRetryBadge }
                    }
                    .onAppear {
                        mainTimeoutFired = false

                        // kick off medium-size fetch if we don't have it yet
                        if mediumUIImage == nil && !mediumLoading {
                            mediumLoading = true
                            DispatchQueue.global(qos: .userInitiated).async {
                                // prefer to derive a medium URL from the authoritative mainImageURL
                                let mediumURL = deriveMediumURL(from: mainImageURL) ?? deriveMediumURL(from: thumbURL)
                                guard let mURL = mediumURL else { mediumLoading = false; return }

                                // choose a target width (px). Use a reasonable middle ground (e.g. 1200px)
                                let targetWidth: CGFloat = 1200
                                // preserve display aspect ratio based on imageHeight vs screen width
                                let aspect = imageHeight / UIScreen.main.bounds.width
                                let targetSize = CGSize(width: targetWidth * UIScreen.main.scale, height: targetWidth * aspect * UIScreen.main.scale)

                                let processor = DownsamplingImageProcessor(size: targetSize)
                                let options: KingfisherOptionsInfo = [
                                    .processor(processor),
                                    .scaleFactor(UIScreen.main.scale),
                                    .backgroundDecode
                                ]

                                KingfisherManager.shared.retrieveImage(with: mURL, options: options, progressBlock: nil) { result in
                                    DispatchQueue.main.async {
                                        mediumLoading = false
                                        switch result {
                                        case .success(let value):
                                            // store processed image (Kingfisher cached processed result by key)
                                            mediumUIImage = value.image
                                            imageLoaded = true
                                            mainTimeoutFired = false
                                        case .failure:
                                            // no medium available; leave thumb displayed
                                            break
                                        }
                                    }
                                }
                            }
                        }

                        // existing cache-check logic for retry badge
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            // If image already loaded (visible) or medium is ready, don't show retry
                            if imageLoaded || mediumUIImage != nil { return }
                            if let key = displayURL?.absoluteString {
                                ImageCache.default.retrieveImage(forKey: key, options: nil, completionHandler: { result in
                                    switch result {
                                    case .success(let value):
                                        if value.cacheType == .none { mainTimeoutFired = true } else { imageLoaded = true }
                                    case .failure:
                                        mainTimeoutFired = true
                                    }
                                })
                            } else {
                                mainTimeoutFired = true
                            }
                        }
                    }
                } else {
                    let imageHeight: CGFloat = 320
                    Color.gray.opacity(0.1)
                        .frame(height: imageHeight)
                        .overlay(Text("No Image").foregroundColor(.secondary))
                }

                infoSection

                descriptionTitle
                descriptionSection
                mapSection
            }
            .padding(.bottom, 24)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: toggleVisited) {
                    Image(systemName: isVisited ? "checkmark.seal.fill" : "checkmark.seal")
                        .foregroundColor(isVisited ? .green : .secondary)
                }
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .secondary)
                }
            }
        }
    }

    private var yearInscribedText: String {
        func extract(_ key: String) -> String? {
            guard heritage.entity.attributesByName[key] != nil else { return nil }
            let v = heritage.value(forKey: key)
            if let i = v as? Int { return String(i) }
            if let n = v as? NSNumber { return n.stringValue }
            if let s = v as? String, !s.isEmpty { return s }
            return nil
        }
        return extract("yearInscribed")
            ?? extract("yearinscribed")
            ?? extract("year_inscribed")
            ?? extract("inscribedYear")
            ?? "—"
    }

    // Safe accessor to avoid KVC exceptions when model lacks a key
    private func safeValue(forKey key: String) -> Any? {
        guard heritage.entity.attributesByName[key] != nil else { return nil }
        return heritage.value(forKey: key)
    }

    // Simple criteria extraction
    private var criteriaText: String {
        if let s = safeValue(forKey: "criteria") as? String, !s.isEmpty { return s }
        if let s = safeValue(forKey: "criterion") as? String, !s.isEmpty { return s }
        return "—"
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

    // Utility to split country strings into tokens used in this view
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

    // Build aligned pairs of (optional emoji, country name)
    private func countryFlagPairs() -> [(emoji: String?, name: String)] {
        let countryRaw = heritage.value(forKey: "country") as? String
        let isoRaw = heritage.value(forKey: "isoCode") as? String
        let countries = splitCountries(countryRaw)
        let isoTokens = splitISOCodes(isoRaw)
        var pairs: [(String?, String)] = []
        for (idx, c) in countries.enumerated() {
            var iso: String? = nil
            if isoTokens.count > idx { iso = isoTokens[idx] }
            if iso == nil {
                // try authoritative lookup if available
                if let lookup = isoForCountry(c) { iso = lookup }
            }
            let emoji = flagEmoji(from: iso)
            pairs.append((emoji, c))
        }
        return pairs
    }

    private var infoSection: some View {
        // New layout: bold centered name; category badge on second line; flags+country names left-aligned; region left-aligned with icon; inscription year; criteria
        VStack(spacing: 8) {
            // 1. Name, bold centered
            Text(name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // 2. Category badge (moved here)
            HStack {
                categoryBadge
                Spacer()
            }
            .frame(maxWidth: .infinity)

            // 3. Flags + country names inline, left aligned (wrap if long)
            let pairs = countryFlagPairs()
            if !pairs.isEmpty {
                let combined = pairs.map { pair -> String in
                    if let e = pair.emoji { return "\(e) \(pair.name)" }
                    return pair.name
                }.joined(separator: ", ")

                Text(combined)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(country)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 4. Region with icon, left aligned
            if !region.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.red)
                    Text(region)
                        .font(.callout)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 5. Inscription year
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                Text("Inscription:")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(yearInscribedText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
            }

            // 6. Criteria
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.subheadline)
                    .foregroundColor(.black)
                Text("Criteria:")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(criteriaText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
            }

            // no bottom category badge (moved to second line)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
        .padding(.horizontal, 8)
    }

    private var categoryBadge: some View {
        HStack(spacing: 6) {
            Text(category.isEmpty ? "Unknown" : category)
                .font(.caption)
                .bold()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(categoryColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var descriptionTitle: some View {
        HStack {
            Text("Description:")
                .font(.subheadline)
                .bold()
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(Color(.secondarySystemBackground))
    }

    private var descriptionSection: some View {
        Text(shortDescription)
            .font(.body)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
            .padding(.horizontal, 8)
    }

    private func toggleFavorite() {
        heritage.setValue(!isFavorite, forKey: "isFavorite")
        save()
    }

    private func toggleVisited() {
        heritage.setValue(!isVisited, forKey: "isVisited")
        save()
    }

    private func save() {
        do { try viewContext.save() } catch { /* ignore for now */ }
    }

    private struct AnnotationItem: Identifiable { let id = UUID(); let coordinate: CLLocationCoordinate2D }

    private var mapSection: some View {
        Group {
            if hasValidCoordinate, let lat = latitude, let lon = longitude {
                let items = [AnnotationItem(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))]
                ZStack {
                    Map(coordinateRegion: $mapRegion, interactionModes: [], annotationItems: items) { item in
                        MapAnnotation(coordinate: item.coordinate) {
                            Image(systemName: categoryIconName)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(categoryColor)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                        }
                    }
                    NavigationLink(isActive: $showFullMap) {
                        HeritageFullMapView(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), categoryIconName: categoryIconName, categoryColor: categoryColor, title: name)
                    } label: { EmptyView() }
                    .hidden()
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture { showFullMap = true }
            } else {
                Color.gray.opacity(0.1)
                    .frame(height: 240)
                    .overlay(Text("No Location").foregroundColor(.secondary))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 8)
            }
        }
    }

    private var mainSkeleton: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.15))
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .gray.opacity(0.6)))
        }
    }

    private var mainRetryBadge: some View {
        Button {
            mainTimeoutFired = false
            mainReloadToken = UUID()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("重试")
            }
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .padding(8)
        }
    }

    // Attempt to derive a medium-size URL from Wikimedia-style image URLs.
    // Returns a URL for a medium-sized thumbnail (e.g. 800–1400px) when derivation is possible.
    private func deriveMediumURL(from url: URL?) -> URL? {
        guard let url = url else { return nil }
        let host = url.host ?? ""
        // Handle Wikimedia / upload.wikimedia.org pattern
        if host.contains("upload.wikimedia.org") {
            // Expect path like /wikipedia/commons/AA/BB/Filename.ext
            let path = url.path
            // find the index of "/wikipedia/commons/"
            if let range = path.range(of: "/wikipedia/commons/") {
                let suffix = path[range.upperBound...]
                // build thumb path: /wikipedia/commons/thumb/{suffix}/{width}px-{filename}
                let components = suffix.split(separator: "/")
                guard let filename = components.last else { return nil }
                // rebuild the thumb path prefix (everything except filename)
                let prefix = components.dropLast().joined(separator: "/")
                // pick a width in px (use 1200 as default within requested 800–1400)
                let width = 1200
                let thumbPath = "/wikipedia/commons/thumb/\(prefix)/\(filename)/\(width)px-\(filename)"
                var comps = URLComponents()
                comps.scheme = url.scheme
                comps.host = url.host
                comps.path = thumbPath
                return comps.url
            }
        }

        // If the URL already contains "/thumb/" and a pixel size, try to increase size by replacing the number
        if url.path.contains("/thumb/") {
            // naive replace: find last path component that starts with digits and "px-"
            let parts = url.path.split(separator: "/")
            if let last = parts.last, last.contains("px-") {
                // replace leading digits up to "px-" with 1200px
                let s = String(last)
                if let idx = s.firstIndex(of: "p") {
                    let filename = s[s.index(idx, offsetBy: 3)...] // after "px-"
                    let new = "1200px-\(filename)"
                    var newParts = parts
                    newParts[newParts.count - 1] = Substring(new)
                    let newPath = "/" + newParts.joined(separator: "/")
                    var comps = URLComponents()
                    comps.scheme = url.scheme
                    comps.host = url.host
                    comps.path = newPath
                    return comps.url
                }
            }
        }

        // Cannot derive a medium variant for unknown hosts
        return nil
    }
}

private struct HeritageFullMapView: View {
    let coordinate: CLLocationCoordinate2D
    let categoryIconName: String
    let categoryColor: Color
    let title: String

    @State private var region: MKCoordinateRegion

    init(coordinate: CLLocationCoordinate2D, categoryIconName: String, categoryColor: Color, title: String) {
        self.coordinate = coordinate
        self.categoryIconName = categoryIconName
        self.categoryColor = categoryColor
        self.title = title
        _region = State(initialValue: MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)))
    }

    private struct PinItem: Identifiable { let id = UUID(); let coordinate: CLLocationCoordinate2D }

    var body: some View {
        let items = [PinItem(coordinate: coordinate)]
        let labelWidth = UIScreen.main.bounds.width / 3
        Map(coordinateRegion: $region, annotationItems: items) { item in
            MapAnnotation(coordinate: item.coordinate) {
                VStack(spacing: 4) {
                    Image(systemName: categoryIconName)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(categoryColor)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    Text(title.isEmpty ? "—" : title)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .frame(width: labelWidth)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    Text("Detail Preview")
}
