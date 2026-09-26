//
//  RunDetailView.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI
import MapKit
import CoreLocation
import Charts
import HealthKit

struct RunDetailView: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace

    @State private var detail: RunDetail?
    @State private var isLoading = true
    @State private var camera: MapCameraPosition = .automatic
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let topSafeArea = proxy.safeAreaInsets.top
            let heroHeight = max(proxy.size.height * 0.55, 420)
            let overlap: CGFloat = 30

            ZStack(alignment: .top) {

                // ① 底层背景
                Color(.systemBackground)
                    .ignoresSafeArea()

                // ② 地图层
                heroMap
                    .frame(height: heroHeight + topSafeArea)
                    .offset(y: -max(0, scrollOffset))
                    .scaleEffect(
                        pullStretch(scrollOffset: scrollOffset,
                                    heroHeight: heroHeight),
                        anchor: .bottom
                    )
                    .ignoresSafeArea(edges: .top)

                // ③ 内容层
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: heroHeight - overlap)

                        contentCard
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .bottom)
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newValue in
                    scrollOffset = newValue
                }

                // ④ 顶部工具栏
                topBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            detail = await WorkoutStore.loadRunDetail(for: workout)
            updateCamera()
            isLoading = false
        }
    }

    private func pullStretch(scrollOffset: CGFloat, heroHeight: CGFloat) -> CGFloat {
        guard scrollOffset < 0 else { return 1 }
        let extra = min(-scrollOffset / heroHeight * 0.5, 0.3)
        return 1 + extra
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

            Capsule()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
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

                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(formattedDate)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

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
            .padding(.top, 14)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.8)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            metricsGrid
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

            detailCards
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                topTrailingRadius: 32,
                style: .continuous
            )
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: -8)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                topTrailingRadius: 32,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            .allowsHitTesting(false)
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

            .init(title: "平均心率",
                  value: formattedInt(detail?.averageHeartRate),
                  unit: detail?.averageHeartRate != nil ? "bpm" : ""),

            .init(title: "最大心率",
                  value: formattedInt(detail?.maxHeartRate),
                  unit: detail?.maxHeartRate != nil ? "bpm" : ""),

            .init(title: "平均步频",
                  value: formattedInt(detail?.averageCadence),
                  unit: detail?.averageCadence != nil ? "/min" : ""),

            .init(title: "平均步幅",
                  value: formattedStride,
                  unit: detail?.averageStrideLength != nil ? "cm" : ""),

            .init(title: "累计上升",
                  value: formattedInt(detail?.elevationAscended),
                  unit: detail?.elevationAscended != nil ? "m" : ""),

            .init(title: "消耗能量",
                  value: formattedInt(detail?.activeEnergy),
                  unit: detail?.activeEnergy != nil ? "kcal" : ""),

            .init(title: "平均功率",
                  value: formattedInt(detail?.averagePower),
                  unit: detail?.averagePower != nil ? "W" : "")
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
        return String(Int(stride * 100))
    }

    // MARK: - 详情图表卡片

    private var detailCards: some View {
        let s = detail?.series ?? RunSeries()

        return VStack(spacing: 12) {
            // ★ VO2 Max 卡片
            if let vo2 = detail?.vo2Max {
                VO2MaxCard(info: vo2)
            }

            // ★ 公里分段卡片
            if let splits = detail?.splits, !splits.isEmpty {
                SplitsTableCard(splits: splits)
            }

            // —— 原有图表卡片 ——
            if let hr = detail?.averageHeartRate {
                RunMetricCard(
                    title: "心率",
                    icon: "heart.fill",
                    color: .red,
                    unit: "bpm",
                    points: s.heartRate,
                    statLabel: "平均 \(formattedInt(hr))",
                    averageValue: hr,
                    yFormat: { "\(Int($0))" }
                )
            }

            if let pace = detail?.averagePace {
                RunMetricCard(
                    title: "配速",
                    icon: "speedometer",
                    color: .orange,
                    unit: "min/km",
                    points: s.pace,
                    statLabel: "平均 \(formattedPace(pace))",
                    averageValue: pace,
                    yFormat: { formatPaceShort($0) }
                )
            }

            if let stride = detail?.averageStrideLength {
                RunMetricCard(
                    title: "步幅",
                    icon: "ruler",
                    color: .green,
                    unit: "cm",
                    points: s.strideLength,
                    statLabel: "平均 \(Int(stride * 100))",
                    averageValue: stride,
                    yFormat: { String(Int($0 * 100)) }
                )
            }

            if let cadence = detail?.averageCadence {
                RunMetricCard(
                    title: "步频",
                    icon: "metronome",
                    color: .blue,
                    unit: "步/分",
                    points: s.cadence,
                    statLabel: "平均 \(formattedInt(cadence))",
                    averageValue: cadence,
                    yFormat: { "\(Int($0))" }
                )
            }

            if !s.groundContactTime.isEmpty {
                let avg = s.groundContactTime.map(\.value).reduce(0, +)
                        / Double(s.groundContactTime.count)
                RunMetricCard(
                    title: "触地时间",
                    icon: "timer",
                    color: .purple,
                    unit: "ms",
                    points: s.groundContactTime,
                    statLabel: "平均 \(formattedInt(avg))",
                    averageValue: avg,
                    yFormat: { "\(Int($0))" }
                )
            }

            if let vo = detail?.verticalOscillation {
                RunMetricCard(
                    title: "垂直振幅",
                    icon: "arrow.up.and.down",
                    color: .cyan,
                    unit: "cm",
                    points: s.verticalOscillation,
                    statLabel: "平均 \(String(format: "%.1f", vo))",
                    averageValue: vo,
                    yFormat: { String(format: "%.1f", $0) }
                )
            }

            if let power = detail?.averagePower {
                RunMetricCard(
                    title: "跑步功率",
                    icon: "bolt.fill",
                    color: .pink,
                    unit: "W",
                    points: s.power,
                    statLabel: "平均 \(String(format: "%.1f", power))",
                    averageValue: power,
                    yFormat: { "\(Int($0))" }
                )
            }

            if let elev = detail?.elevationAscended, !s.elevation.isEmpty {
                let values = s.elevation.map(\.value)
                let maxV = values.max() ?? 0
                let minV = values.min() ?? 0
                let avgV = values.reduce(0, +) / Double(values.count)
                RunMetricCard(
                    title: "海拔",
                    icon: "mountain.2.fill",
                    color: .orange,
                    unit: "m",
                    points: s.elevation,
                    statLabel: "最大 \(Int(maxV)) 最小 \(Int(minV)) 平均 \(String(format: "%.1f", avgV))",
                    secondStatLabel: "↑\(formattedInt(elev))m",
                    averageValue: avgV,
                    yFormat: { "\(Int($0))" }
                )
            }
        }
    }

    private func formatPaceShort(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    // MARK: - 路线绘制

    @MapContentBuilder
    private var routeOverlay: some MapContent {
        if let route = detail?.route, route.count >= 2 {
            MapPolyline(coordinates: route)
                .stroke(Color.orange.opacity(0.22),
                        style: StrokeStyle(lineWidth: 7,
                                           lineCap: .round,
                                           lineJoin: .round))

            MapPolyline(coordinates: route)
                .stroke(
                    .runGradient,
                    style: StrokeStyle(lineWidth: 3.5,
                                       lineCap: .round,
                                       lineJoin: .round)
                )

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
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    // MARK: - 文本

    private var bigDistanceValue: String {
        guard let distance = detail?.distance, distance > 0 else { return "--" }
        let km = (distance / 1000).truncated(to: 2)
        return String(format: "%.2f", km)
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
        return String(Int(value))
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

// MARK: - VO2 Max 卡片

private struct VO2MaxCard: View {
    let info: VO2MaxInfo
    
    @State private var showDetail = false

    private var deltaText: String? {
        guard let delta = info.delta, abs(delta) > 0.001 else { return nil }
        return String(format: "%+.2f", delta)
    }

    private var isPositive: Bool { (info.delta ?? 0) >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最大摄氧量")
                .font(.system(size: 16, weight: .semibold))

            HStack(alignment: .center, spacing: 8) {
                Text(String(format: "%.2f", info.value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                    .monospacedDigit()

                Spacer(minLength: 8)

                if let text = deltaText {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(text)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(isPositive ? Color.green : Color.red)
                            .monospacedDigit()
                        Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isPositive ? Color.green : Color.red)
                        Button {
                            showDetail = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                if let level = info.classification {
                    Text(level.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(level.color.opacity(0.12))
                        )
                }

                if deltaText != nil {
                    Text("较上次")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .sheet(isPresented: $showDetail) {
            VO2MaxDetailSheet(info: info)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - VO2 Max 详情弹窗

    private struct VO2MaxDetailSheet: View {
        let info: VO2MaxInfo

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ① 当前状态
                        currentStatusSection

                        // ② 年龄段标准
                        if let thresholds = info.thresholds,
                           let age = info.age,
                           let sex = info.sex {
                            standardsSection(thresholds: thresholds,
                                             age: age,
                                             sex: sex)
                        } else {
                            noProfileSection
                        }

                        // ③ 对比记录
                        if let prev = info.previousValue {
                            comparisonSection(previous: prev)
                        } else {
                            noHistorySection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .navigationTitle("最大摄氧量")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }

        // MARK: ① 当前状态

        private var currentStatusSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("当前状态")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.2f", info.value))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                        .monospacedDigit()

                    Text("ml/(kg·min)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    if let level = info.classification {
                        Text(level.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(level.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(level.color.opacity(0.15)))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }

        // MARK: ② 年龄段标准

        private func standardsSection(
            thresholds: VO2MaxThresholds,
            age: Int,
            sex: HKBiologicalSex
        ) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("年龄段标准")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(age) 岁 · \(sexLabel(sex))")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(ranges(thresholds).enumerated()), id: \.offset) { idx, item in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(item.level.color)
                                .frame(width: 8, height: 8)

                            Text(item.level.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(item.isCurrent ? item.level.color : .primary)

                            Spacer()

                            Text(item.range)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(item.isCurrent ? item.level.color : .secondary)
                                .monospacedDigit()

                            if item.isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(item.level.color)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            item.isCurrent
                                ? item.level.color.opacity(0.10)
                                : (idx % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }

        private struct RangeItem {
            let level: VO2MaxClassification
            let range: String
            let isCurrent: Bool
        }

        private func ranges(_ t: VO2MaxThresholds) -> [RangeItem] {
            let current = info.classification
            return [
                RangeItem(level: .low,
                          range: "< \(Int(t.low))",
                          isCurrent: current == .low),
                RangeItem(level: .belowAverage,
                          range: "\(Int(t.low)) – \(Int(t.belowAvg) - 1)",
                          isCurrent: current == .belowAverage),
                RangeItem(level: .aboveAverage,
                          range: "\(Int(t.belowAvg)) – \(Int(t.high) - 1)",
                          isCurrent: current == .aboveAverage),
                RangeItem(level: .high,
                          range: "≥ \(Int(t.high))",
                          isCurrent: current == .high)
            ]
        }

        private func sexLabel(_ sex: HKBiologicalSex) -> String {
            switch sex {
            case .male:   return "男"
            case .female: return "女"
            default:      return "—"
            }
        }

        // MARK: 无用户资料

        private var noProfileSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("年龄段标准")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("请在「健康」App 中设置出生日期和生物性别，以显示年龄分组标准")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }

        // MARK: ③ 对比记录

        private func comparisonSection(previous: Double) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("对比记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    comparisonCell(
                        title: "上次",
                        value: String(format: "%.2f", previous),
                        color: .secondary
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)

                    comparisonCell(
                        title: "本次",
                        value: String(format: "%.2f", info.value),
                        color: Color(red: 0.20, green: 0.55, blue: 0.95)
                    )

                    Spacer()

                    if let delta = info.delta {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text(String(format: "%.2f", abs(delta)))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(delta >= 0 ? Color.green : Color.red)

                            Text("变化")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }

        private func comparisonCell(title: String, value: String, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
        }

        private var noHistorySection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("对比记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("暂无历史记录可供对比")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 公里分段表格卡片

private struct SplitsTableCard: View {
    let splits: [KilometerSplit]

    private var fastestIndex: Int? {
        splits.min(by: { $0.duration < $1.duration })?.index
    }

    private let colIndex: CGFloat = 44
    private let colPace: CGFloat = 68
    private let colHR: CGFloat = 52
    private let colStride: CGFloat = 52
    private let colCadence: CGFloat = 52
    private let colPower: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("公里分段")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            HStack(spacing: 0) {
                headerCell("序号", width: colIndex)
                headerCell("配速", width: colPace)
                headerCell("心率", width: colHR)
                headerCell("步幅", width: colStride)
                headerCell("步频", width: colCadence)
                headerCell("功率", width: colPower)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                    rowView(split: split, isFastest: split.index == fastestIndex)
                        .background(
                            idx % 2 == 1
                                ? Color.primary.opacity(0.03)
                                : Color.clear
                        )
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .frame(width: width, alignment: .center)
    }

    private func rowView(split: KilometerSplit, isFastest: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(split.index)")
                    .font(.system(size: 14))
                    .foregroundStyle(isFastest ? .primary : .secondary)
                    .monospacedDigit()
                    .frame(minWidth: 16)

                if isFastest {
                    Text("最快")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            .frame(width: colIndex, alignment: .leading)

            valueCell(formatPace(split.duration), width: colPace, primary: true)
            valueCell(formatInt(split.averageHeartRate), width: colHR)
            valueCell(formatStride(split.averageStrideLength), width: colStride)
            valueCell(formatInt(split.averageCadence), width: colCadence)
            valueCell(formatInt(split.averagePower), width: colPower)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func valueCell(_ text: String, width: CGFloat, primary: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? .primary : .secondary)
            .monospacedDigit()
            .frame(width: width, alignment: .center)
    }

    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    private func formatInt(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(Int(value))
    }

    private func formatStride(_ meters: Double?) -> String {
        guard let meters else { return "--" }
        return String(Int(meters * 100))
    }
}

// MARK: - 图表卡片

private struct RunMetricCard: View {
    let title: String
    let icon: String
    let color: Color
    let unit: String
    let points: [MetricPoint]
    let statLabel: String
    var secondStatLabel: String? = nil
    let averageValue: Double?
    let yFormat: (Double) -> String

    @State private var selectedDate: Date?
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    private var startDate: Date { points.first?.date ?? Date() }
    private var endDate: Date { points.last?.date ?? Date() }

    private var effectiveZoom: CGFloat {
        max(1.0, min(zoomScale * gestureScale, 4.0))
    }

    private var xDomain: ClosedRange<Date> {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return startDate...endDate }
        let visible = total / effectiveZoom
        return startDate...startDate.addingTimeInterval(visible)
    }

    private var xAxisStride: Int {
        let minutes = endDate.timeIntervalSince(startDate) / 60
        if minutes <= 20 { return 5 }
        if minutes <= 60 { return 10 }
        if minutes <= 120 { return 20 }
        return 30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chart
                .frame(height: 120)
            hint
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 30, height: 30)

                Text("\(title) (\(unit))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(statLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if let secondStatLabel {
                    Text(secondStatLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            if let avg = averageValue {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(color.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            if let selectedDate,
               let point = closestPoint(to: selectedDate) {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.gray.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart),
                                                  y: .disabled)
                    ) {
                        Text(yFormat(point.value))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(color, in: Capsule())
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: xAxisStride)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.12))
                AxisTick()
                    .foregroundStyle(Color.gray.opacity(0.3))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let minutes = Int(date.timeIntervalSince(startDate) / 60)
                        Text("\(minutes)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yFormat(v))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .gesture(
            MagnifyGesture()
                .updating($gestureScale) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    let next = zoomScale * value.magnification
                    zoomScale = max(1.0, min(next, 4.0))
                }
        )
        .padding(.horizontal, 8)
    }

    private var hint: some View {
        Text("长按查看数值 · 双指缩放")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 10)
    }

    private func closestPoint(to date: Date) -> MetricPoint? {
        points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }
}
