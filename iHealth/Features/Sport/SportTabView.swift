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
    @State private var summaryScope: RunScope = .month

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
                    await store.loadWorkouts()
                    store.resetSplits()
                    await store.loadAllRunSplits()
                    store.computePersonalBests()
                }
            }
        }
        .navigationTitle("跑步")
        .navigationDestination(for: Workout.self) { workout in
            RunDetailView(workout: workout)
        }
        .task {
            // 1. 授权
            await store.requestAuthorization()

            // 2. 加载 workouts（内部会真正等待查询结束）
            await store.loadWorkouts()

            // 3. 加载 splits + 计算 PB
            await store.loadAllRunSplits()
            store.computePersonalBests()
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

    // MARK: 主题渐变

    private var runGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.62, blue: 0.2),
                Color(red: 1.0, green: 0.42, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: 格式化

    private var distanceValue: String {
        guard totalDistance > 0 else { return "0" }
        return String(format: "%.1f", totalDistance / 1000)
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
                    scopeToggle(onScopeChange)
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

    // MARK: 切换器

    private func scopeToggle(_ onChange: @escaping (RunScope) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(RunScope.allCases) { s in
                Button {
                    withAnimation(.snappy) { onChange(s) }
                } label: {
                    Text(s.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(scope == s ? Color.white : Color.secondary)
                        .frame(width: 30, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if scope == s {
                        Capsule().fill(runGradient)
                    }
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
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
                    .foregroundStyle(runGradient)

                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(runGradient.opacity(0.7))
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
                    .fill(runGradient)
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
                    .fill(runGradient)
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

// MARK: - 本周跑步卡片

struct WeekRunsCard: View {
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本周跑步")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !workouts.isEmpty {
                    Text("\(workouts.count) 次")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 10)

            if workouts.isEmpty {
                Text("本周还没有跑步记录")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workouts.enumerated()),
                            id: \.element.id) { index, workout in
                        NavigationLink(value: workout) {
                            WorkoutRow(workout: workout)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < workouts.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

// MARK: - 个人最好成绩卡片

struct PBCard: View {
    let bests: [PersonalBest]

    private var runGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.62, blue: 0.2),
                Color(red: 1.0, green: 0.42, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("个人最好成绩")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("分段最快")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("PB")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(runGradient)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(bests.enumerated()), id: \.element.id) { index, pb in
                    pbRow(pb)
                    if index < bests.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func pbRow(_ pb: PersonalBest) -> some View {
        HStack(spacing: 0) {
            Text(pb.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .leading)

            if let time = pb.time {
                Text(formatTime(time))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(runGradient)

                Spacer(minLength: 8)

                if let date = pb.date {
                    Text(formatDate(date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("——")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Text("暂无记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 9)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        PBCard.dateFormatter.string(from: date)
    }
}

// MARK: - 记录行

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(workout.type.color.opacity(0.15))
                Image(systemName: workout.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(workout.type.color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.type.rawValue)
                    .font(.body.weight(.medium))

                HStack(spacing: 6) {
                    Text(workout.startDate, format: .dateTime.hour().minute())
                    if let calories = workout.formattedCalories {
                        Text("·")
                        Text(calories)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.formattedDuration)
                    .font(.subheadline.weight(.semibold))
                if let distance = workout.formattedDistance {
                    Text(distance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
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
