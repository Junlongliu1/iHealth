//
//  MetricDetailComponents.swift
//  iHealth
//
//  所有「日 / 周 / 月」详情页共享的枚举、状态与导航组件。
//

import SwiftUI
import Charts

// MARK: - 时间范围

enum MetricRange: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day:   return "日"
        case .week:  return "周"
        case .month: return "月"
        }
    }
}

// MARK: - 顶部范围选择器

struct MetricRangePicker: View {
    @Binding var selection: MetricRange

    var body: some View {
        Picker("范围", selection: $selection) {
            ForEach(MetricRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - 导航条（左右箭头 + 居中标题）

struct MetricRangeNavigator: View {
    @Binding var selection: MetricRange
    let currentDay: Date
    let weekAnchor: Date
    let monthAnchor: Date
    let canGoForward: Bool
    let onShift: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { onShift(-1) } label: {
                navArrow(systemName: "chevron.left", enabled: true)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Text(navTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.interpolate)

            Spacer(minLength: 4)

            Button { onShift(1) } label: {
                navArrow(systemName: "chevron.right", enabled: canGoForward)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(.horizontal, 4)
    }

    private func navArrow(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(enabled ? 0.06 : 0.03)))
            .contentShape(Circle())
    }

    private var navTitle: String {
        MetricNavigation.title(
            range: selection,
            currentDay: currentDay,
            weekAnchor: weekAnchor,
            monthAnchor: monthAnchor
        )
    }
}

// MARK: - 导航辅助

enum MetricNavigation {

    static func title(
        range: MetricRange,
        currentDay: Date,
        weekAnchor: Date,
        monthAnchor: Date
    ) -> String {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .day:
            let today = calendar.startOfDay(for: now)
            let day = calendar.startOfDay(for: currentDay)
            if day == today { return "今天" }
            return shortDate(day, format: "M月d日 EEE")

        case .week:
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start
            if anchorWeekStart == thisWeekStart { return "本周" }
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: anchorWeekStart)!
            return "\(shortDate(anchorWeekStart, format: "M月d日"))–\(shortDate(weekEnd, format: "M月d日"))"

        case .month:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)!.start
            let anchorMonthStart = calendar.dateInterval(of: .month, for: monthAnchor)!.start
            if anchorMonthStart == thisMonthStart { return "本月" }
            return shortDate(anchorMonthStart, format: "yyyy年M月")
        }
    }

    static func canGoForward(
        range: MetricRange,
        currentDay: Date,
        weekAnchor: Date,
        monthAnchor: Date
    ) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .day:
            return calendar.startOfDay(for: currentDay) < calendar.startOfDay(for: now)
        case .week:
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start
            return anchorWeekStart < thisWeekStart
        case .month:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)!.start
            let anchorMonthStart = calendar.dateInterval(of: .month, for: monthAnchor)!.start
            return anchorMonthStart < thisMonthStart
        }
    }

    /// 返回 nil 表示不允许移动（已到最前/最后）
    static func shift(
        range: MetricRange,
        by offset: Int,
        currentDay: Date,
        weekAnchor: Date,
        monthAnchor: Date
    ) -> MetricAnchor? {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .day:
            let today = calendar.startOfDay(for: now)
            guard let newDay = calendar.date(byAdding: .day, value: offset, to: currentDay),
                  newDay <= today else { return nil }
            return .day(newDay)

        case .week:
            guard let newWeek = calendar.date(byAdding: .weekOfYear, value: offset, to: weekAnchor) else { return nil }
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let newWeekStart = calendar.dateInterval(of: .weekOfYear, for: newWeek)!.start
            guard newWeekStart <= thisWeekStart else { return nil }
            return .week(newWeek)

        case .month:
            guard let newMonth = calendar.date(byAdding: .month, value: offset, to: monthAnchor) else { return nil }
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)!.start
            let newMonthStart = calendar.dateInterval(of: .month, for: newMonth)!.start
            guard newMonthStart <= thisMonthStart else { return nil }
            return .month(newMonth)
        }
    }

    private static func shortDate(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f.string(from: date)
    }
}

enum MetricAnchor {
    case day(Date)
    case week(Date)
    case month(Date)
}

// MARK: - 周 / 月窗口工具

enum MetricWindows {

    /// 返回 (start, end)，end 为不含的右边界。
    /// 本周 / 本月截止到今天（明天 0 点），其余完整区间。
    static func week(_ anchor: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let now = Date()
        let isCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start == weekStart
        let end = isCurrentWeek
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : weekEnd
        return (weekStart, end)
    }

