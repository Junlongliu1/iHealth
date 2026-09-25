//
//  RunDetailView.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI
import MapKit
import CoreLocation

struct RunDetailView: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace

    @State private var store = WorkoutStore()
    @State private var detail: RunDetail?
    @State private var isLoading = true
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = max(proxy.size.height * 0.55, 420)
            let overlap: CGFloat = 30

            ZStack(alignment: .top) {

                // ① 地图：独立一层，从顶部铺到 heroHeight
                heroMap
                    .frame(height: heroHeight)
                    .ignoresSafeArea(edges: .top)

                // ② 内容：从 heroHeight - overlap 开始，ScrollView 不覆盖地图主体
                ScrollView {
                    VStack(spacing: 0) {
                        contentCard
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.top, heroHeight - overlap)
                .ignoresSafeArea(edges: .bottom)

                // ③ 顶部工具栏：浮在最上层
                topBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            detail = await store.loadRunDetail(for: workout)
            updateCamera()
            isLoading = false
        }
    }

    // MARK: - Hero 地图

    @ViewBuilder
    private var heroMap: some View {
        if isLoading {
            Color(.secondarySystemBackground)
        } else {
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
        }
    }

    // MARK: - 顶部玻璃工具栏

    private var topBar: some View {
        HStack(spacing: 10) {
            // 返回
            GlassEffectContainer {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .circle)
                .glassEffectID("back", in: glassNamespace)
            }

            Spacer()

            // 分享 + 更多（组合胶囊）
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        shareRoute()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 22)

                    Button {
                        // 更多操作
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("actions", in: glassNamespace)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        // 品牌标题：真正居中于屏幕
        .overlay {
            Text("iHealth")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.74, blue: 0.92),
                            Color(red: 0.55, green: 0.55, blue: 0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 18)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("title", in: glassNamespace)
        }
    }

    // MARK: - 内容卡片

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 头部：大数字 + 头像
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // 大号距离
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(bigDistanceValue)
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        Text(distanceUnit)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .offset(y: 1)
                    }

                    // 日期
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(formattedDate)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    // 设备来源
                    if let source = detail?.sourceName, !source.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: sourceIcon(for: source))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(source)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)

                // 头像
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.75, blue: 0.4),
                                    Color(red: 0.85, green: 0.5, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        Image(systemName: "person.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

                    Text("Evron")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            // 分隔线
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.8)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            // 3 列指标网格
            metricsGrid
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background {
            Color(.systemBackground)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 32,
                        topTrailingRadius: 32,
                        style: .continuous
                    )
                )
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - 3 列指标

    private var metricsGrid: some View {
        let items: [MetricItem] = [
            .init(title: "运动时间",
                  value: formattedDuration(detail?.duration),
                  unit: ""),

            .init(title: "平均配速",
                  value: formattedPace(detail?.averagePace),
                  unit: detail?.averagePace != nil ? "/km" : "",
                  accent: true),

            .init(title: "平均功率",
                  value: formattedInt(detail?.averagePower),
                  unit: detail?.averagePower != nil ? "W" : ""),

            .init(title: "平均心率",
                  value: formattedInt(detail?.averageHeartRate),
                  unit: detail?.averageHeartRate != nil ? "bpm" : ""),

            .init(title: "最大心率",
                  value: formattedInt(detail?.maxHeartRate),
                  unit: detail?.maxHeartRate != nil ? "bpm" : ""),

            .init(title: "累计上升",
                  value: formattedInt(detail?.elevationAscended),
                  unit: detail?.elevationAscended != nil ? "m" : ""),

            .init(title: "平均步幅",
                  value: formattedStride,
                  unit: detail?.averageStrideLength != nil ? "cm" : ""),

            .init(title: "平均步频",
                  value: formattedInt(detail?.averageCadence),
                  unit: detail?.averageCadence != nil ? "/min" : ""),

            .init(title: "垂直振幅",
                  value: formattedDouble(detail?.verticalOscillation, digits: 1),
                  unit: detail?.verticalOscillation != nil ? "cm" : ""),

            .init(title: "垂直步幅比",
                  value: formattedVerticalRatio,
                  unit: verticalRatioValue != nil ? "%" : ""),

            .init(title: "消耗能量",
                  value: formattedInt(detail?.activeEnergy),
                  unit: detail?.activeEnergy != nil ? "kcal" : ""),

            .init(title: "总距离",
                  value: formattedTotalDistance,
                  unit: detail?.distance != nil ? "km" : "")
        ]

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 18
        ) {
            ForEach(items) { item in
                MetricColumn(item: item)
            }
        }
    }

    private var formattedStride: String {
        guard let stride = detail?.averageStrideLength else { return "--" }
        return String(Int((stride * 100).rounded()))
    }

    private var verticalRatioValue: Double? {
        guard let osc = detail?.verticalOscillation,
              let stride = detail?.averageStrideLength,
              stride > 0 else { return nil }
        return osc / (stride * 100) * 100
    }

    private var formattedVerticalRatio: String {
        guard let ratio = verticalRatioValue else { return "--" }
        return String(format: "%.1f", ratio)
    }

    private var formattedTotalDistance: String {
        guard let distance = detail?.distance else { return "--" }
        return String(format: "%.2f", distance / 1000)
    }

    // MARK: - 路线绘制

    @MapContentBuilder
    private var routeOverlay: some MapContent {
        if let route = detail?.route, route.count >= 2 {
            // 外发光
            MapPolyline(coordinates: route)
                .stroke(Color.orange.opacity(0.22),
                        style: StrokeStyle(lineWidth: 7,
                                           lineCap: .round,
                                           lineJoin: .round))

            // 主线
            MapPolyline(coordinates: route)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.62, blue: 0.2),
                            Color(red: 1.0, green: 0.42, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3.5,
                                       lineCap: .round,
                                       lineJoin: .round)
                )

            // 起点
            if let start = route.first {
                Annotation("", coordinate: start, anchor: .center) {
                    ZStack {
                        Circle().fill(.white).frame(width: 16, height: 16)
                        Circle()
                            .fill(Color(red: 0.4, green: 0.85, blue: 0.4))
                            .frame(width: 10, height: 10)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
            }

            // 公里标记
            ForEach(detail?.kilometerMarkers ?? []) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.85))
                            .frame(width: 20, height: 20)
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                            .frame(width: 20, height: 20)
                        Text("\(marker.id)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                }
            }
        }
    }

    // MARK: - 相机

    private func updateCamera() {
        guard let route = detail?.route, !route.isEmpty else { return }

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
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - 文本

    private var bigDistanceValue: String {
        guard let distance = detail?.distance, distance > 0 else { return "--" }
        return String(format: "%.2f", distance / 1000)
    }

    private var distanceUnit: String {
        detail?.distance != nil ? "km" : ""
    }

    private var formattedDate: String {
        workout.startDate.formatted(
            .dateTime.month(.twoDigits).day(.twoDigits)
                .weekday(.abbreviated)
                .hour().minute()
        )
    }

    private func sourceIcon(for name: String) -> String {
        name.localizedCaseInsensitiveContains("watch") ? "applewatch" : "iphone"
    }

    private func formattedDuration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "--" }
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func formattedPace(_ pace: TimeInterval?) -> String {
        guard let pace, pace.isFinite, pace > 0 else { return "--" }
        let total = Int(pace.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    private func formattedInt(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(Int(value.rounded()))
    }

    private func formattedDouble(_ value: Double?, digits: Int) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(digits)f", value)
    }

    private func shareRoute() {
        // TODO: 分享路线
    }
}

// MARK: - 指标项

private struct MetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    var accent: Bool = false
}

private struct MetricColumn: View {
    let item: MetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(item.accent
                                     ? Color(red: 0.29, green: 0.65, blue: 0.92)
                                     : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())

                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(item.title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
