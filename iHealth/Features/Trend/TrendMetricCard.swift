//  TrendMetricCard.swift
//  iHealth
//
//  通用趋势指标卡片（折线样式）。
//  · 头部：图标 + 标题；下方大号最新值 + 平均值
//  · 每张卡片内部维护自己的选中日期
//  · 长按卡片头部 → 打开详情页
//  · 按住图表 → 显示竖线 + 固定磨砂气泡

import SwiftUI
import Charts

struct TrendMetricCard<Detail: View>: View {
    let title: String
    let icon: String
    let color: Color
    let points: [TrendDataPoint]
    let trendRange: TrendRange
    let valueFormatter: (Double) -> String
    let yAxisFormatter: (Double) -> String
    @ViewBuilder let detailContent: () -> Detail

    @State private var selectedDate: Date?
    @State private var showDetail = false

    // MARK: 派生

    private var values: [Double] { points.compactMap(\.value) }

    private var averageValue: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var maxValue: Double? { values.max() }
    private var minValue: Double? { values.min() }

    private var latestValue: Double? {
        points.last(where: { $0.value != nil })?.value
    }

    private var deltaFromAverage: Double? {
        guard let latest = latestValue, let avg = averageValue else { return nil }
        return latest - avg
    }

    private var selectedPoint: TrendDataPoint? {
        guard let selectedDate else { return nil }
        let nearest = points.min {
            abs($0.date.timeIntervalSince(selectedDate)) <
            abs($1.date.timeIntervalSince(selectedDate))
        }
        guard let nearest,
              abs(nearest.date.timeIntervalSince(selectedDate)) <= 12 * 3600 else {
            return nil
        }
        return nearest
    }

    private var hasAnyData: Bool { !values.isEmpty }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) {
                    showDetail = true
                }

            if hasAnyData {
                chart.frame(height: 170)
            } else {
                emptyState
            }

            if hasAnyData {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                footer
            }
        }
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 20, padding: 0)
        .padding(.horizontal)
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                detailContent()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let latest = latestValue {
                    Text(valueFormatter(latest))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.45), value: latest)
                } else {
                    Text("--")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 8)

                if let avg = averageValue {
                    HStack(spacing: 4) {
                        Text("平均")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)

                        Text(valueFormatter(avg))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.45), value: avg)

                        if let delta = deltaFromAverage, abs(delta) > 0.001 {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(delta >= 0 ? .green : .red)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.snappy(duration: 0.3), value: deltaFromAverage ?? 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(color.opacity(0.35))
            Text("暂无数据")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            if let avg = averageValue {
                RuleMark(y: .value("平均", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(color.opacity(0.45))
                    .zIndex(0)
            }

            ForEach(points) { p in
                if let v = p.value {
                    LineMark(
                        x: .value("日期", p.date),
                        y: .value(title, v)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .zIndex(1)
                }
            }

            if let p = selectedPoint, let v = p.value {
                RuleMark(x: .value("选中", p.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .zIndex(2)

                PointMark(
                    x: .value("日期", p.date),
                    y: .value(title, v)
                )
                .foregroundStyle(color)
                .symbolSize(70)
                .zIndex(3)
                .annotation(
                    position: .top,
                    spacing: 8,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    selectionCallout(date: p.date, value: v)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { mark in
                AxisGridLine()
                    .foregroundStyle(Color.primary.opacity(0.05))
                AxisValueLabel {
                    if let d = mark.as(Date.self) {
                        Text(xLabel(d))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { mark in
                AxisGridLine()
                    .foregroundStyle(Color.primary.opacity(0.05))
                AxisValueLabel {
                    if let v = mark.as(Double.self) {
                        Text(yAxisFormatter(v))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 8)
        .animation(.smooth(duration: 0.5), value: points)
        .animation(.snappy(duration: 0.18), value: selectedPoint?.id)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            footerItem(
                title: "最大",
                value: maxValue.map(valueFormatter) ?? "--",
                color: color
            )

            footerDivider

            footerItem(
                title: "最小",
                value: minValue.map(valueFormatter) ?? "--",
                color: color.opacity(0.7)
            )

            footerDivider

            footerItem(
                title: "天数",
                value: "\(values.count)",
                color: .secondary
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 22)
    }

    private func footerItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.4), value: value)
    }

    // MARK: - X 轴

    private var xAxisValues: AxisMarkValues {
        switch trendRange {
        case .sevenDays:  return .stride(by: .day, count: 1)
        case .thirtyDays: return .stride(by: .day, count: 5)
        case .sixtyDays:  return .stride(by: .day, count: 10)
        }
    }

    private func xLabel(_ date: Date) -> String {
        switch trendRange {
        case .sevenDays:
            let weekday = Calendar.current.component(.weekday, from: date)
            return ["日", "一", "二", "三", "四", "五", "六"][weekday - 1]
        case .thirtyDays, .sixtyDays:
            return "\(Calendar.current.component(.day, from: date))"
        }
    }

    // MARK: - 单线气泡（单行）

    private func selectionCallout(date: Date, value: Double) -> some View {
        HStack(spacing: 5) {
            Text(date.formatted(
                .dateTime.month(.defaultDigits).day()
                    .locale(Locale(identifier: "zh_CN"))
            ))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)

            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Text(valueFormatter(value))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color(.systemBackground).opacity(0.92))
                .background(.ultraThinMaterial, in: Capsule())
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
