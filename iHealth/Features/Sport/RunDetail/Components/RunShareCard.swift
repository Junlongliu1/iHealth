//
//  RunShareCard.swift
//  iHealth
//

import SwiftUI
import UIKit
import CoreLocation

// MARK: - 分享图片卡片

/// 4:3 横版布局（600 × 450），路线居中于上半部，数据以玻璃面板浮在底部。
/// scale 3 输出 1800 × 1350 高清图。
struct RunShareCard: View {
    let detail: RunDetail?
    let workout: Workout

    // MARK: - 可调参数

    /// 路线区域水平内边距（越小路线越宽）
    private let routeHorizontalInset: CGFloat = 20
    /// 底部预留高度（数据面板高度 + 与路线的间距，越小路线越高）
    private let routeVerticalReserve: CGFloat = 118

    // MARK: - 数据（与顶部卡片一致）

    private var distanceValue: String {
        guard let d = detail?.distance, d > 0 else { return "--" }
        let km = (d / 1000).truncated(to: 2)
        return String(format: "%.2f", km)
    }

    private var durationText: String {
        RunDetailFormat.duration(detail?.duration)
    }

    private var paceText: String {
        RunDetailFormat.pace(detail?.averagePace)
    }

    private var cadenceText: String {
        RunDetailFormat.cadence(detail?.averageCadence)
    }

    private var strideText: String {
        guard let s = detail?.averageStrideLength else { return "--" }
        return String(Int(s * 100))
    }

    private var heartRateText: String {
        RunDetailFormat.heartRate(detail?.averageHeartRate)
    }

    // MARK: 日期

    private var dateText: String {
        workout.startDate.formatted(
            .dateTime.year().month(.twoDigits).day(.twoDigits)
        )
    }

    private var timeText: String {
        workout.startDate.formatted(.dateTime.hour().minute())
    }

