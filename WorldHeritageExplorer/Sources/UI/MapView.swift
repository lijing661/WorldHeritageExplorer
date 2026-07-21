//  MapView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.

import SwiftUI
import MapKit
import CoreData
import CoreLocation

struct MapTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // New: binding to selected tab so we can switch back to List
    @Binding var selectedTab: MainTab

    @FetchRequest private var heritages: FetchedResults<NSManagedObject>

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 120)
    )
    @State private var showFilter = false
    @State private var didSetInitialCenter = false
    private let locationOnce = LocationOnce()

    init(selectedTab: Binding<MainTab>) {
        self._selectedTab = selectedTab
        let req = NSFetchRequest<NSManagedObject>(entityName: "Heritage")
        // Only those with valid coords
        let pred = NSPredicate(format: "latitude != nil AND longitude != nil AND (latitude != 0 OR longitude != 0)")
        req.predicate = pred
        // Required sort descriptors for fetched results controller
        req.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "country", ascending: true)
        ]
        _heritages = FetchRequest(fetchRequest: req)
    }

    private var annotations: [HeritageAnnotation] {
        heritages.compactMap { obj in
            guard let lat = obj.value(forKey: "latitude") as? Double,
                  let lon = obj.value(forKey: "longitude") as? Double else { return nil }
            let name = (obj.value(forKey: "name") as? String) ?? "—"
            let country = (obj.value(forKey: "country") as? String) ?? ""
            let category = (obj.value(forKey: "category") as? String) ?? ""
            return HeritageAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                title: name,
                subtitle: country,
                kind: HeritageKind.from(category: category)
            )
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            HeritageMKMap(annotations: annotations, region: $region, showsUser: true)
                .ignoresSafeArea() // 让地图延伸到最顶
        }
        .navigationBarHidden(true)
        .hideTabBarIfAvailable()
        .safeAreaInset(edge: .top) { // 顶栏固定在最上方
            topBar
                .background(Color(.systemBackground).ignoresSafeArea(edges: .top)) // 覆盖状态栏背景，无分割线/阴影
        }
        // Center to user's location only once on first appear
        .task { if !didSetInitialCenter { await centerToUserOnce() } }
        .sheet(isPresented: $showFilter) {
            VStack(spacing: 16) {
                Text("Filter (Coming Soon)").font(.headline)
                Text("按类型/国家/年份筛选将在后续加入").foregroundColor(.secondary)
                Button("关闭") { showFilter = false }
            }
            .padding()
            .presentationDetents([.fraction(0.25)])
        }
    }

    private func centerToUserOnce() async {
        didSetInitialCenter = true
        if let coord = await locationOnce.requestCurrentCoordinate() {
            region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
            )
        }
    }

    // 干净的系统风格顶栏（44pt 内容高度），无分割线/阴影
    private var topBar: some View {
        HStack {
            Button(action: { selectedTab = .list }) { // back to List tab
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(width: 36, alignment: .leading)
            }
            Spacer()
            Text("All sites")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Button(action: { showFilter = true }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }
}

// MARK: - Annotation Models

enum HeritageKind {
    case cultural, natural, mixed, unknown
    static func from(category: String) -> HeritageKind {
        let s = category.lowercased()
        if s.contains("mixed") { return .mixed }
        if s.contains("natural") { return .natural }
        if s.contains("cultural") { return .cultural }
        return .unknown
    }
    var glyphName: String {
        switch self {
        case .cultural: return "building.columns.fill"
        case .natural: return "leaf.fill"
        case .mixed: return "circle.lefthalf.filled"
        case .unknown: return "questionmark.circle"
        }
    }
    var tint: UIColor {
        switch self {
        case .cultural: return UIColor.systemYellow
        case .natural: return UIColor.systemGreen
        case .mixed: return UIColor.systemPurple
        case .unknown: return UIColor.systemGray
        }
    }
}

final class HeritageAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    let kind: HeritageKind
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, kind: HeritageKind) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        super.init()
    }
}

// MARK: - UIKit Map with clustering

struct HeritageMKMap: UIViewRepresentable {
    var annotations: [HeritageAnnotation]
    @Binding var region: MKCoordinateRegion
    var showsUser: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.region = region
        map.showsCompass = true
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = showsUser
        map.userTrackingMode = .none
        map.register(HeritageMarkerView.self, forAnnotationViewWithReuseIdentifier: HeritageMarkerView.reuseID)
        map.register(HeritageClusterView.self, forAnnotationViewWithReuseIdentifier: HeritageClusterView.reuseID)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if map.region.center.latitude != region.center.latitude || map.region.center.longitude != region.center.longitude || map.region.span.latitudeDelta != region.span.latitudeDelta {
            map.setRegion(region, animated: true)
        }
        map.showsUserLocation = showsUser
        // Simple refresh approach: replace all when counts differ (data ~1k)
        let existing = map.annotations.compactMap { $0 as? HeritageAnnotation }
        if existing.count != annotations.count {
            map.removeAnnotations(map.annotations)
            map.addAnnotations(annotations)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: HeritageClusterView.reuseID, for: cluster) as! HeritageClusterView
                view.annotation = cluster
                return view
            }
            guard let ann = annotation as? HeritageAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: HeritageMarkerView.reuseID, for: ann) as! HeritageMarkerView
            view.configure(kind: ann.kind)
            view.clusteringIdentifier = "heritage"
            view.canShowCallout = true
            return view
        }
    }
}

// MARK: - Annotation Views

final class HeritageMarkerView: MKMarkerAnnotationView {
    static let reuseID = "heritage.marker"
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        displayPriority = .defaultHigh
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    func configure(kind: HeritageKind) {
        markerTintColor = kind.tint
        glyphImage = UIImage(systemName: kind.glyphName)
        glyphTintColor = .white
    }
}

final class HeritageClusterView: MKAnnotationView {
    static let reuseID = "heritage.cluster"
    private let countLabel = UILabel()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        let circle = UIView(frame: bounds)
        circle.backgroundColor = .white
        circle.layer.cornerRadius = bounds.width/2
        circle.layer.borderWidth = 2
        circle.layer.borderColor = UIColor.black.cgColor
        circle.isUserInteractionEnabled = false
        addSubview(circle)

        countLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = .black
        countLabel.textAlignment = .center
        countLabel.frame = bounds
        countLabel.isUserInteractionEnabled = false
        addSubview(countLabel)
        centerOffset = CGPoint(x: 0, y: -2)
        displayPriority = .defaultHigh
    }
    override func prepareForDisplay() {
        super.prepareForDisplay()
        if let cluster = annotation as? MKClusterAnnotation {
            countLabel.text = "\(cluster.memberAnnotations.count)"
        } else {
            countLabel.text = ""
        }
    }
}

private extension View {
    @ViewBuilder
    func hideTabBarIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

// One-shot location helper (requests once, no continuous updates)
final class LocationOnce: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestCurrentCoordinate() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            if CLLocationManager.locationServicesEnabled() {
                // Prefer a single-shot request
                manager.requestLocation()
            } else {
                cont.resume(returning: nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last?.coordinate)
        continuation = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

#Preview { MapTabView(selectedTab: .constant(.map)) }
