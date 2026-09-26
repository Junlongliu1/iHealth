//
//  RunHeroMapView.swift
//  iHealth
//

import SwiftUI
import MapKit
import CoreLocation

/// 跑步详情页顶部地图层：展示轨迹、起点、公里标记
struct RunHeroMapView: View {
    let route: [CLLocationCoordinate2D]
    let kilometerMarkers: [KilometerMarker]
    let isLoading: Bool

    @State private var camera: MapCameraPosition = .automatic

    private var routeKey: Int { route.count }

    var body: some View {
        Group {
            if isLoading {
                Color(.secondarySystemBackground)
            } else {
                ZStack(alignment: .bottom) {
                    Map(position: $camera,
                        interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                        routeOverlay
                    }
                    .mapStyle(.standard(elevation: .realistic,
                                        pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                        MapPitchToggle()
                    }

                    // 底部渐变：让内容卡片浮出更自然
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(.systemBackground).opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    .allowsHitTesting(false)
                }
            }
        }
        .task(id: routeKey) {
            updateCamera()
        }
    }

    // MARK: - 路线绘制

    @MapContentBuilder
    private var routeOverlay: some MapContent {
        if route.count >= 2 {
            // 描边阴影
            MapPolyline(coordinates: route)
                .stroke(Color.orange.opacity(0.20),
                        style: StrokeStyle(lineWidth: 8,
                                           lineCap: .round,
                                           lineJoin: .round))

            // 主线渐变
            MapPolyline(coordinates: route)
                .stroke(
                    .runGradient,
                    style: StrokeStyle(lineWidth: 3.5,
                                       lineCap: .round,
                                       lineJoin: .round)
                )

            // 起点标记
            if let start = route.first {
                Annotation("", coordinate: start, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.20),
                                    radius: 4, y: 1)
                        Circle()
                            .fill(Color(red: 0.4, green: 0.85, blue: 0.4))
                            .frame(width: 12, height: 12)
                    }
                }
            }

            // 公里标记
            ForEach(kilometerMarkers) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.75))
                            .frame(width: 22, height: 22)
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                            .frame(width: 22, height: 22)
                        Text("\(marker.id)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 4, y: 1)
                }
            }
        }
    }

    // MARK: - 相机

    private func updateCamera() {
        guard !route.isEmpty else { return }

        let lats = route.map(\.latitude)
        let lons = route.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.003) * 1.5,
            longitudeDelta: max(maxLon - minLon, 0.003) * 1.5
        )
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