    private var weekdayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEEE"
        return f.string(from: workout.startDate)
    }

    private var hasRoute: Bool {
        guard let route = detail?.route else { return false }
        return route.count >= 2
    }

    // MARK: Body

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .frame(width: 600, height: 450)
    }

    // MARK: 背景

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.065)

            RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.44, blue: 0.10).opacity(0.42),
                    Color(red: 1.00, green: 0.44, blue: 0.10).opacity(0.0)
                ],
                center: .init(x: 0.04, y: 0.0),
                startRadius: 10,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    Color(red: 0.36, green: 0.28, blue: 1.00).opacity(0.24),
                    Color(red: 0.36, green: 0.28, blue: 1.00).opacity(0.0)
                ],
                center: .init(x: 1.04, y: 1.04),
                startRadius: 10,
                endRadius: 540
            )

            RadialGradient(
                colors: [
                    Color(red: 1.00, green: 0.28, blue: 0.50).opacity(0.06),
                    Color(red: 1.00, green: 0.28, blue: 0.50).opacity(0.0)
                ],
                center: .init(x: 0.94, y: 0.52),
                startRadius: 10,
                endRadius: 340
            )
        }
    }

    // MARK: 内容

    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer().frame(height: 14)

            routeWithData
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer().frame(height: 12)

            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(goldGradient)
                        .frame(width: 5, height: 5)

                    Text("RUN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(4.2)
                        .foregroundStyle(goldGradient)
                }

                HStack(spacing: 8) {
                    Text(dateText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .monospacedDigit()

                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 2.5, height: 2.5)

                    Text(weekdayText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.50))

                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 2.5, height: 2.5)

                    Text(timeText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.50))
                        .monospacedDigit()
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.00, green: 0.48, blue: 0.15).opacity(0.24),
                                Color(red: 1.00, green: 0.48, blue: 0.15).opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.15),
                                .white.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: "figure.run")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(goldGradient)
            }
        }
    }

    // MARK: - 路线 + 数据（一张卡）

    private var routeWithData: some View {
        ZStack(alignment: .bottom) {
            routeBackground

            dataPanel
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.14),
                            .white.opacity(0.06),
                            .white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
    }

    // MARK: 路线背景

    private var routeBackground: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.opacity(0.035)

                mapGrid

                // 路线可用区域
                let availW = geo.size.width - routeHorizontalInset
                let availH = max(geo.size.height - routeVerticalReserve, 60)
                let side = min(availW, availH)

                if hasRoute {
                    routeContent(in: CGSize(width: side, height: side))
                        .frame(width: side, height: side)
                        .position(
                            x: geo.size.width / 2,
                            y: availH / 2 + 6
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.white.opacity(0.22))
                        Text("无路线数据")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.32))
                    }
                    .position(
                        x: geo.size.width / 2,
                        y: availH / 2 + 6
                    )
                }
            }
        }
    }

    private var mapGrid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 26
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(.white.opacity(0.028)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func routeContent(in size: CGSize) -> some View {
        let route = detail?.route ?? []
        let path = makePath(route: route, size: size)
        let startPt = endpointPoint(route: route, size: size, isStart: true)
        let endPt = endpointPoint(route: route, size: size, isStart: false)

        ZStack {
            // 外层泛光
            path.stroke(
                Color(red: 1.00, green: 0.52, blue: 0.18).opacity(0.16),
                style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
            )

            // 内层发光
            path.stroke(
                Color(red: 1.00, green: 0.55, blue: 0.20).opacity(0.32),
                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
            )

            // 主路线
            path.stroke(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.88, blue: 0.48),
                        Color(red: 1.00, green: 0.60, blue: 0.22),
                        Color(red: 1.00, green: 0.42, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
            )

            if let startPt {
                endpointMarker(
                    color: Color(red: 0.30, green: 0.90, blue: 0.44)
                )
                .position(startPt)
            }

            if let endPt {
                endpointMarker(
                    color: Color(red: 1.00, green: 0.36, blue: 0.36)
                )
                .position(endPt)
            }
        }
    }

    private func endpointMarker(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 26, height: 26)

            Circle()
                .fill(color.opacity(0.45))
                .frame(width: 16, height: 16)

            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white, lineWidth: 1.6))
                .shadow(color: color.opacity(0.70), radius: 6)
        }
    }

    // MARK: - 玻璃数据面板

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 0) {

            // 主行：距离 + 时长
            HStack(alignment: .bottom, spacing: 0) {

                VStack(alignment: .leading, spacing: 1) {
                    Text("距离")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.42))

                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(distanceValue)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(distanceGradient)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .shadow(
                                color: Color(red: 1.00, green: 0.52, blue: 0.18).opacity(0.60),
                                radius: 16,
                                y: 5
                            )

                        Text("km")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.bottom, 6)
                    }
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("运动时间")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.42))

                    Text(durationText)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.bottom, 2)
            }

            Spacer().frame(height: 10)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.16),
                            .white.opacity(0.06),
                            .white.opacity(0.01)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)

            Spacer().frame(height: 10)

            // 副行：配速 / 步频 / 步幅 / 心率
            HStack(alignment: .top, spacing: 0) {
                compactMetric(
                    title: "平均配速",
                    value: paceText,
                    unit: detail?.averagePace != nil ? "/km" : ""
                )
                compactMetric(
                    title: "平均步频",
                    value: cadenceText,
                    unit: detail?.averageCadence != nil ? "/min" : ""
                )
                compactMetric(
                    title: "平均步幅",
                    value: strideText,
                    unit: detail?.averageStrideLength != nil ? "cm" : ""
                )
                compactMetric(
                    title: "平均心率",
                    value: heartRateText,
                    unit: detail?.averageHeartRate != nil ? "bpm" : ""
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background { glassBackground }
    }

    private var glassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.02, green: 0.03, blue: 0.06).opacity(0.78))

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.09), location: 0.0),
                            .init(color: .white.opacity(0.02), location: 0.35),
                            .init(color: .white.opacity(0.0), location: 0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.18),
                            .white.opacity(0.06),
                            .white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
    }

    private func compactMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: 16, height: 16)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.62, blue: 0.30),
                                    Color(red: 0.98, green: 0.30, blue: 0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("iHealth")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Text("记录每一次奔跑")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    // MARK: - 渐变

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.82, blue: 0.46),
                Color(red: 1.00, green: 0.50, blue: 0.20)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var distanceGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 1.00, green: 0.92, blue: 0.64), location: 0.0),
                .init(color: Color(red: 1.00, green: 0.70, blue: 0.28), location: 0.55),
                .init(color: Color(red: 0.96, green: 0.42, blue: 0.10), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - 坐标转换

    /// 路线采样边距系数：1.04 = 上下左右各留 2%，越小路线越饱满
    private let routePaddingFactor: Double = 1.04

    private func normalizedRoutePoints(route: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard route.count >= 2 else { return [] }

        let step = max(1, route.count / 300)
        var sampled: [CLLocationCoordinate2D] = stride(
            from: 0, to: route.count, by: step
        ).map { route[$0] }

        if let last = route.last, sampled.last?.latitude != last.latitude
            || sampled.last?.longitude != last.longitude {
            sampled.append(last)
        }

        let lats = sampled.map(\.latitude)
        let lons = sampled.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }

        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        let span = max(latRange, lonRange)
        guard span > 0.00005 else { return [] }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let halfSpan = span / 2 * routePaddingFactor

        let minLatN = centerLat - halfSpan
        let minLonN = centerLon - halfSpan

        return sampled.map { coord in
            let x = (coord.longitude - minLonN) / (2 * halfSpan)
            let y = 1 - (coord.latitude - minLatN) / (2 * halfSpan)
            return CGPoint(x: x, y: y)
        }
    }

    private func makePath(route: [CLLocationCoordinate2D], size: CGSize) -> Path {
        var path = Path()
        let points = normalizedRoutePoints(route: route)
        guard !points.isEmpty else { return path }

        for (i, pt) in points.enumerated() {
            let screen = CGPoint(x: pt.x * size.width, y: pt.y * size.height)
            if i == 0 {
                path.move(to: screen)
            } else {
                path.addLine(to: screen)
            }
        }
        return path
    }

    private func endpointPoint(
        route: [CLLocationCoordinate2D],
        size: CGSize,
        isStart: Bool
    ) -> CGPoint? {
        let points = normalizedRoutePoints(route: route)
        guard let pt = isStart ? points.first : points.last else { return nil }
        return CGPoint(x: pt.x * size.width, y: pt.y * size.height)
    }
}

// MARK: - UIActivityViewController 包装

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        vc.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { dismiss() }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 分享项

struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}
