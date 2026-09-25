//
//  HeartRateVariabilityDetailView.swift
//  iHealth
//
//  心率变异性（HRV / SDNN）详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

struct HeartRateVariabilityDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: MetricRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()

    @State private var hourly: [HourlyHeartRateVariability] = []
    @State private var daily: [DailyHeartRateVariability] = []
    @State private var isLoading = false
    @State private var slideDirection: Edge = .trailing

    @State private var selectedTrendDay: Date?
    @State private var selectedHour: Int?

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
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
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
        .navigationTitle("心率变异性")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCurrent() }
        .onChange(of: selectedRange) { _, _ in
            selectedTrendDay = nil
            selectedHour = nil
            Task { await loadCurrent() }
        }
    }

    private var contentId: String {
        let calendar = Calendar.current
        switch selectedRange {
        case .day:   return "d-\(calendar.startOfDay(for: currentDay).timeIntervalSince1970)"
        case .week:  return "w-\(calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start.timeIntervalSince1970)"
        case .month: return "m-\(calendar.dateInterval(of: .month, for: monthAnchor)!.start.timeIntervalSince1970)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedRange {
        case .day:   dayContent
        case .week:  trendContent(for: .week)
        case .month: trendContent(for: .month)
        }
    }

    private var dayContent: some View {
        let values = hourly.compactMap { $0.milliseconds }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let hasAny = !values.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("心率变异性").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hasAny ? "\(Int(avg.rounded()))" : "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("毫秒").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每小时 HRV")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("点击查看某时段")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                if hasAny {
                    HourlyLineChart(
                        data: hourly,
                        hour: { $0.hour },
                        value: { $0.milliseconds },
                        color: .red,
                        valueFormatter: { "\(Int($0.rounded())) 毫秒" },
                        fallbackYRange: 20...80,
                        yPaddingRatio: 0.3,
                        selection: $selectedHour
                    )
                    .frame(height: 140)
                } else {
                    emptyChart.frame(height: 140)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func trendContent(for range: MetricRange) -> some View {
        let avg = averageDaily(daily)
        let values = daily.compactMap { $0.milliseconds }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("日均 HRV").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(avg.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("毫秒").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日 HRV")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("点击查看某天")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                TrendLineChart(
                    data: daily,
                    date: { $0.date },
                    value: { $0.milliseconds },
                    color: .red,
                    range: range,
                    valueFormatter: { "\(Int($0.rounded())) 毫秒" },
                    fallbackYRange: 20...80,
                    yPaddingRatio: 0.25,
                    selection: $selectedTrendDay
                )
                .frame(height: 140)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 8) {
                statItem(title: "平均",     value: avg.map { "\(Int($0.rounded())) 毫秒" } ?? "--")
                statItem(title: "最高",     value: values.max().map { "\(Int($0.rounded())) 毫秒" } ?? "--")
                statItem(title: "最低",     value: values.min().map { "\(Int($0.rounded())) 毫秒" } ?? "--")
                statItem(title: "有数据天数", value: "\(values.count) 天")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func statItem(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var emptyChart: some View {
        VStack {
            Spacer()
            Text("暂无数据").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

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
                let fetched = await healthManager.fetchHourlyHeartRateVariability(for: newDay)
                withAnimation(.smooth(duration: 0.32)) {
                    currentDay = newDay; hourly = fetched
                }
            }
        case .week(let newWeek):
            Task {
                let (s, e) = MetricWindows.week(newWeek)
                let fetched = await healthManager.fetchDailyHeartRateVariability(from: s, to: e)
                withAnimation(.smooth(duration: 0.32)) {
                    weekAnchor = newWeek; daily = fetched
                }
            }
        case .month(let newMonth):
            Task {
                let (s, e) = MetricWindows.month(newMonth)
                let fetched = await healthManager.fetchDailyHeartRateVariability(from: s, to: e)
                withAnimation(.smooth(duration: 0.32)) {
                    monthAnchor = newMonth; daily = fetched
                }
            }
        }
    }

    private func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }
        switch selectedRange {
        case .day:
            hourly = await healthManager.fetchHourlyHeartRateVariability(for: currentDay)
        case .week:
            let (s, e) = MetricWindows.week(weekAnchor)
            daily = await healthManager.fetchDailyHeartRateVariability(from: s, to: e)
        case .month:
            let (s, e) = MetricWindows.month(monthAnchor)
            daily = await healthManager.fetchDailyHeartRateVariability(from: s, to: e)
        }
    }

    private func averageDaily(_ data: [DailyHeartRateVariability]) -> Double? {
        let values = data.compactMap { $0.milliseconds }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
