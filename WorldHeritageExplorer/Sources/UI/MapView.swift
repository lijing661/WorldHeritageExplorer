//  MapView.swift
//  WorldHeritageExplorer
//
//  Created by GitHub Copilot on 11/9/25.
//

import SwiftUI
import MapKit

struct MapTabView: View {
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), span: .init(latitudeDelta: 80, longitudeDelta: 180))

    var body: some View {
        Map(coordinateRegion: $region)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                Text("Map")
                    .font(.headline)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
    }
}

#Preview { MapTabView() }