    static func month(_ anchor: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: anchor)!
        let now = Date()
        let isCurrentMonth = calendar.dateInterval(of: .month, for: now)!.start == interval.start
        let end = isCurrentMonth
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : interval.end
        return (interval.start, end)
    }
}

// MARK: - 常用小尺寸图表气泡

struct MetricBubble: View {
    let content: AnyView

    init<C: View>(@ViewBuilder content: () -> C) {
        self.content = AnyView(content())
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - X 轴标签辅助

enum MetricXAxis {
    static func label(for date: Date, range: MetricRange) -> String {
        switch range {
        case .day, .week:
            let weekday = Calendar.current.component(.weekday, from: date)
            return ["日", "一", "二", "三", "四", "五", "六"][weekday - 1]
        case .month:
            return "\(Calendar.current.component(.day, from: date))"
        }
    }

    static func stride(for range: MetricRange) -> AxisMarkValues {
        switch range {
        case .day, .week: return .stride(by: .day, count: 1)
        case .month:      return .stride(by: .day, count: 5)
        }
    }
}

// MARK: - 小时 X 轴辅助

enum MetricHourAxis {
    static func ticks(upTo maxHour: Int) -> [Int] {
        let step = maxHour <= 6 ? 1 : (maxHour <= 12 ? 2 : 3)
        return Array(stride(from: 0, through: maxHour, by: step))
    }

    static func label(for hour: Int) -> String {
        String(format: "%02d", hour)
    }
}

// MARK: - 统一 Y 轴样式

@AxisContentBuilder
func metricYAxis(width: CGFloat = 30) -> some AxisContent {
    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
        AxisTick()
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            .foregroundStyle(Color.primary.opacity(0.08))
        AxisValueLabel {
            if let v = value.as(Double.self) {
                Text("\(Int(v))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: width, alignment: .trailing)
            }
        }
    }
}

// MARK: - 日视图小时折线图（通用）

struct HourlyLineChart<Item: Identifiable>: View {
    let data: [Item]
    let hour: (Item) -> Int
    let value: (Item) -> Double?
    let color: Color
    let valueFormatter: (Double) -> String
    let fallbackYRange: ClosedRange<Double>
    var yPaddingRatio: Double = 0.25
    var clampRange: ClosedRange<Double>? = nil
    @Binding var selection: Int?

    private var maxHour: Int { data.map(hour).max() ?? 23 }
    private var values: [Double] { data.compactMap(value) }
    private var count: Int { values.count }

    private var selectedItem: Item? {
        guard let selection else { return nil }
        return data.first { hour($0) == selection }
    }

    /// 首尾各留半格，避免贴边
    private var xDomain: ClosedRange<Double> {
        -0.6...(Double(maxHour) + 0.6)
    }

    /// 数据点 ≥ 4 用平滑曲线，否则用直线避免过冲
    private var interpolation: InterpolationMethod {
        count >= 4 ? .catmullRom : .linear
    }

    private var yDomain: ClosedRange<Double> {
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

    var body: some View {
        Chart {
            ForEach(data) { item in
                if let v = value(item) {
                    AreaMark(
                        x: .value("小时", Double(hour(item))),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("值", v)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [color.opacity(0.26), color.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(interpolation)

                    LineMark(
                        x: .value("小时", Double(hour(item))),
                        y: .value("值", v)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(interpolation)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("小时", Double(hour(item))),
                        y: .value("值", v)
                    )
                    .foregroundStyle(color)
                    .symbolSize(22)
                }
            }

            if let item = selectedItem, let v = value(item) {
                RuleMark(x: .value("选中", Double(hour(item))))
                    .foregroundStyle(color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .zIndex(1)

                PointMark(
                    x: .value("小时", Double(hour(item))),
                    y: .value("值", v)
                )
                .foregroundStyle(color)
                .symbolSize(60)
                .zIndex(2)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: MetricHourAxis.ticks(upTo: maxHour).map(Double.init)) { mark in
                AxisValueLabel {
                    if let h = mark.as(Double.self) {
                        Text(MetricHourAxis.label(for: Int(h)))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis { metricYAxis(width: 30) }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard let raw = proxy.value(atX: gesture.location.x, as: Double.self) else { return }
                            let h = Int(raw.rounded())
                            guard (0...maxHour).contains(h) else { return }
                            if selection != h { selection = h }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.15)) { selection = nil }
                        }
                )
        }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                MetricBubble {
                    HStack(spacing: 5) {
                        Text("\(String(format: "%02d", hour(item))):00")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("·").foregroundStyle(.tertiary)
                        Text(value(item).map(valueFormatter) ?? "无数据")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.15), value: selectedItem?.id)
    }
}

// MARK: - 周 / 月趋势折线图（通用）

struct TrendLineChart<Item: Identifiable>: View {
    let data: [Item]
    let date: (Item) -> Date
    let value: (Item) -> Double?
    let color: Color
    let range: MetricRange
    let valueFormatter: (Double) -> String
    let fallbackYRange: ClosedRange<Double>
    var yPaddingRatio: Double = 0.25
    var clampRange: ClosedRange<Double>? = nil
    var reference: Reference = .average
    @Binding var selection: Date?

    enum Reference {
        case average
        case fixed(Double)
        case none
    }

    private var validItems: [Item] { data.filter { value($0) != nil } }
    private var validValues: [Double] { data.compactMap(value) }
    private var count: Int { validValues.count }

    private var selectedItem: Item? {
        guard let selection else { return nil }
        let nearest = validItems.min {
            abs(date($0).timeIntervalSince(selection)) < abs(date($1).timeIntervalSince(selection))
        }
        guard let nearest,
              abs(date(nearest).timeIntervalSince(selection)) <= 12 * 3600 else { return nil }
        return nearest
    }

    private var interpolation: InterpolationMethod {
        count >= 4 ? .catmullRom : .linear
    }

    /// 首尾各留半天，避免贴边
    private var xDomain: ClosedRange<Date> {
        guard let first = validItems.first.map(date),
              let last = validItems.last.map(date),
              first < last else {
            let now = Date()
            return now.addingTimeInterval(-86400)...now.addingTimeInterval(86400)
        }
        let pad: TimeInterval = 12 * 3600
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    private var referenceValue: Double? {
        switch reference {
        case .average:
            guard !validValues.isEmpty else { return nil }
            return validValues.reduce(0, +) / Double(validValues.count)
        case .fixed(let v):
            return v
        case .none:
            return nil
        }
    }

    private var yDomain: ClosedRange<Double> {
        guard let lo = validValues.min(),
              let hi = validValues.max(),
              lo < hi else {
            return fallbackYRange
        }
        let pad = max((hi - lo) * yPaddingRatio, 2)
        var lower = lo - pad
        var upper = hi + pad
        if case .fixed(let ref) = reference {
            lower = min(lower, ref - pad)
        }
        if let clamp = clampRange {
            lower = max(clamp.lowerBound, lower)
            upper = min(clamp.upperBound, upper)
        }
        return lower...upper
    }

    var body: some View {
        Chart {
            if let ref = referenceValue {
                RuleMark(y: .value("参考", ref))
                    .foregroundStyle(color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .zIndex(0)
            }

            if count == 1, let item = validItems.first, let v = value(item) {
                PointMark(
                    x: .value("日期", date(item)),
                    y: .value("值", v)
                )
                .foregroundStyle(color)
                .symbolSize(80)
            } else {
                ForEach(data) { item in
                    if let v = value(item) {
                        AreaMark(
                            x: .value("日期", date(item)),
                            yStart: .value("底", yDomain.lowerBound),
                            yEnd: .value("值", v)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [color.opacity(0.26), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(interpolation)
                        .zIndex(1)

                        LineMark(
                            x: .value("日期", date(item)),
                            y: .value("值", v)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(interpolation)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .zIndex(2)
                    }
                }
            }

            if let item = selectedItem, let v = value(item) {
                RuleMark(x: .value("选中", date(item)))
                    .foregroundStyle(color.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .zIndex(3)

                PointMark(
                    x: .value("日期", date(item)),
                    y: .value("值", v)
                )
                .foregroundStyle(color)
                .symbolSize(80)
                .zIndex(4)
            }
        }
        .chartXSelection(value: $selection)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: MetricXAxis.stride(for: range)) { mark in
                AxisValueLabel {
                    if let d = mark.as(Date.self) {
                        Text(MetricXAxis.label(for: d, range: range))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis { metricYAxis(width: 30) }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                MetricBubble {
                    HStack(spacing: 5) {
                        Text(shortDate(date(item)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(value(item).map(valueFormatter) ?? "无数据")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.18), value: selectedItem?.id)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}
