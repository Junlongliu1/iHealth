//
//  MetricCard.swift
//  iHealth
//
//  所有方形小卡片的通用实现。
//  8 个指标卡片（步数 / 日照 / 基础代谢 / 活动消耗 / 心率 / 血氧 / 静息心率 / HRV）
//  只需传入图标、颜色、单位、数据源和图表样式。
//

import SwiftUI
import Charts

struct MetricCard<Hourly: Identifiable>: View {

    // MARK: - 配置

    let icon: String
    let iconColor: Color
    let title: String
    let unit: String
    let hourly: [Hourly]

    /// 从元素中取小时（0–23）
    let hour: (Hourly) -> Int
    /// 从元素中取值（nil 表示该小时无数据）
    let value: (Hourly) -> Double?

    /// 图表样式：柱状（显示累计值）或曲线（显示平均值）
    let style: Style

    /// 曲线样式在「完全无数据」时使用的 Y 轴范围
    var fallbackYRange: ClosedRange<Double> = 50...100
    /// 曲线样式 Y 轴 padding 比例
    var yPaddingRatio: Double = 0.3
    /// 曲线样式 Y 轴范围上限（可选，用于血氧等有物理边界的指标）
    var clampRange: ClosedRange<Double>? = nil

    enum Style { case bar, line }

    // MARK: - 派生值

    private var values: [Double] { hourly.compactMap(value) }

    private var total: Double { values.reduce(0, +) }

    private var average: Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private var maxHour: Int { hourly.map(hour).max() ?? 0 }

    private var displayText: String {
        switch style {
        case .bar:
            return "\(Int(total.rounded()))"
        case .line:
            guard let avg = average else { return "--" }
            return "\(Int(avg.rounded()))"
        }
    }

    private var hasData: Bool {
        switch style {
        case .bar:  return !hourly.isEmpty && total > 0
        case .line: return !values.isEmpty
        }
    }

    // MARK: - 视图

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(displayText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(iconColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("今天")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Group {
                if hasData {
                    chart
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .cardStyle(radius: 14)
    }

    // MARK: - 标题

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 图表

    @ViewBuilder
    private var chart: some View {
        Chart {
            ForEach(hourly) { item in
                if style == .bar {
                    BarMark(
                        x: .value("小时", hour(item)),
                        y: .value(title, value(item) ?? 0),
                        width: .fixed(6)
                    )
                    .foregroundStyle(iconColor.gradient)
                    .cornerRadius(2)
                } else if let v = value(item) {
                    AreaMark(
                        x: .value("小时", hour(item)),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value(title, v)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [iconColor.opacity(0.30), iconColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("小时", hour(item)),
                        y: .value(title, v)
                    )
                    .foregroundStyle(iconColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        }
        .chartXScale(domain: 0...max(1, maxHour))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: MetricHourAxis.ticks(upTo: maxHour)) { mark in
                AxisValueLabel {
                    if let h = mark.as(Int.self) {
                        Text(MetricHourAxis.label(for: h))
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.padding(.top, 2) }
    }

    private var emptyState: some View {
        Text("暂无数据")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Y 轴

    private var yDomain: ClosedRange<Double> {
        switch style {
        case .bar:
            let hi = values.max() ?? 1
            return 0...max(hi, 1)

        case .line:
            guard let lo = values.min(), let hi = values.max(), lo < hi else {
                return fallbackYRange
            }
            let pad = max((hi - lo) * yPaddingRatio, 2)
            let lower = lo - pad
            let upper = hi + pad
            if let clamp = clampRange {
                return max(clamp.lowerBound, lower)...min(clamp.upperBound, upper)
            }
            return lower...upper
        }
    }
}
