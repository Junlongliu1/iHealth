//
//  SportTabView.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI

// MARK: - 周/月范围

enum RunScope: String, CaseIterable, Identifiable {
    case week  = "周"
    case month = "月"

    var id: String { rawValue }
}

// MARK: - 运动首页

struct SportTabView: View {
    @State private var store: WorkoutStore
    @State private var summaryScope: RunScope = .week

    init(store: WorkoutStore = WorkoutStore()) {
        _store = State(initialValue: store)
    }

    // MARK: - 计算属性

    private var runningWorkouts: [Workout] {
        store.workouts.filter { $0.type == .running }
    }

    /// 本周跑步（倒序：最新在前）
    private var thisWeekRuns: [Workout] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else {
            return runningWorkouts
        }
        return runningWorkouts
            .filter { interval.contains($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if store.isLoading && store.workouts.isEmpty {
                ProgressView("正在读取运动记录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runningWorkouts.isEmpty {
                ContentUnavailableView(
                    "暂无跑步记录",
                    systemImage: "figure.run",
                    description: Text("在「健康」App 或 Apple Watch 中记录一次跑步后，这里会显示")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // 错误提示（如有）
                        if let error = store.errorMessage {
                            errorBanner(error)
                        }

                        // ① 汇总卡片（周/月切换，可点击进年度页）
                        NavigationLink {
                            RunYearView(store: store)
                        } label: {
                            RunSummaryCard(
                                allRuns: runningWorkouts,
                                anchorDate: Date(),
                                scope: summaryScope,
                                showsToggle: true,
                                onScopeChange: { newScope in
                                    summaryScope = newScope
                                }
                            )
                        }
                        .buttonStyle(.plain)

                        // ② 本周记录卡片
                        WeekRunsCard(workouts: thisWeekRuns)

                        // ③ 个人最好成绩
                        PBCard(bests: store.personalBests)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await load(requestAuth: false, resetSplits: true)
                }
            }
        }
        .navigationTitle("跑步")
        .navigationDestination(for: Workout.self) { workout in
            RunDetailView(workout: workout)
        }
        .task {
            await load(requestAuth: true, resetSplits: false)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // TODO: 添加运动记录
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - 加载入口

    @MainActor
    private func load(requestAuth: Bool, resetSplits: Bool) async {
        if requestAuth {
            await store.requestAuthorization()
        }
        await store.loadWorkouts()
        if resetSplits {
            store.resetSplits()
        }
        await store.loadAllRunSplits()
        store.computePersonalBests()
    }

    // MARK: - 错误横幅

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

// MARK: - 汇总卡片（周/月自适应）

struct RunSummaryCard: View {
    let allRuns: [Workout]
    let anchorDate: Date
    let scope: RunScope
    var showsToggle: Bool = false
    var onScopeChange: ((RunScope) -> Void)? = nil

    private var cal: Calendar { Calendar.current }

    // MARK: 范围

    private var currentInterval: DateInterval? {
        switch scope {
        case .week:
            return cal.dateInterval(of: .weekOfYear, for: anchorDate)
        case .month:
            return cal.dateInterval(of: .month, for: anchorDate)
        }
    }

    private var runs: [Workout] {
        guard let interval = currentInterval else { return [] }
        return allRuns.filter { interval.contains($0.startDate) }
    }

    // MARK: 汇总

    private var totalDistance: Double {
        runs.compactMap(\.distance).reduce(0, +)
    }
    private var totalDuration: TimeInterval {
        runs.reduce(0) { $0 + $1.duration }
    }
    private var runCount: Int { runs.count }

    // MARK: 标题

    private var rangeTitle: String {
        switch scope {
        case .week:
            guard let interval = currentInterval else { return "本周" }
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.defaultDigits).day())) – \(end.formatted(.dateTime.month(.defaultDigits).day()))"
        case .month:
            return anchorDate.formatted(.dateTime.month(.wide))
        }
    }

    // MARK: 格式化

    private var distanceValue: String {
        guard totalDistance > 0 else { return "0" }
        let km = (totalDistance / 1000).truncated(to: 1)   // 汇总用 1 位
        return String(format: "%.1f", km)
    }
    
    private var durationValue: String {
        let total = Int(totalDuration)
        if total >= 3600 {
            return String(format: "%.1f", Double(total) / 3600)
        }
        return "\(total / 60)"
    }
    private var durationUnit: String {
        Int(totalDuration) >= 3600 ? "小时" : "分"
    }

    // MARK: 日历数据

    private var runDayNumbers: Set<Int> {
        Set(runs.map { cal.component(.day, from: $0.startDate) })
    }

    private var gridDays: [Int?] {
        guard let interval = cal.dateInterval(of: .month, for: anchorDate) else {
            return []
        }
        let daysInMonth = cal.range(of: .day, in: .month, for: anchorDate)?.count ?? 30
        let firstWeekday = cal.component(.weekday, from: interval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var result: [Int?] = Array(repeating: nil, count: leading)
        result.append(contentsOf: (1...daysInMonth).map { Optional($0) })
        return result
    }

    private var weekDayDates: [Date] {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: anchorDate) else {
            return []
        }
        return (0..<7).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: interval.start)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text(rangeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if showsToggle, let onScopeChange {
                    Picker("", selection: Binding(
                        get: { scope },
                        set: { newValue in
                            withAnimation(.snappy) { onScopeChange(newValue) }
                        }
                    )) {
                        ForEach(RunScope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .labelsHidden()
                    .tint(.orange)
                }
            }

            HStack(spacing: 0) {
                statItem(value: distanceValue, unit: "km", title: "跑量")
                divider
                statItem(value: "\(runCount)", unit: "次", title: "次数")
                divider
                statItem(value: durationValue, unit: durationUnit, title: "耗时")
            }

            if scope == .week {
                weekCalendar
            } else {
                monthCalendar
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 8)
    }

    private func statItem(value: String, unit: String, title: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.runGradient)

                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.runGradient.opacity(0.7))
            }
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 周日历

