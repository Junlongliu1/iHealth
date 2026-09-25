//
//  MetricDetailScreen.swift
//  iHealth
//
//  8 个「日 / 周 / 月」详情页共享的通用容器。
//  负责：所有 @State、body 骨架、shift(by:)、loadCurrent、contentId、动画。
//  具体内容通过 dayContent / trendContent 闭包注入。
//

import SwiftUI

struct MetricDetailScreen<
    Hourly: Identifiable,
    Daily: Identifiable,
    DayContent: View,
    TrendContent: View
>: View {

    // MARK: - 外部配置

    let title: String
    let fetchHourly: (Date) async -> [Hourly]
    let fetchDaily: (Date, Date) async -> [Daily]
    let dayContent: ([Hourly], Binding<Int?>) -> DayContent
    let trendContent: (MetricRange, [Daily], Binding<Date?>) -> TrendContent

    // MARK: - 内部状态

    @State private var selectedRange: MetricRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()
    @State private var hourly: [Hourly] = []
    @State private var daily: [Daily] = []
    @State private var isLoading = false
    @State private var slideDirection: Edge = .trailing
    @State private var selectedTrendDay: Date?
    @State private var selectedHour: Int?

    // MARK: - Init

    init(
        title: String,
        fetchHourly: @escaping (Date) async -> [Hourly],
        fetchDaily: @escaping (Date, Date) async -> [Daily],
        dayContent: @escaping ([Hourly], Binding<Int?>) -> DayContent,
        trendContent: @escaping (MetricRange, [Daily], Binding<Date?>) -> TrendContent
    ) {
        self.title = title
        self.fetchHourly = fetchHourly
        self.fetchDaily = fetchDaily
        self.dayContent = dayContent
        self.trendContent = trendContent
    }

    // MARK: - Body

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

                if isLoading && hourly.isEmpty && daily.isEmpty {
                    ProgressView()
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity)
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
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCurrent() }
        .onChange(of: selectedRange) { _, _ in
            selectedTrendDay = nil
            selectedHour = nil
            Task { await loadCurrent() }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch selectedRange {
        case .day:
            dayContent(hourly, $selectedHour)
        case .week:
            trendContent(.week, daily, $selectedTrendDay)
        case .month:
            trendContent(.month, daily, $selectedTrendDay)
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

    // MARK: - 切换

    private func shift(by offset: Int) {
        guard let anchor = MetricNavigation.shift(
            range: selectedRange, by: offset,
            currentDay: currentDay, weekAnchor: weekAnchor, monthAnchor: monthAnchor
        ) else { return }

        slideDirection = offset > 0 ? .trailing : .leading
        selectedHour = nil
        selectedTrendDay = nil

        switch anchor {
        case .day(let newDay):
            Task {
                let fetched = await fetchHourly(newDay)
                withAnimation(.smooth(duration: 0.32)) {
                    currentDay = newDay
                    hourly = fetched
                }
            }
        case .week(let newWeek):
            Task {
                let (s, e) = MetricWindows.week(newWeek)
                let fetched = await fetchDaily(s, e)
                withAnimation(.smooth(duration: 0.32)) {
                    weekAnchor = newWeek
                    daily = fetched
                }
            }
        case .month(let newMonth):
            Task {
                let (s, e) = MetricWindows.month(newMonth)
                let fetched = await fetchDaily(s, e)
                withAnimation(.smooth(duration: 0.32)) {
                    monthAnchor = newMonth
                    daily = fetched
                }
            }
        }
    }

    // MARK: - 加载

    private func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }
        switch selectedRange {
        case .day:
            hourly = await fetchHourly(currentDay)
        case .week:
            let (s, e) = MetricWindows.week(weekAnchor)
            daily = await fetchDaily(s, e)
        case .month:
            let (s, e) = MetricWindows.month(monthAnchor)
            daily = await fetchDaily(s, e)
        }
    }
}
