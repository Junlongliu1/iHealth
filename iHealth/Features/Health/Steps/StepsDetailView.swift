//
//  StepsDetailView.swift
//  iHealth
//
//  步数详情页。
//  支持「日 / 周 / 月」三种时间范围。
//  日视图点击柱状图查看该小时步数。
//  周 / 月切换带方向感的 push 过渡。
//

import SwiftUI
import Charts

// MARK: - 时间范围

enum StepsRange: String, CaseIterable, Identifiable {
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

// MARK: - 步数详情页

struct StepsDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: StepsRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()

    @State private var hourly: [HourlySteps] = []
    @State private var daily: [DailySteps] = []
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
        .navigationTitle("步数")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCurrent() }
        .onChange(of: selectedRange) { _, _ in
            selectedTrendDay = nil
            selectedHour = nil
            Task { await loadCurrent() }
        }
    }

    // MARK: - 内容标识（触发 push 过渡）

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
            ForEach(StepsRange.allCases) { range in
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
        let total = hourly.reduce(0) { $0 + $1.steps }
        let peak = hourly.max { $0.steps < $1.steps }
        let hasAnySteps = hourly.contains { $0.steps > 0 }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("步数")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(total.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("步")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每小时分布")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if hasAnySteps {
                    StepsHourlyChart(
                        data: hourly,
                        selection: $selectedHour
                    )
                    .frame(height: 140)
                } else {
                    emptyChart
                        .frame(height: 140)
                }
            }

            if let peak, peak.steps > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)

                    Text("最活跃时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("\(String(format: "%02d", peak.hour)):00 · \(Int(peak.steps)) 步")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.08))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 周 / 月视图

    private func trendContent(for range: StepsRange) -> some View {
        let avg = averageDaily(daily)
        let total = daily.reduce(0) { $0 + $1.steps }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("日均步数")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(avg.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("步")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日步数")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某天")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                StepsTrendChart(
                    data: daily,
                    range: range,
                    selection: $selectedTrendDay
                )
                .frame(height: 140)
            }

            StepsStatsGrid(daily: daily, total: total)
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

    // MARK: - 状态视图

    private var loadingState: some View {
        VStack { ProgressView().padding(.top, 80) }
            .frame(maxWidth: .infinity)
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
            selectedHour = nil

            Task {
                let fetched = await healthManager.fetchHourlySteps(for: newDay)
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

    // MARK: - 前进能力

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

    // MARK: - 首次加载 / 切换范围

    private func loadCurrent() async {
        isLoading = true
        defer { isLoading = false }

        switch selectedRange {
        case .day:
            hourly = await healthManager.fetchHourlySteps(for: currentDay)
        case .week:
            daily = await fetchWeek(weekAnchor)
        case .month:
            daily = await fetchMonth(monthAnchor)
        }
    }

    // MARK: - 周 / 月窗口（本周 / 本月截止到今天）

    private func fetchWeek(_ anchor: Date) async -> [DailySteps] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let now = Date()
        let isCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start == weekStart
        let end = isCurrentWeek
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : weekEnd

        return await healthManager.fetchDailySteps(from: weekStart, to: end)
    }

    private func fetchMonth(_ anchor: Date) async -> [DailySteps] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: anchor)!
        let monthStart = interval.start

        let now = Date()
        let isCurrentMonth = calendar.dateInterval(of: .month, for: now)!.start == monthStart
        let end = isCurrentMonth
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : interval.end

        return await healthManager.fetchDailySteps(from: monthStart, to: end)
    }

    // MARK: - 聚合

    private func averageDaily(_ data: [DailySteps]) -> Double {
        guard !data.isEmpty else { return 0 }
        return data.reduce(0) { $0 + $1.steps } / Double(data.count)
    }
}

// MARK: - 每小时分布柱状图（按住显示气泡，松手消失）

private struct StepsHourlyChart: View {
    let data: [HourlySteps]
    @Binding var selection: Int?

    private var selectedItem: HourlySteps? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("小时", item.hour),
                    y: .value("步数", item.steps)
                )
                .foregroundStyle(barColor(item))
                .cornerRadius(2)
            }
        }
        .chartXScale(domain: xDomain)
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
                            if selection != hour {
                                selection = hour
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.15)) {
                                selection = nil
                            }
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

    private func barColor(_ item: HourlySteps) -> Color {
        if let selected = selectedItem, selected.id == item.id {
            return .green
        }
        return Color.green.opacity(0.5)
    }

    private func bubble(_ item: HourlySteps) -> some View {
        HStack(spacing: 5) {
            Text("\(String(format: "%02d", item.hour)):00")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.steps > 0 ? "\(Int(item.steps)) 步" : "无数据")
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
}

// MARK: - 每日趋势柱状图（周 / 月共用，支持点击选中）

private struct StepsTrendChart: View {
    let data: [DailySteps]
    let range: StepsRange
    @Binding var selection: Date?

    private var selectedItem: DailySteps? {
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
                    y: .value("步数", item.steps)
                )
                .foregroundStyle(barColor(item))
                .cornerRadius(3)
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

    private func barColor(_ item: DailySteps) -> Color {
        if let selected = selectedItem, selected.id == item.id {
            return .green
        }
        return Color.green.opacity(0.5)
    }

    private func bubble(_ item: DailySteps) -> some View {
        HStack(spacing: 5) {
            Text(shortDate(item.date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.steps > 0 ? "\(Int(item.steps)) 步" : "无数据")
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

// MARK: - 统计网格

private struct StepsStatsGrid: View {
    let daily: [DailySteps]
    let total: Double

    private var avg: Double {
        guard !daily.isEmpty else { return 0 }
        return total / Double(daily.count)
    }

    private var best: DailySteps? {
        daily.max { $0.steps < $1.steps }
    }

    private var reachedDays: Int {
        daily.filter { $0.steps >= 10_000 }.count
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            item(title: "总步数", value: "\(Int(total))")
            item(title: "日均",   value: "\(Int(avg))")
            item(title: "最高一天", value: best.map { "\(Int($0.steps))" } ?? "--")
            item(title: "达标天数", value: "\(reachedDays) 天")
        }
    }

    private func item(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
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
