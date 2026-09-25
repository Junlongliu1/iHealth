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

// MARK: - 每日总睡眠

struct DailySleepTotal: Identifiable {
    let date: Date
    let total: TimeInterval
    var id: Date { date }
}

// MARK: - 睡眠详情页

struct SleepDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: MetricRange = .day
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
                MetricRangePicker(selection: $selectedRange)
                MetricRangeNavigator(
                    selection: $selectedRange,
                    currentDay: currentDay,
                    weekAnchor: weekAnchor,
                    monthAnchor: monthAnchor,
                    canGoForward: MetricNavigation.canGoForward(
                        range: selectedRange,
                        currentDay: currentDay,
                        weekAnchor: weekAnchor,
                        monthAnchor: monthAnchor
                    ),
                    onShift: shift(by:)
                )

                if isLoading && samples.isEmpty {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                } else if samples.isEmpty {
                    ContentUnavailableView(
                        "暂无睡眠数据",
                        systemImage: "bed.double",
                        description: Text("请确保已佩戴 Apple Watch 入睡")
                    )
                    .padding(.top, 40)
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

    @ViewBuilder
    private var content: some View {
        switch selectedRange {
        case .day:
            SleepSummaryView(samples: samples)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        case .week:
            trendContent(for: .week)
        case .month:
            trendContent(for: .month)
        }
    }

    private func trendContent(for range: MetricRange) -> some View {
        let daily = dailyTotals(from: samples, range: range)
        let summary = SleepSummary(samples: samples)
        let avg = averageTotal(daily)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("睡眠时间")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(avg.hourMinuteText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日睡眠")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("点击查看某天")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                SleepTrendChart(data: daily, range: range, selection: $selectedTrendDay)
                    .frame(height: 120)
            }

            SleepStageGrid(summary: summary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 切换

    private func shift(by offset: Int) {
        guard let anchor = MetricNavigation.shift(
            range: selectedRange, by: offset,
            currentDay: currentDay, weekAnchor: weekAnchor, monthAnchor: monthAnchor
        ) else { return }

        slideDirection = offset > 0 ? .trailing : .leading
        selectedTrendDay = nil

        switch anchor {
        case .day(let newDay):
            Task {
                let fetched = await fetchDay(newDay)
                withAnimation(.smooth(duration: 0.32)) {
                    currentDay = newDay; samples = fetched
                }
            }
        case .week(let newWeek):
            Task {
                let fetched = await fetchWeek(newWeek)
                withAnimation(.smooth(duration: 0.32)) {
                    weekAnchor = newWeek; samples = fetched
                }
            }
        case .month(let newMonth):
            Task {
                let fetched = await fetchMonth(newMonth)
                withAnimation(.smooth(duration: 0.32)) {
                    monthAnchor = newMonth; samples = fetched
                }
            }
        }
    }

    // MARK: - 加载

    private func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }
        switch selectedRange {
        case .day:   samples = await fetchDay(currentDay)
        case .week:  samples = await fetchWeek(weekAnchor)
        case .month: samples = await fetchMonth(monthAnchor)
        }
    }

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

        let (rangeStart, rangeEnd) = weekSleepWindow(for: anchor)
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

        let (rangeStart, rangeEnd) = monthSleepWindow(for: anchor)
        let queryStart = calendar.date(byAdding: .day, value: -1, to: rangeStart)!
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: rangeEnd)!

        let raw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)
        let fetched = raw.filter {
            $0.startDate >= rangeStart && $0.startDate < rangeEnd
        }
        monthCache[key] = fetched
        return fetched
    }

    // MARK: - 睡眠日窗口

    private func weekSleepWindow(for anchor: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let (s, _) = SleepDay.window(for: weekStart)
        let (_, e) = SleepDay.window(for: weekEnd)
        return (s, e)
    }

    private func monthSleepWindow(for anchor: Date) -> (Date, Date) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: anchor)!
        let monthStart = interval.start
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let (s, _) = SleepDay.window(for: monthStart)
        let (_, e) = SleepDay.window(for: monthEnd)
        return (s, e)
    }

    // MARK: - 聚合

    private func dailyTotals(from samples: [HKCategorySample], range: MetricRange) -> [DailySleepTotal] {
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

        return days.map { DailySleepTotal(date: $0, total: byDay[$0] ?? 0) }
    }

    private func averageTotal(_ data: [DailySleepTotal]) -> TimeInterval {
        let valid = data.filter { $0.total > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.total } / Double(valid.count)
    }
}

// MARK: - 趋势柱状图

private struct SleepTrendChart: View {
    let data: [DailySleepTotal]
    let range: MetricRange
    @Binding var selection: Date?

    private var selectedItem: DailySleepTotal? {
        guard let selection else { return nil }
        let nearest = data.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
        guard let nearest,
              abs(nearest.date.timeIntervalSince(selection)) <= 12 * 3600 else { return nil }
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
            AxisMarks(values: MetricXAxis.stride(for: range)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(MetricXAxis.label(for: date, range: range))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
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
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                MetricBubble {
                    HStack(spacing: 5) {
                        Text(shortDate(item.date))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.total > 0 ? item.total.hourMinuteText : "无数据")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.18), value: selectedItem?.id)
    }

    private func barColor(_ item: DailySleepTotal) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .indigo }
        return Color.indigo.opacity(0.45)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}
