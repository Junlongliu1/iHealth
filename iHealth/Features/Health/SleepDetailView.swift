//
//  SleepDetailView.swift
//  iHealth
//
//  睡眠详情页。
//  支持「日 / 周 / 月」三种时间范围。
//  日视图：按睡眠会话归属，避免跨午夜的一晚被拆到两天。
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

    var daysBack: Int {
        switch self {
        case .day:   return 0
        case .week:  return 6
        case .month: return 29
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedRange: SleepRange = .day
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var samples: [HKCategorySample] = []
    @State private var isLoading = false
    @State private var dayCache: [Date: [HKCategorySample]] = [:]
    @State private var rangeCache: [SleepRange: [HKCategorySample]] = [:]

    /// 聚合成「一晚」的最大间隔：超过 1 小时就认为是两段独立的睡眠
    private let sessionGap: TimeInterval = 60 * 60

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker

                if selectedRange == .day {
                    dayNavigator
                }

                if isLoading && samples.isEmpty {
                    loadingState
                } else if samples.isEmpty {
                    emptyState
                } else {
                    content
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
            Task { await loadCurrent() }
        }
        .onChange(of: currentDay) { _, _ in
            Task { await loadCurrent() }
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

    // MARK: - 日视图日期导航

    private var dayNavigator: some View {
        HStack(spacing: 12) {
            Button { shiftDay(by: -1) } label: {
                navArrow(systemName: "chevron.left", enabled: true)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Text(dayTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Spacer(minLength: 4)

            Button { shiftDay(by: 1) } label: {
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
            dayContent.simultaneousGesture(daySwipeGesture)
        case .week:
            trendContent(for: .week)
        case .month:
            trendContent(for: .month)
        }
    }

    // MARK: - 日视图

    private var dayContent: some View {
        SleepSummaryView(samples: samples)
            .id(currentDay)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: - 左右滑动切换日期

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let h = value.translation.width
                let v = value.translation.height
                guard abs(h) > abs(v) * 1.5, abs(h) > 50 else { return }
                if h < 0 { shiftDay(by: 1) } else { shiftDay(by: -1) }
            }
    }

    private var canGoForward: Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: currentDay)
            < calendar.startOfDay(for: Date())
    }

    private func shiftDay(by offset: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let newDay = calendar.date(byAdding: .day, value: offset, to: currentDay),
              newDay <= today else { return }
        withAnimation(.smooth(duration: 0.22)) {
            currentDay = newDay
        }
    }

    // MARK: - 日期标题

    private var dayTitle: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: currentDay)
        let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0

        switch diff {
        case 0: return "今天"
        case 1: return "昨天"
        case 2: return "前天"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEE"
            return f.string(from: day)
        }
    }

    // MARK: - 周 / 月视图

    private func trendContent(for range: SleepRange) -> some View {
        let daily = dailyTotals(from: samples, range: range)
        let summary = SleepSummary(samples: samples)
        let avg = averageTotal(daily)
        let title = range == .week ? "本周平均" : "本月平均"

        return VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Text(formatHourMinute(avg))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    SleepStageItem(label: "深睡", duration: summary.deep,  color: .indigo)
                    SleepStageItem(label: "浅睡", duration: summary.core,  color: .blue)
                    SleepStageItem(label: "眼动", duration: summary.rem,   color: .cyan)
                    SleepStageItem(label: "清醒", duration: summary.awake, color: .orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("每日睡眠")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                SleepTrendChart(data: daily, range: range)
                    .frame(height: 180)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
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

    // MARK: - 数据加载

    private func loadCurrent() async {
        switch selectedRange {
        case .day:
            await loadDay(currentDay)
        case .week, .month:
            await loadRange(selectedRange)
        }
    }

    // MARK: ★ 核心修改：按会话归属

    private func loadDay(_ day: Date) async {
        let calendar = Calendar.current
        let key = calendar.startOfDay(for: day)
        if let cached = dayCache[key] {
            samples = cached
            return
        }

        isLoading = true

        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // 1. 放宽查询范围，保证跨午夜的一整晚能被完整抓到
        let queryStart = calendar.date(byAdding: .day, value: -1, to: dayStart)!
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: dayEnd)!

        let raw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)

        // 2. 把散段聚合成「睡眠会话」
        let sessions = sleepSessions(from: raw)

        // 3. 按会话的 endDate 归属：会话结束于目标日 → 归到目标日
        let matched = sessions.filter { session in
            guard let last = session.last else { return false }
            return calendar.isDate(last.endDate, inSameDayAs: day)
        }

        let fetched = matched.flatMap { $0 }
        dayCache[key] = fetched
        samples = fetched
        isLoading = false
    }

    private func loadRange(_ range: SleepRange) async {
        if let cached = rangeCache[range] {
            samples = cached
            return
        }

        isLoading = true
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let start = calendar.date(byAdding: .day, value: -range.daysBack - 1, to: todayStart)!
        let raw = await healthManager.fetchSleepSamples(from: start, to: end)

        // 周 / 月也先聚合，避免跨午夜被拆到两天
        let sessions = sleepSessions(from: raw)
        let fetched = sessions.flatMap { $0 }
        rangeCache[range] = fetched
        samples = fetched
        isLoading = false
    }

    // MARK: - 会话聚合

    /// 把散落的样本聚合成「睡眠会话」：
    /// 相邻两条样本间隔 < sessionGap（1 小时）就视为同一晚。
    private func sleepSessions(from samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var lastEnd: Date?

        for s in sorted {
            if let last = lastEnd, s.startDate.timeIntervalSince(last) > sessionGap {
                if !current.isEmpty { sessions.append(current) }
                current = []
            }
            current.append(s)
            lastEnd = s.endDate
        }
        if !current.isEmpty { sessions.append(current) }
        return sessions
    }

    // MARK: - 聚合

    private func dailyTotals(from samples: [HKCategorySample], range: SleepRange) -> [DailySleepTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var byDay: [Date: TimeInterval] = [:]
        for s in samples {
            guard let stage = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            guard stage != .awake && stage != .inBed else { continue }
            let day = calendar.startOfDay(for: s.endDate)
            byDay[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }

        return (0...range.daysBack).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            return DailySleepTotal(date: date, total: byDay[date] ?? 0)
        }
    }

    private func averageTotal(_ data: [DailySleepTotal]) -> TimeInterval {
        let valid = data.filter { $0.total > 0 }
        guard !valid.isEmpty else { return 0 }
        let sum = valid.reduce(0) { $0 + $1.total }
        return sum / Double(valid.count)
    }

    private func formatHourMinute(_ t: TimeInterval) -> String {
        guard t > 0 else { return "0分" }
        let totalMinutes = Int(t / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)小时\(m)分" : "\(m)分"
    }

    // MARK: - 卡片背景

    @ViewBuilder
    private var cardBackground: some View {
        if colorScheme == .dark {
            Color(red: 0.11, green: 0.11, blue: 0.12)
        } else {
            Color(.secondarySystemBackground)
        }
    }
}

// MARK: - 趋势柱状图（周 / 月共用）

private struct SleepTrendChart: View {
    let data: [DailySleepTotal]
    let range: SleepRange

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("日期", item.date, unit: .day),
                y: .value("小时", item.total / 3600)
            )
            .foregroundStyle(Color.indigo.gradient)
            .cornerRadius(4)
        }
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
