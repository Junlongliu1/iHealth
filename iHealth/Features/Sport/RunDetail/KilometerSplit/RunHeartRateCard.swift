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

    // MARK: - Y 轴范围（贴合数据，让波动更明显）

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let mn = values.min(), let mx = values.max(), mx > mn else {
            let base = averageValue ?? points.first?.value ?? 0
            let pad = max(abs(base) * 0.02, 0.5)
            return (base - pad)...(base + pad)
        }
        let span = mx - mn
        let padding = max(span * 0.12, 0.3)
        return (mn - padding)...(mx + padding)
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

            if points.isEmpty {
                emptyChart
            } else {
                chart.frame(height: 132)
            }

            zoneSection
            footer
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("心率")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let avg = averageValue {
                    Text("平均 \(String(format: "%.1f", avg))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if let mx = maxValue, let mn = minValue, mx > mn {
                    HStack(spacing: 5) {
                        Text("↓\(String(format: "%.1f", mn))")
                        Text("↑\(String(format: "%.1f", mx))")
                    }
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    // MARK: - Empty

    private var emptyChart: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .padding(.horizontal, 16)
            VStack(spacing: 6) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(.quaternary)
                Text("暂无心率数据")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 132)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }

            // 平均值虚线
            if let avg = averageValue {
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(color.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // 选中态
            if let selectedDate,
               let point = closestPoint(to: selectedDate) {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Color.gray.opacity(0.30))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
                .symbolSize(60)
                .annotation(
                    position: .top,
                    spacing: 8,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    Text(String(format: "%.1f", point.value))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(color.gradient)
                                .shadow(color: color.opacity(0.35), radius: 5, y: 2)
                        }
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: xAxisStride)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.08))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let minutes = Int(date.timeIntervalSince(startDate) / 60)
                        Text("\(minutes)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
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
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            VStack(spacing: 8) {
                ForEach(zoneDurations) { item in
                    zoneRow(item)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private func zoneRow(_ item: ZoneDuration) -> some View {
        let total = totalZoneDuration
        let fraction = total > 0 ? item.duration / total : 0
        let isActive = item.duration > 0

        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                Text("Z\(item.zone.id)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive
                                     ? AnyShapeStyle(item.zone.color)
                                     : AnyShapeStyle(.tertiary))
                    .frame(width: 18, alignment: .leading)
                    .monospacedDigit()

                Text(item.zone.name)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive
                                     ? AnyShapeStyle(.primary)
                                     : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
            }
            .frame(width: 72, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    item.zone.color.opacity(isActive ? 0.95 : 0.0),
                                    item.zone.color.opacity(isActive ? 0.70 : 0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * fraction,
                                          isActive ? 4 : 0))
                }
            }
            .frame(height: 8)

            Text(formatDuration(item.duration))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(isActive
                                 ? AnyShapeStyle(.primary)
                                 : AnyShapeStyle(.tertiary))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isActive
                                 ? AnyShapeStyle(.secondary)
                                 : AnyShapeStyle(.tertiary))
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            Text("长按查看 · 双指缩放")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            Spacer(minLength: 0)

            if effectiveZoom > 1.01 {
                Text(String(format: "%.1f×", effectiveZoom))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.10), in: Capsule())
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: effectiveZoom > 1.01)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 11)
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
