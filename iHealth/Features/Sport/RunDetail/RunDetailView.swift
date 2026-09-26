//
//  RunDetailView.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI

struct RunDetailView: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @Namespace private var glassNamespace

    @State private var detail: RunDetail?
    @State private var isLoading = true
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let topSafeArea = proxy.safeAreaInsets.top
            let heroHeight = max(proxy.size.height * 0.55, 420)
            let overlap: CGFloat = 36

            ZStack(alignment: .top) {

                // ① 底层背景
                Color(.systemBackground)
                    .ignoresSafeArea()

                // ② 地图层
                RunHeroMapView(
                    route: detail?.route ?? [],
                    kilometerMarkers: detail?.kilometerMarkers ?? [],
                    isLoading: isLoading
                )
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
                RunTopBar(
                    onBack: { dismiss() },
                    onShare: { shareRoute() },
                    onMore: { /* TODO */ },
                    namespace: glassNamespace
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            detail = await WorkoutStore.loadRunDetail(for: workout)
            isLoading = false
        }
    }

    private func pullStretch(scrollOffset: CGFloat, heroHeight: CGFloat) -> CGFloat {
        guard scrollOffset < 0 else { return 1 }
        let extra = min(-scrollOffset / heroHeight * 0.5, 0.3)
        return 1 + extra
    }

    // MARK: - 内容卡片

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            Capsule()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 4)

            RunSummaryHeader(detail: detail, workout: workout)

            Rectangle()
                .fill(Color.primary.opacity(0.05))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

            RunMetricsGrid(detail: detail)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

            detailCards
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 36,
                topTrailingRadius: 36,
                style: .continuous
            )
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.14), radius: 30, x: 0, y: -12)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 36,
                topTrailingRadius: 36,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 详情图表卡片

    private var detailCards: some View {
        let s = detail?.series ?? RunSeries()

        return VStack(spacing: 14) {
            if let vo2 = detail?.vo2Max {
                VO2MaxCard(info: vo2)
            }

            if let splits = detail?.splits, !splits.isEmpty {
                SplitsTableCard(splits: splits)
            }

            if let hr = detail?.averageHeartRate {
                RunMetricChartCard(
                    title: "心率",
                    icon: "heart.fill",
                    color: .red,
                    unit: "bpm",
                    points: s.heartRate,
                    statLabel: "平均 \(RunDetailFormat.heartRate(hr))",
                    averageValue: hr,
                    yFormat: { "\(Int($0))" }
                )
            }

            if let pace = detail?.averagePace {
                RunMetricChartCard(
                    title: "配速",
                    icon: "speedometer",
                    color: .orange,
                    unit: "min/km",
                    points: s.pace,
                    statLabel: "平均 \(RunDetailFormat.pace(pace))",
                    averageValue: pace,
                    yFormat: { RunDetailFormat.paceShort($0) }
                )
            }

            if let stride = detail?.averageStrideLength {
                RunMetricChartCard(
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
                RunMetricChartCard(
                    title: "步频",
                    icon: "metronome",
                    color: .blue,
                    unit: "步/分",
                    points: s.cadence,
                    statLabel: "平均 \(RunDetailFormat.cadence(cadence))",
                    averageValue: cadence,
                    yFormat: { "\(Int($0.rounded()))" }
                )
            }

            if !s.groundContactTime.isEmpty {
                let avg = s.groundContactTime.map(\.value).reduce(0, +)
                        / Double(s.groundContactTime.count)
                RunMetricChartCard(
                    title: "触地时间",
                    icon: "timer",
                    color: .purple,
                    unit: "ms",
                    points: s.groundContactTime,
                    statLabel: "平均 \(RunDetailFormat.int(avg))",
                    averageValue: avg,
                    yFormat: { "\(Int($0))" }
                )
            }

            if let vo = detail?.verticalOscillation {
                RunMetricChartCard(
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
                RunMetricChartCard(
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
                RunMetricChartCard(
                    title: "海拔",
                    icon: "mountain.2.fill",
                    color: .orange,
                    unit: "m",
                    points: s.elevation,
                    statLabel: "最大 \(Int(maxV)) 最小 \(Int(minV))",
                    secondStatLabel: "↑\(RunDetailFormat.int(elev))m",
                    averageValue: avgV,
                    yFormat: { "\(Int($0))" }
                )
            }
        }
    }

    private func shareRoute() {
        // TODO: 分享路线
    }
}

// MARK: - 详情页通用格式化

enum RunDetailFormat {

    static func duration(_ d: TimeInterval?) -> String {
        guard let d else { return "--" }
        let total = Int(d)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func pace(_ p: TimeInterval?) -> String {
        guard let p, p.isFinite, p > 0 else { return "--" }
        let total = Int(p.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    static func paceShort(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    static func int(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(Int(v))
    }

    static func heartRate(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(Int(v.rounded()))
    }

    static func power(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(Int(v.rounded()))
    }

    static func cadence(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(Int(v.rounded()))
    }
}
