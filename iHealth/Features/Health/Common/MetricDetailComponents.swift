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
