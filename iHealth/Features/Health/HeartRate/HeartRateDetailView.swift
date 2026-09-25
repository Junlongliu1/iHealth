//
//  HeartRateDetailView.swift
//  iHealth
//
//  心率详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

enum HeartRateRange: String, CaseIterable, Identifiable {
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

struct HeartRateDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: HeartRateRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()

    @State private var hourly: [HourlyHeartRate] = []
    @State private var daily: [DailyHeartRate] = []
    @State private var isLoading = false
    @State private var slideDirection: Edge = .trailing

    @State private var selectedTrendDay: Date?
    @State private var selectedHour: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker
                rangeNavigator

                if isLoading && hourly.isEmpty && daily.isEmpty {
                    loadingState
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
        .navigationTitle("心率")
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
        case .day:
            return "d-\(calendar.startOfDay(for: currentDay).timeIntervalSince1970)"
        case .week:
            return "w-\(calendar.dateInterval(of: .weekOfYear, for: weekAnchor)!.start.timeIntervalSince1970)"
        case .month:
            return "m-\(calendar.dateInterval(of: .month, for: monthAnchor)!.start.timeIntervalSince1970)"
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $selectedRange) {
            ForEach(HeartRateRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

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

    @ViewBuilder
    private var content: some View {
        switch selectedRange {
        case .day:   dayContent
        case .week:  trendContent(for: .week)
        case .month: trendContent(for: .month)
        }
    }

    // MARK: - 日视图

    private var dayContent: some View {
        let values = hourly.compactMap { $0.bpm }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let peak = hourly.compactMap { item -> HourlyHeartRate? in
            item.bpm != nil ? item : nil
        }.max { ($0.bpm ?? 0) < ($1.bpm ?? 0) }
        let hasAny = !values.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("平均心率")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hasAny ? "\(Int(avg.rounded()))" : "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("次/分")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每小时心率")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if hasAny {
                    HeartRateHourlyChart(data: hourly, selection: $selectedHour)
                        .frame(height: 140)
                } else {
                    emptyChart.frame(height: 140)
                }
            }

            if let peak, let bpm = peak.bpm {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)

                    Text("心率最高时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("\(String(format: "%02d", peak.hour)):00 · \(Int(bpm.rounded())) 次/分")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 周 / 月视图

    private func trendContent(for range: HeartRateRange) -> some View {
        let avg = averageDaily(daily)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("日均心率")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(avg.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("次/分")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日平均心率")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某天")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                HeartRateTrendChart(
                    data: daily,
                    range: range,
                    selection: $selectedTrendDay
                )
                .frame(height: 140)
            }

            HeartRateStatsGrid(daily: daily)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var emptyChart: some View {
        VStack {
            Spacer()
            Text("暂无数据")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingState: some View {
        VStack { ProgressView().padding(.top, 80) }
            .frame(maxWidth: .infinity)
    }

    // MARK: - 切换

    private func shift(by offset: Int) {
        let calendar = Calendar.current
        let now = Date()

        switch selectedRange {
        case .day:
            let today = calendar.startOfDay(for: now)
            guard let newDay = calendar.date(byAdding: .day, value: offset, to: currentDay),
                  newDay <= today else { return }
            slideDirection = offset > 0 ? .trailing : .leading
            selectedHour = nil
            Task {
                let fetched = await healthManager.fetchHourlyHeartRate(for: newDay)
                withAnimation(.smooth(duration: 0.32)) {
                    currentDay = newDay
                    hourly = fetched
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
                    daily = fetched
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
                    daily = fetched
                }
            }
        }
    }

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

    private func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }

        switch selectedRange {
        case .day:
            hourly = await healthManager.fetchHourlyHeartRate(for: currentDay)
        case .week:
            daily = await fetchWeek(weekAnchor)
        case .month:
            daily = await fetchMonth(monthAnchor)
        }
    }

    private func fetchWeek(_ anchor: Date) async -> [DailyHeartRate] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let now = Date()
        let isCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start == weekStart
        let end = isCurrentWeek
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : weekEnd
        return await healthManager.fetchDailyHeartRate(from: weekStart, to: end)
    }

    private func fetchMonth(_ anchor: Date) async -> [DailyHeartRate] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: anchor)!
        let monthStart = interval.start
        let now = Date()
        let isCurrentMonth = calendar.dateInterval(of: .month, for: now)!.start == monthStart
        let end = isCurrentMonth
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : interval.end
        return await healthManager.fetchDailyHeartRate(from: monthStart, to: end)
    }

    private func averageDaily(_ data: [DailyHeartRate]) -> Double? {
        let values = data.compactMap { $0.bpm }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - 每小时心率曲线

private struct HeartRateHourlyChart: View {
    let data: [HourlyHeartRate]
    @Binding var selection: Int?

    private var selectedItem: HourlyHeartRate? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                if let bpm = item.bpm {
                    AreaMark(
                        x: .value("小时", item.hour),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("心率", bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red.opacity(0.28), Color.red.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("小时", item.hour),
                        y: .value("心率", bpm)
                    )
                    .foregroundStyle(Color.red)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xTicks) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
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
                        Text("\(Int(v))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let raw = proxy.value(atX: value.location.x, as: Double.self) else { return }
                            let hour = Int(raw.rounded())
                            let maxHour = data.last?.hour ?? 23
                            guard hour >= 0, hour <= maxHour else { return }
                            if selection != hour { selection = hour }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.15)) { selection = nil }
                        }
                )
        }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                bubble(item)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.15), value: selectedItem?.id)
    }

    private func bubble(_ item: HourlyHeartRate) -> some View {
        HStack(spacing: 5) {
            Text("\(String(format: "%02d", item.hour)):00")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.bpm.map { "\(Int($0.rounded())) 次/分" } ?? "无数据")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var xDomain: ClosedRange<Int> {
        let maxHour = data.last?.hour ?? 23
        return 0...max(1, maxHour)
    }

    private var xTicks: [Int] {
        guard let maxHour = data.last?.hour else { return [] }
        let step = maxHour <= 6 ? 1 : (maxHour <= 12 ? 2 : 3)
        return Array(stride(from: 0, through: maxHour, by: step))
    }

    private var yDomain: ClosedRange<Double> {
        let values = data.compactMap { $0.bpm }
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            return 50...100
        }
        let pad = max((hi - lo) * 0.2, 3)
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - 每日心率趋势图（折线 + 面积，支持点击选中）

private struct HeartRateTrendChart: View {
    let data: [DailyHeartRate]
    let range: HeartRateRange
    @Binding var selection: Date?

    private var validValues: [Double] { data.compactMap { $0.bpm } }

    private var selectedItem: DailyHeartRate? {
        guard let selection else { return nil }
        let nearest = data.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
        guard let nearest else { return nil }
        if abs(nearest.date.timeIntervalSince(selection)) > 12 * 3600 { return nil }
        return nearest
    }

    /// 参考线：整段区间的平均心率
    private var referenceValue: Double? {
        guard !validValues.isEmpty else { return nil }
        return validValues.reduce(0, +) / Double(validValues.count)
    }

    var body: some View {
        Chart {
            // 平均参考线（虚线）
            if let ref = referenceValue {
                RuleMark(y: .value("平均", ref))
                    .foregroundStyle(Color.red.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .zIndex(0)
            }

            ForEach(data) { item in
                if let bpm = item.bpm {
                    AreaMark(
                        x: .value("日期", item.date, unit: .day),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("心率", bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red.opacity(0.28), Color.red.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    .zIndex(1)

                    LineMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("心率", bpm)
                    )
                    .foregroundStyle(Color.red)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .zIndex(2)
                }
            }

            // 选中点
            if let item = selectedItem, let bpm = item.bpm {
                PointMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("心率", bpm)
                )
                .foregroundStyle(Color.red)
                .symbolSize(60)
                .zIndex(3)
            }
        }
        .chartXSelection(value: $selection)
        .chartYScale(domain: yDomain)
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
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
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

    private func bubble(_ item: DailyHeartRate) -> some View {
        HStack(spacing: 5) {
            Text(shortDate(item.date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.bpm.map { "\(Int($0.rounded())) 次/分" } ?? "无数据")
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

    /// 以数据范围为基准的 Y 轴，不再从 0 起，突出波动
    private var yDomain: ClosedRange<Double> {
        guard let lo = validValues.min(),
              let hi = validValues.max(),
              lo < hi else {
            return 50...100
        }
        let pad = max((hi - lo) * 0.25, 3)
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - 统计网格

private struct HeartRateStatsGrid: View {
    let daily: [DailyHeartRate]

    private var valid: [Double] { daily.compactMap { $0.bpm } }

    private var avg: Double? {
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private var highest: Double? { valid.max() }
    private var lowest:  Double? { valid.min() }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            item(title: "平均", value: avg.map { "\(Int($0.rounded())) 次/分" } ?? "--")
            item(title: "最高", value: highest.map { "\(Int($0.rounded())) 次/分" } ?? "--")
            item(title: "最低", value: lowest.map { "\(Int($0.rounded())) 次/分" } ?? "--")
            item(title: "有数据天数", value: "\(valid.count) 天")
        }
    }

    private func item(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
