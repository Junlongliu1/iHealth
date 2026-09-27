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

                Color(.systemBackground)
                    .ignoresSafeArea()

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
            ShoeAssignmentCard(workout: workout)

            if let vo2 = detail?.vo2Max {
                VO2MaxCard(info: vo2)
            }

            if let splits = detail?.splits, !splits.isEmpty {
                SplitsTableCard(splits: splits)
            }

            if let hr = detail?.averageHeartRate {
                RunHeartRateCard(
                    points: s.heartRate,
                    averageValue: hr
                )
            }

            if let pace = detail?.averagePace {
                RunMetricChartCard(
                    title: "配速",
                    icon: "speedometer",
                    color: .orange,
                    unit: "min/km",
                    points: s.pace,
                    statLabel: "平均 \(RunDetailFormat.pacePrecise(pace))",
                    averageValue: pace,
                    yFormat: { RunDetailFormat.paceShortPrecise($0) }
                )
            }

            if let stride = detail?.averageStrideLength {
                RunMetricChartCard(
                    title: "步幅",
                    icon: "ruler",
                    color: .green,
                    unit: "cm",
                    points: s.strideLength,
                    statLabel: "平均 \(String(format: "%.2f", stride * 100))",
                    averageValue: stride,
                    yFormat: { String(format: "%.1f", $0 * 100) }
                )
            }

            if let cadence = detail?.averageCadence {
                RunMetricChartCard(
                    title: "步频",
                    icon: "metronome",
                    color: .blue,
                    unit: "步/分",
                    points: s.cadence,
                    statLabel: "平均 \(String(format: "%.1f", cadence))",
                    averageValue: cadence,
                    yFormat: { String(format: "%.1f", $0) }
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
                    statLabel: "平均 \(String(format: "%.1f", avg))",
                    averageValue: avg,
                    yFormat: { String(format: "%.1f", $0) }
                )
            }

            if let vo = detail?.verticalOscillation {
                RunMetricChartCard(
                    title: "垂直振幅",
                    icon: "arrow.up.and.down",
                    color: .cyan,
                    unit: "cm",
                    points: s.verticalOscillation,
                    statLabel: "平均 \(String(format: "%.2f", vo))",
                    averageValue: vo,
                    yFormat: { String(format: "%.2f", $0) }
                )
            }

            if let power = detail?.averagePower {
                RunMetricChartCard(
                    title: "跑步功率",
                    icon: "bolt.fill",
                    color: .pink,
                    unit: "W",
                    points: s.power,
                    statLabel: "平均 \(String(format: "%.2f", power))",
                    averageValue: power,
                    yFormat: { String(format: "%.1f", $0) }
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
                    statLabel: "最大 \(String(format: "%.1f", maxV)) 最小 \(String(format: "%.1f", minV))",
                    secondStatLabel: "↑\(String(format: "%.1f", elev))m",
                    averageValue: avgV,
                    yFormat: { String(format: "%.1f", $0) }
                )
            }
        }
    }

    private func shareRoute() {
        // TODO: 分享路线
    }
}

// MARK: - 跑鞋关联卡片

struct ShoeAssignmentCard: View {
    let workout: Workout

    @State private var store = RunningShoeStore.shared
    @State private var showPicker = false

    private var assignedShoe: RunningShoe? {
        store.shoe(for: workout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("跑鞋")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Spacer()

                if assignedShoe != nil {
                    Button {
                        showPicker = true
                    } label: {
                        Text("更换")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if let shoe = assignedShoe {
                shoeRow(shoe)
            } else {
                assignButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
        .sheet(isPresented: $showPicker) {
            ShoePickerSheet(workout: workout)
        }
    }

    // MARK: 已关联

    private func shoeRow(_ shoe: RunningShoe) -> some View {
        let total = store.totalDistance(for: shoe, workouts: [workout])
        let progress = store.wearProgress(for: shoe, workouts: [workout])
        let wear = ShoeWearLevel.from(progress: progress)

        return Button {
            showPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(shoe.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "shoeprints.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(shoe.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(shoe.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if store.isDefault(shoe) {
                                Text("默认")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.orange, in: Capsule())
                            }
                        }

                        Text("本次 \(formatKm(workout.distance))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // 磨损进度条
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(wear.color.gradient)
                                .frame(width: max(geo.size.width * min(progress, 1), 4))
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("累计 \(formatKm(total))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Spacer()

                        Text(wear.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(wear.color)
                    }
                }
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 未关联

    private var assignButton: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)

                Text("关联跑鞋")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatKm(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return "—" }
        return String(format: "%.2f km", meters / 1000)
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

    static func pacePrecise(_ p: TimeInterval?) -> String {
        guard let p, p.isFinite, p > 0 else { return "--" }
        let minutes = Int(p) / 60
        let seconds = p - Double(minutes) * 60
        return String(format: "%d'%04.1f\"", minutes, seconds)
    }

    static func paceShort(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    static func paceShortPrecise(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = seconds - Double(minutes) * 60
        return String(format: "%d'%04.1f\"", minutes, secs)
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
        return String(Int(v))
    }

    static func cadence(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(Int(v))
    }
}
