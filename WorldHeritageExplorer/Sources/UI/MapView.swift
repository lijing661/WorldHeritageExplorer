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
    @State private var lastSelectedAnnotationID: String? = nil
    @State private var selectedHeritageObject: NSManagedObject? = nil
    @State private var navigateToDetail = false
    @State private var selectedAnnotationID: String? = nil

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
                id: obj.objectID.uriRepresentation().absoluteString,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                title: name,
                subtitle: country,
                kind: HeritageKind.from(category: category)
            )
        }
    }

    private var idToObject: [String: NSManagedObject] {
        Dictionary(uniqueKeysWithValues: heritages.map { ($0.objectID.uriRepresentation().absoluteString, $0) })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                HeritageMKMap(
                    annotations: annotations,
                    region: $region,
                    selectedAnnotationID: $selectedAnnotationID,
                    showsUser: true,
                    onAnnotationSelect: handleAnnotationSelect(id:),
                    onDetailTapped: pushDetailFor(id:)
                )
                .ignoresSafeArea()

                // Hidden navigation link to push detail view
                NavigationLink(isActive: $navigateToDetail) {
                    if let obj = selectedHeritageObject {
                        HeritageDetailView(item: obj)
                    } else {
                        EmptyView()
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            }
            .navigationBarHidden(true)
            .hideTabBarIfAvailable()
            .safeAreaInset(edge: .top) {
                topBar
                    .background(Color(.systemBackground).ignoresSafeArea(edges: .top))
            }
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
    }

    private func handleAnnotationSelect(id: String) {
        // First tap: just select / show callout. The callout has a detail button.
        lastSelectedAnnotationID = id
    }

    private func pushDetailFor(id: String) {
        selectedHeritageObject = idToObject[id]
        selectedAnnotationID = id
        navigateToDetail = true
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
    let id: String
    init(id: String, coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, kind: HeritageKind) {
        self.id = id
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
    @Binding var selectedAnnotationID: String?
    var showsUser: Bool = true
    var onAnnotationSelect: ((String) -> Void)? = nil
    var onDetailTapped: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

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
        // Only set region from SwiftUI when it has explicitly changed and the user is not dragging.
        let regionChanged = map.region.center.latitude != region.center.latitude
            || map.region.center.longitude != region.center.longitude
            || map.region.span.latitudeDelta != region.span.latitudeDelta
        if regionChanged, !context.coordinator.isUserInteracting {
            map.setRegion(region, animated: true)
        }
        map.showsUserLocation = showsUser
        let existing = map.annotations.compactMap { $0 as? HeritageAnnotation }
        if existing.count != annotations.count {
            map.removeAnnotations(map.annotations)
            map.addAnnotations(annotations)
        }
        // Re-select the annotation when returning from detail so the callout stays visible
        if let selectedID = selectedAnnotationID,
           let annotation = annotations.first(where: { $0.id == selectedID }),
           !map.selectedAnnotations.contains(where: { ($0 as? HeritageAnnotation)?.id == selectedID }) {
            map.selectAnnotation(annotation, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: HeritageMKMap
        var onAnnotationSelect: ((String) -> Void)?
        var onDetailTapped: ((String) -> Void)?
        var isUserInteracting = false

        init(parent: HeritageMKMap) {
            self.parent = parent
            self.onAnnotationSelect = parent.onAnnotationSelect
            self.onDetailTapped = parent.onDetailTapped
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isUserInteracting = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUserInteracting = false
            parent.region = mapView.region
        }

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

            // Add a detail button to the callout; tapping it opens the heritage detail page
            let button = UIButton(type: .detailDisclosure)
            button.addTarget(self, action: #selector(detailButtonTapped(_:)), for: .touchUpInside)
            button.heritageAnnotationView = view
            view.rightCalloutAccessoryView = button
            view.detailButton = button
            view.annotationID = ann.id

            return view
        }

        @objc private func detailButtonTapped(_ sender: UIButton) {
            guard let id = sender.heritageAnnotationView?.annotationID else { return }
            onDetailTapped?(id)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let ann = view.annotation as? HeritageAnnotation {
                onAnnotationSelect?(ann.id)
            } else if let cluster = view.annotation as? MKClusterAnnotation,
                      let ann = cluster.memberAnnotations.first as? HeritageAnnotation {
                onAnnotationSelect?(ann.id)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            // no-op
        }
    }
}

// MARK: - Annotation Views

final class HeritageMarkerView: MKMarkerAnnotationView {
    static let reuseID = "heritage.marker"
    var detailButton: UIButton?
    var annotationID: String?
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

private var heritageAnnotationViewKey: UInt8 = 0

private extension UIButton {
    var heritageAnnotationView: HeritageMarkerView? {
        get { objc_getAssociatedObject(self, &heritageAnnotationViewKey) as? HeritageMarkerView }
        set { objc_setAssociatedObject(self, &heritageAnnotationViewKey, newValue, .OBJC_ASSOCIATION_ASSIGN) }
    }
}

// MARK: - Cluster View

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

#Preview { MapTabView(selectedTab: .constant(.map)) }
