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
                    HeartRateVariabilityHourlyChart(data: hourly, selection: $selectedHour)
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
                HeartRateVariabilityTrendChart(data: daily, range: range, selection: $selectedTrendDay)
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

// MARK: - 每小时 HRV 曲线

private struct HeartRateVariabilityHourlyChart: View {
    let data: [HourlyHeartRateVariability]
    @Binding var selection: Int?

    private var selectedItem: HourlyHeartRateVariability? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                if let ms = item.milliseconds {
                    AreaMark(
                        x: .value("小时", item.hour),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("HRV", ms)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.red.opacity(0.28), Color.red.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(x: .value("小时", item.hour), y: .value("HRV", ms))
                        .foregroundStyle(Color.red)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                    PointMark(x: .value("小时", item.hour), y: .value("HRV", ms))
                        .foregroundStyle(Color.red).symbolSize(36)
                }
            }
        }
        .chartXScale(domain: 0...max(1, data.last?.hour ?? 23))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: MetricHourAxis.ticks(upTo: data.last?.hour ?? 23)) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(MetricHourAxis.label(for: hour))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let raw = proxy.value(atX: value.location.x, as: Double.self) else { return }
                            let hour = Int(raw.rounded())
                            let maxHour = data.last?.hour ?? 23
                            guard (0...maxHour).contains(hour) else { return }
                            if selection != hour { selection = hour }
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
                        Text("\(String(format: "%02d", item.hour)):00")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary).monospacedDigit()
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.milliseconds.map { "\(Int($0.rounded())) 毫秒" } ?? "无数据")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.15), value: selectedItem?.id)
    }

    private var yDomain: ClosedRange<Double> {
        let values = data.compactMap { $0.milliseconds }
        guard let lo = values.min(), let hi = values.max(), lo < hi else { return 20...80 }
        let pad = max((hi - lo) * 0.3, 3)
        return max(0, lo - pad)...(hi + pad)
    }
}

// MARK: - 每日 HRV 趋势图

private struct HeartRateVariabilityTrendChart: View {
    let data: [DailyHeartRateVariability]
    let range: MetricRange
    @Binding var selection: Date?

    private var validValues: [Double] { data.compactMap { $0.milliseconds } }

    private var selectedItem: DailyHeartRateVariability? {
        guard let selection else { return nil }
        let nearest = data.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
        guard let nearest,
              abs(nearest.date.timeIntervalSince(selection)) <= 12 * 3600 else { return nil }
        return nearest
    }

    private var referenceValue: Double? {
        guard !validValues.isEmpty else { return nil }
        return validValues.reduce(0, +) / Double(validValues.count)
    }

    var body: some View {
        Chart {
            if let ref = referenceValue {
                RuleMark(y: .value("平均", ref))
                    .foregroundStyle(Color.red.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .zIndex(0)
            }

            ForEach(data) { item in
                if let ms = item.milliseconds {
                    AreaMark(
                        x: .value("日期", item.date, unit: .day),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("HRV", ms)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [Color.red.opacity(0.28), Color.red.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom).zIndex(1)

                    LineMark(x: .value("日期", item.date, unit: .day), y: .value("HRV", ms))
                        .foregroundStyle(Color.red)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round)).zIndex(2)
                }
            }

            if let item = selectedItem, let ms = item.milliseconds {
                PointMark(x: .value("日期", item.date, unit: .day), y: .value("HRV", ms))
                    .foregroundStyle(Color.red).symbolSize(60).zIndex(3)
            }
        }
        .chartXSelection(value: $selection)
        .chartYScale(domain: yDomain)
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
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.system(size: 9)).foregroundStyle(.tertiary)
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
                        Text(item.milliseconds.map { "\(Int($0.rounded())) 毫秒" } ?? "无数据")
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

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }

    private var yDomain: ClosedRange<Double> {
        guard let lo = validValues.min(), let hi = validValues.max(), lo < hi else { return 20...80 }
        let pad = max((hi - lo) * 0.25, 3)
        return max(0, lo - pad)...(hi + pad)
    }
}
