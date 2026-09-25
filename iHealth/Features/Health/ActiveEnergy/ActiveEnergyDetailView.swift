//
//  ActiveEnergyDetailView.swift
//  iHealth
//
//  活动消耗详情页。
//  支持「日 / 周 / 月」三种时间范围。
//  日视图按住柱状图查看该小时消耗量。
//  周 / 月切换带方向感的 push 过渡。
//

import SwiftUI
import Charts

struct ActiveEnergyDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: MetricRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()

    @State private var hourly: [HourlyActiveEnergy] = []
    @State private var daily: [DailyActiveEnergy] = []
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
        .navigationTitle("活动消耗")
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
        let total = hourly.reduce(0) { $0 + $1.kilocalories }
        let peak = hourly.max { $0.kilocalories < $1.kilocalories }
        let hasAny = hourly.contains { $0.kilocalories > 0 }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("活动消耗").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(total.rounded()))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("大卡").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每小时分布")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("点击查看某时段")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                if hasAny {
                    ActiveEnergyHourlyChart(data: hourly, selection: $selectedHour).frame(height: 140)
                } else {
                    emptyChart.frame(height: 140)
                }
            }

            if let peak, peak.kilocalories > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
                    Text("消耗最高时段").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(String(format: "%02d", peak.hour)):00 · \(Int(peak.kilocalories.rounded())) 大卡")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary).monospacedDigit()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.10)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func trendContent(for range: MetricRange) -> some View {
        let avg = averageDaily(daily)
        let total = daily.reduce(0) { $0 + $1.kilocalories }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("日均活动消耗").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(avg.rounded()))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("大卡").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日活动消耗")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("点击查看某天")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ActiveEnergyTrendChart(data: daily, range: range, selection: $selectedTrendDay)
                    .frame(height: 140)
            }

            ActiveEnergyStatsGrid(daily: daily, total: total)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
                let fetched = await healthManager.fetchHourlyActiveEnergy(for: newDay)
                withAnimation(.smooth(duration: 0.32)) {
                    currentDay = newDay; hourly = fetched
                }
            }
        case .week(let newWeek):
            Task {
                let (s, e) = MetricWindows.week(newWeek)
                let fetched = await healthManager.fetchDailyActiveEnergy(from: s, to: e)
                withAnimation(.smooth(duration: 0.32)) {
                    weekAnchor = newWeek; daily = fetched
                }
            }
        case .month(let newMonth):
            Task {
                let (s, e) = MetricWindows.month(newMonth)
                let fetched = await healthManager.fetchDailyActiveEnergy(from: s, to: e)
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
            hourly = await healthManager.fetchHourlyActiveEnergy(for: currentDay)
        case .week:
            let (s, e) = MetricWindows.week(weekAnchor)
            daily = await healthManager.fetchDailyActiveEnergy(from: s, to: e)
        case .month:
            let (s, e) = MetricWindows.month(monthAnchor)
            daily = await healthManager.fetchDailyActiveEnergy(from: s, to: e)
        }
    }

    private func averageDaily(_ data: [DailyActiveEnergy]) -> Double {
        guard !data.isEmpty else { return 0 }
        return data.reduce(0) { $0 + $1.kilocalories } / Double(data.count)
    }
}

// MARK: - 每小时柱状图

private struct ActiveEnergyHourlyChart: View {
    let data: [HourlyActiveEnergy]
    @Binding var selection: Int?

    private var selectedItem: HourlyActiveEnergy? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(x: .value("小时", item.hour), y: .value("大卡", item.kilocalories))
                    .foregroundStyle(barColor(item))
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: 0...max(1, data.last?.hour ?? 23))
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
                        Text(item.kilocalories > 0 ? "\(Int(item.kilocalories.rounded())) 大卡" : "无数据")
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

    private func barColor(_ item: HourlyActiveEnergy) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .red }
        return Color.red.opacity(0.5)
    }
}

// MARK: - 每日柱状图

private struct ActiveEnergyTrendChart: View {
    let data: [DailyActiveEnergy]
    let range: MetricRange
    @Binding var selection: Date?

    private var selectedItem: DailyActiveEnergy? {
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
                BarMark(x: .value("日期", item.date, unit: .day), y: .value("大卡", item.kilocalories))
                    .foregroundStyle(barColor(item))
                    .cornerRadius(3)
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
                        Text(item.kilocalories > 0 ? "\(Int(item.kilocalories.rounded())) 大卡" : "无数据")
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

    private func barColor(_ item: DailyActiveEnergy) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .red }
        return Color.red.opacity(0.5)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}

// MARK: - 统计网格

private struct ActiveEnergyStatsGrid: View {
    let daily: [DailyActiveEnergy]
    let total: Double

    private var avg: Double {
        guard !daily.isEmpty else { return 0 }
        return total / Double(daily.count)
    }
    private var best: DailyActiveEnergy? { daily.max { $0.kilocalories < $1.kilocalories } }
    private var lowest: DailyActiveEnergy? { daily.min { $0.kilocalories < $1.kilocalories } }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ], alignment: .leading, spacing: 8) {
            item(title: "总消耗",   value: "\(Int(total.rounded())) 大卡")
            item(title: "日均",     value: "\(Int(avg.rounded())) 大卡")
            item(title: "最高一天", value: best.map { "\(Int($0.kilocalories.rounded())) 大卡" } ?? "--")
            item(title: "最低一天", value: lowest.map { "\(Int($0.kilocalories.rounded())) 大卡" } ?? "--")
        }
    }

    private func item(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
