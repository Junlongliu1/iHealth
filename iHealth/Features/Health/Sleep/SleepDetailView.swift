//
//  SleepDetailView.swift
//  iHealth
//
//  睡眠详情页。
//  支持「日 / 周 / 月」三种时间范围。
//  与苹果健康一致：按「睡眠日（18:00–18:00）」归属。
//  周 / 月切换带方向感的 push 过渡。
//

import SwiftUI
import HealthKit
import Charts

// MARK: - 时间范围

enum SleepRange: String, CaseIterable, Identifiable {
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

// MARK: - 每日总睡眠

struct DailySleepTotal: Identifiable {
    let date: Date
    let total: TimeInterval
    var id: Date { date }
}

// MARK: - 睡眠详情页

struct SleepDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: SleepRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()

    @State private var samples: [HKCategorySample] = []
    @State private var isLoading = false
    @State private var slideDirection: Edge = .trailing

    @State private var dayCache: [Date: [HKCategorySample]] = [:]
    @State private var weekCache: [Date: [HKCategorySample]] = [:]
    @State private var monthCache: [Date: [HKCategorySample]] = [:]

    @State private var selectedTrendDay: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker
                rangeNavigator

                if isLoading && samples.isEmpty {
                    loadingState
                } else if samples.isEmpty {
                    emptyState
                } else {
                    content
                        .id(contentId)
                        .transition(.push(from: slideDirection))
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("睡眠")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCurrent() }
        .onChange(of: selectedRange) { _, _ in
            selectedTrendDay = nil
            Task { await loadCurrent() }
        }
    }

    // MARK: - 内容标识（触发 push 过渡的关键）

    private var contentId: String {
        let calendar = Calendar.current
        switch selectedRange {
        case .day:
            return "d-\(calendar.startOfDay(for: currentDay).timeIntervalSince1970)"
        case .week:
            return "w-\(calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start.timeIntervalSince1970)"
        case .month:
            return "m-\(calendar.dateInterval(of: .month, for: monthAnchor)!.start.timeIntervalSince1970)"
        }
    }

    // MARK: - 顶部范围切换

    private var rangePicker: some View {
        Picker("范围", selection: $selectedRange) {
            ForEach(SleepRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - 导航条

    private var rangeNavigator: some View {
        HStack(spacing: 12) {
            Button { shift(by: -1) } label: {
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

            Button { shift(by: 1) } label: {
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

    // MARK: - 内容分支

    @ViewBuilder
    private var content: some View {
        switch selectedRange {
        case .day:
            dayContent
        case .week:
            trendContent(for: .week)
        case .month:
            trendContent(for: .month)
        }
    }

    // MARK: - 日视图

    private var dayContent: some View {
        SleepSummaryView(samples: samples)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    // MARK: - 周 / 月视图

    private func trendContent(for range: SleepRange) -> some View {
        let daily = dailyTotals(from: samples, range: range)
        let summary = SleepSummary(samples: samples)
        let avg = averageTotal(daily)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("睡眠时间")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(avg.hourMinuteText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日睡眠")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某天")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                SleepTrendChart(
                    data: daily,
                    range: range,
                    selection: $selectedTrendDay
                )
                .frame(height: 120)
            }

            SleepStageGrid(summary: summary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 切换逻辑（先加载，再原子更新 + push 过渡）

    private func shift(by offset: Int) {
        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .day:
            let today = calendar.startOfDay(for: now)
            guard let newDay = calendar.date(byAdding: .day, value: offset, to: currentDay),
                  newDay <= today else { return }

            slideDirection = offset > 0 ? .trailing : .leading
            selectedTrendDay = nil

            Task {
                let fetched = await fetchDay(newDay)
                withAnimation(.smooth(duration: 0.32)) {
                    currentDay = newDay
                    samples = fetched
                }
            }

        case .week:
            guard let newWeek = calendar.date(byAdding: .weekOfYear, value: offset, to: weekAnchor) else { return }
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let newWeekStart = calendar.dateInterval(of: .weekOfYear, for: newWeek)!.start
            guard newWeekStart <= thisWeekStart else { return }

            slideDirection = offset > 0 ? .trailing : .leading
            selectedTrendDay = nil

            Task {
                let fetched = await fetchWeek(newWeek)
                withAnimation(.smooth(duration: 0.32)) {
                    weekAnchor = newWeek
                    samples = fetched
                }
            }

        case .month:
            guard let newMonth = calendar.date(byAdding: .month, value: offset, to: monthAnchor) else { return }
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)!.start
            let newMonthStart = calendar.dateInterval(of: .month, for: newMonth)!.start
            guard newMonthStart <= thisMonthStart else { return }

            slideDirection = offset > 0 ? .trailing : .leading
            selectedTrendDay = nil

            Task {
                let fetched = await fetchMonth(newMonth)
                withAnimation(.smooth(duration: 0.32)) {
                    monthAnchor = newMonth
                    samples = fetched
                }
            }
        }
    }

    // MARK: - 前进 / 后退能力

    private var canGoForward: Bool {
        let calendar = Calendar.current
        let now = Date()
        switch selectedRange {
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

    // MARK: - 标题

    private var navTitle: String {
        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .day:
            let today = calendar.startOfDay(for: now)
            let day = calendar.startOfDay(for: currentDay)
            if day == today { return "今天" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEE"
            return f.string(from: day)

        case .week:
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
            let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start
            if anchorWeekStart == thisWeekStart { return "本周" }
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: anchorWeekStart)!
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日"
            return "\(f.string(from: anchorWeekStart))–\(f.string(from: weekEnd))"

        case .month:
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)!.start
            let anchorMonthStart = calendar.dateInterval(of: .month, for: monthAnchor)!.start
            if anchorMonthStart == thisMonthStart { return "本月" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "yyyy年M月"
            return f.string(from: anchorMonthStart)
        }
    }

    // MARK: - 状态视图

    private var loadingState: some View {
        VStack { ProgressView().padding(.top, 80) }
            .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "暂无睡眠数据",
            systemImage: "bed.double",
            description: Text("请确保已佩戴 Apple Watch 入睡")
        )
        .padding(.top, 40)
    }

    // MARK: - 首次加载 / 切换范围

    private func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }

        switch selectedRange {
        case .day:
            samples = await fetchDay(currentDay)
        case .week:
            samples = await fetchWeek(weekAnchor)
        case .month:
            samples = await fetchMonth(monthAnchor)
        }
    }

    // MARK: - 纯加载（带缓存）

    private func fetchDay(_ day: Date) async -> [HKCategorySample] {
        let calendar = Calendar.current
        let key = calendar.startOfDay(for: day)
        if let cached = dayCache[key] { return cached }

        let (sleepDayStart, sleepDayEnd) = SleepDay.window(for: day)
        let queryStart = calendar.date(byAdding: .day, value: -1, to: sleepDayStart)!
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: sleepDayEnd)!

        let raw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)
        let fetched = raw.filter {
            $0.startDate >= sleepDayStart && $0.startDate < sleepDayEnd
        }
        dayCache[key] = fetched
        return fetched
    }

    private func fetchWeek(_ anchor: Date) async -> [HKCategorySample] {
        let calendar = Calendar.current
        let key = calendar.startOfDay(for: anchor)
        if let cached = weekCache[key] { return cached }

        let (rangeStart, rangeEnd) = weekWindow(for: anchor)
        let queryStart = calendar.date(byAdding: .day, value: -1, to: rangeStart)!
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: rangeEnd)!

        let raw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)
        let fetched = raw.filter {
            $0.startDate >= rangeStart && $0.startDate < rangeEnd
        }
        weekCache[key] = fetched
        return fetched
    }

    private func fetchMonth(_ anchor: Date) async -> [HKCategorySample] {
        let calendar = Calendar.current
        let key = calendar.startOfDay(for: anchor)
        if let cached = monthCache[key] { return cached }

        let (rangeStart, rangeEnd) = monthWindow(for: anchor)
        let queryStart = calendar.date(byAdding: .day, value: -1, to: rangeStart)!
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: rangeEnd)!

        let raw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)
        let fetched = raw.filter {
            $0.startDate >= rangeStart && $0.startDate < rangeEnd
        }
        monthCache[key] = fetched
        return fetched
    }

    // MARK: - 时间窗口

    private func weekWindow(for anchor: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let (s, _) = SleepDay.window(for: weekStart)
        let (_, e) = SleepDay.window(for: weekEnd)
        return (s, e)
    }

    private func monthWindow(for anchor: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: anchor)!
        let monthStart = interval.start
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let (s, _) = SleepDay.window(for: monthStart)
        let (_, e) = SleepDay.window(for: monthEnd)
        return (s, e)
    }

    // MARK: - 聚合

    private func dailyTotals(from samples: [HKCategorySample], range: SleepRange) -> [DailySleepTotal] {
        let calendar = Calendar.current

        var byDay: [Date: TimeInterval] = [:]
        for s in samples {
            guard let stage = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            guard stage != .awake && stage != .inBed else { continue }
            let day = SleepDay.day(for: s.startDate)
            byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }

        let days: [Date]
        switch range {
        case .day:
            days = [calendar.startOfDay(for: currentDay)]

        case .week:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start
            days = (0..<7).map {
                calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: weekStart)!)
            }

        case .month:
            let interval = calendar.dateInterval(of: .month, for: monthAnchor)!
            let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
            days = (0..<dayCount).map {
                calendar.startOfDay(for: calendar.date(byAdding: .day, value: $0, to: interval.start)!)
            }
        }

        return days.map { day in
            DailySleepTotal(date: day, total: byDay[day] ?? 0)
        }
    }

    private func averageTotal(_ data: [DailySleepTotal]) -> TimeInterval {
        let valid = data.filter { $0.total > 0 }
        guard !valid.isEmpty else { return 0 }
        let sum = valid.reduce(0) { $0 + $1.total }
        return sum / Double(valid.count)
    }
}

