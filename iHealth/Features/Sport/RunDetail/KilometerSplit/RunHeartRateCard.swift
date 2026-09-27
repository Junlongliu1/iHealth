//
//  RunHeartRateCard.swift
//  iHealth
//

import SwiftUI
import Charts

/// 跑步心率卡片：折线图 + 心率区间分布
struct RunHeartRateCard: View {
    let points: [MetricPoint]
    let averageValue: Double?

    @State private var selectedDate: Date?
    @State private var zoomScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var profile = AthleteProfileStore.shared

    private let color: Color = .red
    private let icon: String = "heart.fill"
    private let unit: String = "bpm"

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

    private var maxValue: Double? { points.map(\.value).max() }
    private var minValue: Double? { points.map(\.value).min() }

    // MARK: - 心率区间

    private struct ZoneDuration: Identifiable {
        var id: Int { zone.id }
        let zone: HRZone
        let duration: TimeInterval
    }

    /// 逐点按相邻点的时间差累加到所属区间
    /// - Note: HKStatisticsCollectionQuery 的 interval 为 60s，
    ///         末点默认按 60s 计；缺失区间不强行补 0。
    private var zoneDurations: [ZoneDuration] {
        var durations = [TimeInterval](repeating: 0, count: HRZone.all.count)

        guard !points.isEmpty else {
            return HRZone.all.map { ZoneDuration(zone: $0, duration: 0) }
        }

        for i in 0..<points.count {
            let point = points[i]
            let dt: TimeInterval = {
                if i + 1 < points.count {
                    return max(points[i + 1].date.timeIntervalSince(point.date), 0)
                }
                return 60
            }()

            if let idx = zoneIndex(for: point.value) {
                durations[idx] += dt
            }
        }

        return zip(HRZone.all, durations).map {
            ZoneDuration(zone: $0.0, duration: $0.1)
        }
    }

    private var totalZoneDuration: TimeInterval {
        zoneDurations.reduce(0) { $0 + $1.duration }
    }

    /// 落在哪个区间（左闭右开，最高段用闭区间）
    /// 低于 Z1 下限的心率归入 Z1（视作恢复/热身）
    private func zoneIndex(for value: Double) -> Int? {
        let zones = HRZone.all
        guard !zones.isEmpty else { return nil }
        for (idx, zone) in zones.enumerated() {
            let r = zone.range(maxHR: profile.maxHR, restingHR: profile.restingHR)
            let isLast = (idx == zones.count - 1)
            if value >= Double(r.low) && (isLast || value < Double(r.high)) {
                return idx
            }
        }
        return 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chart.frame(height: 130)
            zoneSection
            hint
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("心率")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let avg = averageValue {
                    Text("平均 \(Int(avg.rounded()))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let mx = maxValue, let mn = minValue, mx > mn {
                    HStack(spacing: 4) {
                        Text("↓\(Int(mn))").foregroundStyle(.tertiary)
                        Text("↑\(Int(mx))").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11))
                    .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 图表（沿用 RunMetricChartCard 的样式）

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.24), color.opacity(0.02)],
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
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
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
                        Text("\(Int(point.value))")
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
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.12))
                AxisTick().foregroundStyle(Color.gray.opacity(0.3))
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
                AxisGridLine().foregroundStyle(Color.gray.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
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

    // MARK: - 心率区间分布

    private var zoneSection: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            VStack(spacing: 7) {
                ForEach(zoneDurations) { item in
                    zoneRow(item)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func zoneRow(_ item: ZoneDuration) -> some View {
        let total = totalZoneDuration
        let fraction = total > 0 ? item.duration / total : 0
        let isActive = item.duration > 0

        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("Z\(item.zone.id)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(item.zone.color)
                Text(item.zone.name)
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? .primary : .tertiary)
                    .lineLimit(1)
            }
            .frame(width: 78, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(item.zone.color.opacity(0.85))
                        .frame(width: max(geo.size.width * fraction,
                                          isActive ? 3 : 0))
                }
            }
            .frame(height: 6)

            Text(formatDuration(item.duration))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? .primary : .tertiary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
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

    private func formatDuration(_ d: TimeInterval) -> String {
        guard d > 0 else { return "0:00" }
        let total = Int(d.rounded())
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            let h = m / 60
            return String(format: "%d:%02d:%02d", h, m % 60, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
