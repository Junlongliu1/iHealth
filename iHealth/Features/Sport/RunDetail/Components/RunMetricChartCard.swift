//
//  RunMetricChartCard.swift
//  iHealth
//

import SwiftUI
import Charts

// MARK: - 单项指标图表卡片（心率 / 配速 / 步幅 / 步频 / 触地 / 垂直 / 功率 / 海拔）

struct RunMetricChartCard: View {
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
