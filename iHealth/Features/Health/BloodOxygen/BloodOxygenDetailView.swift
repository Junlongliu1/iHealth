//
//  BloodOxygenDetailView.swift
//  iHealth
//
//  血氧详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

enum BloodOxygenRange: String, CaseIterable, Identifiable {
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

struct BloodOxygenDetailView: View {
    @State private var healthManager = HealthManager.shared

    @State private var selectedRange: BloodOxygenRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var weekAnchor: Date = Date()
    @State private var monthAnchor: Date = Date()

    @State private var hourly: [HourlyBloodOxygen] = []
    @State private var daily: [DailyBloodOxygen] = []
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
        .navigationTitle("血氧")
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
            ForEach(BloodOxygenRange.allCases) { range in
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
        let values = hourly.compactMap { $0.percent }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let lowest = hourly.compactMap { item -> HourlyBloodOxygen? in
            item.percent != nil ? item : nil
        }.min { ($0.percent ?? 100) < ($1.percent ?? 100) }
        let hasAny = !values.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("平均血氧")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hasAny ? "\(Int(avg.rounded()))" : "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("%")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每小时血氧")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if hasAny {
                    BloodOxygenHourlyChart(data: hourly, selection: $selectedHour)
                        .frame(height: 140)
                } else {
                    emptyChart.frame(height: 140)
                }
            }

            if let lowest, let p = lowest.percent {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)

                    Text("血氧最低时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("\(String(format: "%02d", lowest.hour)):00 · \(Int(p.rounded())) %")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.10))
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 周 / 月视图

    private func trendContent(for range: BloodOxygenRange) -> some View {
        let avg = averageDaily(daily)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("日均血氧")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(avg.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("%")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每日平均血氧")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text("点击查看某天")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                BloodOxygenTrendChart(
                    data: daily,
                    range: range,
                    selection: $selectedTrendDay
                )
                .frame(height: 140)
            }

            BloodOxygenStatsGrid(daily: daily)
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
                let fetched = await healthManager.fetchHourlyBloodOxygen(for: newDay)
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
            hourly = await healthManager.fetchHourlyBloodOxygen(for: currentDay)
        case .week:
            daily = await fetchWeek(weekAnchor)
        case .month:
            daily = await fetchMonth(monthAnchor)
        }
    }

    private func fetchWeek(_ anchor: Date) async -> [DailyBloodOxygen] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        let now = Date()
        let isCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start == weekStart
        let end = isCurrentWeek
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : weekEnd
        return await healthManager.fetchDailyBloodOxygen(from: weekStart, to: end)
    }

    private func fetchMonth(_ anchor: Date) async -> [DailyBloodOxygen] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: anchor)!
        let monthStart = interval.start
        let now = Date()
        let isCurrentMonth = calendar.dateInterval(of: .month, for: now)!.start == monthStart
        let end = isCurrentMonth
            ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            : interval.end
        return await healthManager.fetchDailyBloodOxygen(from: monthStart, to: end)
    }

    private func averageDaily(_ data: [DailyBloodOxygen]) -> Double? {
        let values = data.compactMap { $0.percent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - 每小时血氧曲线

private struct BloodOxygenHourlyChart: View {
    let data: [HourlyBloodOxygen]
    @Binding var selection: Int?

    private var selectedItem: HourlyBloodOxygen? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                if let p = item.percent {
                    AreaMark(
                        x: .value("小时", item.hour),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("血氧", p)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.28), Color.blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("小时", item.hour),
                        y: .value("血氧", p)
                    )
                    .foregroundStyle(Color.blue)
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

    private func bubble(_ item: HourlyBloodOxygen) -> some View {
        HStack(spacing: 5) {
            Text("\(String(format: "%02d", item.hour)):00")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.percent.map { "\(Int($0.rounded())) %" } ?? "无数据")
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
        let values = data.compactMap { $0.percent }
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            return 90...100
        }
        let pad = max((hi - lo) * 0.2, 1)
        return max(0, lo - pad)...min(100, hi + pad)
    }
}

// MARK: - 每日血氧趋势图（折线 + 面积，含 95% 参考线，支持点击选中）

private struct BloodOxygenTrendChart: View {
    let data: [DailyBloodOxygen]
    let range: BloodOxygenRange
    @Binding var selection: Date?

    private var validValues: [Double] { data.compactMap { $0.percent } }

    private var selectedItem: DailyBloodOxygen? {
        guard let selection else { return nil }
        let nearest = data.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
        guard let nearest else { return nil }
        if abs(nearest.date.timeIntervalSince(selection)) > 12 * 3600 { return nil }
        return nearest
    }

    /// 参考线：95%（正常血氧下限）
    private let referenceValue: Double = 95

    var body: some View {
        Chart {
            // 95% 参考线
            RuleMark(y: .value("参考", referenceValue))
                .foregroundStyle(Color.blue.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .zIndex(0)

            ForEach(data) { item in
                if let p = item.percent {
                    AreaMark(
                        x: .value("日期", item.date, unit: .day),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("血氧", p)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.28), Color.blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    .zIndex(1)

                    LineMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("血氧", p)
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .zIndex(2)
                }
            }

            if let item = selectedItem, let p = item.percent {
                PointMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("血氧", p)
                )
                .foregroundStyle(p < referenceValue ? Color.pink : Color.blue)
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

    private func bubble(_ item: DailyBloodOxygen) -> some View {
        let isLow = (item.percent ?? 100) < referenceValue
        return HStack(spacing: 5) {
            Text(shortDate(item.date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(item.percent.map { "\(Int($0.rounded())) %" } ?? "无数据")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isLow ? Color.pink : Color.secondary)
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

    /// 以数据范围为基准的 Y 轴，同时保证 95% 参考线可见
    private var yDomain: ClosedRange<Double> {
        guard let lo = validValues.min(),
              let hi = validValues.max(),
              lo < hi else {
            return 90...100
        }
        let lower = min(lo, referenceValue) - max((hi - lo) * 0.15, 1)
        let upper = hi + max((hi - lo) * 0.15, 1)
        return max(0, lower)...min(100, upper)
    }
}
// MARK: - 统计网格

private struct BloodOxygenStatsGrid: View {
    let daily: [DailyBloodOxygen]

    private var valid: [Double] { daily.compactMap { $0.percent } }

    private var avg: Double? {
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private var highest: Double? { valid.max() }
    private var lowest:  Double? { valid.min() }

    /// 低于 90% 视为低血氧
    private var lowDays: Int { valid.filter { $0 < 90 }.count }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            item(title: "平均", value: avg.map { "\(Int($0.rounded())) %" } ?? "--")
            item(title: "最高", value: highest.map { "\(Int($0.rounded())) %" } ?? "--")
            item(title: "最低", value: lowest.map { "\(Int($0.rounded())) %" } ?? "--")
            item(title: "<90% 天数", value: "\(lowDays) 天")
        }
    }

    private func item(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.blue)
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
