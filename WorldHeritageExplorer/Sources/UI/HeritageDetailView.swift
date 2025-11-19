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
                    ZStack(alignment: .bottomTrailing) {
                        KFImage(url)
                            .placeholder { mainSkeleton }
                            .retry(maxCount: 2, interval: .seconds(2))
                            .cacheOriginalImage()
                            .backgroundDecode()
                            .resizable()
                            .scaledToFill()
                            .id(mainReloadToken)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipped()
                        if mainTimeoutFired { mainRetryBadge }
                    }
                    .onAppear {
                        mainTimeoutFired = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            // 如果仍未有缓存（磁盘或内存），给出重试按钮
                            if let key = mainImageURL?.absoluteString {
                                ImageCache.default.retrieveImage(forKey: key, options: nil, completionHandler: { result in
                                    switch result {
                                    case .success(let value):
                                        if value.cacheType == .none { mainTimeoutFired = true }
                                    case .failure:
                                        mainTimeoutFired = true
                                    }
                                })
                            }
                        }
                    }
                } else {
                    Color.gray.opacity(0.1)
                        .frame(height: 220)
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
                    Text("Back")
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

    private var infoSection: some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(country)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if !region.isEmpty {
                Text("(\(region))")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                categoryBadge
                Spacer()
                Text("Inscribed in: \(yearInscribedText)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 1)
        .padding(.horizontal, 8)
    }

    private var categoryBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: categoryIconName)
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