// MARK: - 趋势柱状图（周 / 月共用，支持点击选中）

private struct SleepTrendChart: View {
    let data: [DailySleepTotal]
    let range: SleepRange
    @Binding var selection: Date?

    private var selectedItem: DailySleepTotal? {
        guard let selection else { return nil }
        let nearest = data.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
        guard let nearest else { return nil }
        if abs(nearest.date.timeIntervalSince(selection)) > 12 * 3600 { return nil }
        return nearest
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("小时", item.total / 3600)
                )
                .foregroundStyle(barColor(item))
                .cornerRadius(4)
            }
        }
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: xStride) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xLabel(date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours))h")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                bubble(item)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.18), value: selectedItem?.id)
    }

    private func barColor(_ item: DailySleepTotal) -> Color {
        if let selected = selectedItem, selected.id == item.id {
            return .indigo
        }
        return Color.indigo.opacity(0.45)
    }

    private func bubble(_ item: DailySleepTotal) -> some View {
        HStack(spacing: 5) {
            Text(shortDate(item.date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.total > 0 ? item.total.hourMinuteText : "无数据")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }

    private var xStride: AxisMarkValues {
        switch range {
        case .day, .week: return .stride(by: .day, count: 1)
        case .month:      return .stride(by: .day, count: 5)
        }
    }

    private func xLabel(_ date: Date) -> String {
        switch range {
        case .day, .week:
            let weekday = Calendar.current.component(.weekday, from: date)
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            return names[weekday - 1]
        case .month:
            return "\(Calendar.current.component(.day, from: date))"
        }
    }
}