    private var weekCalendar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 0) {
                ForEach(weekDayDates, id: \.self) { date in
                    weekDayCell(date)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func weekDayCell(_ date: Date) -> some View {
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let didRun = runs.contains {
            $0.startDate >= dayStart && $0.startDate < dayEnd
        }
        let isToday = cal.isDateInToday(date)

        return ZStack {
            if didRun {
                Circle()
                    .fill(.runGradient)
                    .frame(width: 20, height: 20)
            } else if isToday {
                Circle()
                    .stroke(Color.orange.opacity(0.6), lineWidth: 1)
                    .frame(width: 20, height: 20)
            }
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: 9, weight: didRun ? .bold : .regular))
                .foregroundStyle(didRun
                                 ? Color.white
                                 : (isToday ? Color.orange : Color.primary))
        }
        .frame(height: 20)
    }

    // MARK: 月历

    private var monthCalendar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 4
            ) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        monthDayCell(day)
                    } else {
                        Color.clear.frame(height: 20)
                    }
                }
            }
        }
    }

    private func monthDayCell(_ day: Int) -> some View {
        let didRun = runDayNumbers.contains(day)
        let isToday = cal.isDateInToday(monthDayDate(day))

        return ZStack {
            if didRun {
                Circle()
                    .fill(.runGradient)
                    .frame(width: 20, height: 20)
            } else if isToday {
                Circle()
                    .stroke(Color.orange.opacity(0.6), lineWidth: 1)
                    .frame(width: 20, height: 20)
            }
            Text("\(day)")
                .font(.system(size: 9, weight: didRun ? .bold : .regular))
                .foregroundStyle(didRun
                                 ? Color.white
                                 : (isToday ? Color.orange : Color.primary))
        }
        .frame(height: 20)
    }

    private func monthDayDate(_ day: Int) -> Date {
        guard let interval = cal.dateInterval(of: .month, for: anchorDate) else {
            return anchorDate
        }
        return cal.date(byAdding: .day, value: day - 1, to: interval.start) ?? anchorDate
    }
}

// MARK: - Preview

#Preview("空数据") {
    NavigationStack {
        SportTabView(store: WorkoutStore.preview([]))
    }
}

#Preview("示例数据") {
    NavigationStack {
        SportTabView(store: WorkoutStore.preview(Workout.preview))
    }
}
