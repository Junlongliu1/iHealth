//
//  RunYearView.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI

// MARK: - 年度跑步记录

struct RunYearView: View {
    let store: WorkoutStore
    @State private var year: Int

    private let currentYear = Calendar.current.component(.year, from: Date())
    private let minYear = 2000

    init(store: WorkoutStore,
         year: Int = Calendar.current.component(.year, from: Date())) {
        self.store = store
        _year = State(initialValue: year)
    }

    private var cal: Calendar { Calendar.current }

    private var allRunning: [Workout] {
        store.workouts.filter { $0.type == .running }
    }

    private var yearRuns: [Workout] {
        allRunning.filter {
            cal.component(.year, from: $0.startDate) == year
        }
    }

    /// 显示的月份：往年 12 个月；今年只到当月
    private var allMonths: [Date] {
        guard let yearStart = cal.date(
            from: DateComponents(year: year, month: 1, day: 1)
        ) else { return [] }

        let lastMonth: Int = (year == currentYear)
            ? cal.component(.month, from: Date())
            : 12

        return (1...lastMonth).reversed().compactMap { monthOffset in
            cal.date(byAdding: .month, value: monthOffset - 1, to: yearStart)
        }
    }

    private var yearDistance: Double {
        yearRuns.compactMap(\.distance).reduce(0, +)
    }
    private var yearDuration: TimeInterval {
        yearRuns.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                yearSummary

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        ForEach(allMonths, id: \.self) { month in
                            NavigationLink {
                                RunMonthView(store: store, month: month)
                            } label: {
                                // 固定月视图，不显示切换器
                                RunSummaryCard(
                                    allRuns: allRunning,
                                    anchorDate: month,
                                    scope: .month
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                yearSwitcher
            }
        }
        .refreshable {
            await store.loadWorkouts()
        }
    }

    private var yearSwitcher: some View {
        HStack(spacing: 12) {
            Button {
                guard year > minYear else { return }
                withAnimation(.snappy) { year -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(year <= minYear)
            .opacity(year <= minYear ? 0.3 : 1)

            Text("\(String(year))年")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 78)

            Button {
                guard year < currentYear else { return }
                withAnimation(.snappy) { year += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(year >= currentYear)
            .opacity(year >= currentYear ? 0.3 : 1)
        }
    }

    private var yearSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("全年汇总")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                summaryItem(
                    value: String(format: "%.1f", (yearDistance / 1000).truncated(to: 1)),
                    unit: "km",
                    title: "跑量"
                )
                divider
                summaryItem(
                    value: "\(yearRuns.count)",
                    unit: "次",
                    title: "次数"
                )
                divider
                summaryItem(
                    value: {
                        let h = yearDuration / 3600
                        return h >= 10
                            ? String(format: "%.0f", h)
                            : String(format: "%.1f", h)
                    }(),
                    unit: "小时",
                    title: "耗时"
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 8)
    }

    private func summaryItem(value: String, unit: String, title: String) -> some View {
        VStack(spacing: 3) {
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
}

// MARK: - 月度跑步记录

struct RunMonthView: View {
    let store: WorkoutStore
    let month: Date

    private var cal: Calendar { Calendar.current }

    private var allRunning: [Workout] {
        store.workouts.filter { $0.type == .running }
    }

    private var monthRuns: [Workout] {
        guard let interval = cal.dateInterval(of: .month, for: month) else {
            return []
        }
        return allRunning
            .filter { interval.contains($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    private var groupedWorkouts: [(date: Date, items: [Workout])] {
        let dict = Dictionary(grouping: monthRuns) {
            cal.startOfDay(for: $0.startDate)
        }
        return dict
            .map { (date: $0.key,
                    items: $0.value.sorted { $0.startDate > $1.startDate }) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：月度卡片（与首页同一组件，固定月视图）
            RunSummaryCard(
                allRuns: allRunning,
                anchorDate: month,
                scope: .month
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if monthRuns.isEmpty {
                ContentUnavailableView(
                    "本月暂无跑步记录",
                    systemImage: "figure.run",
                    description: Text("这个月还没有跑步数据")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedWorkouts, id: \.date) { group in
                        Section(sectionTitle(for: group.date)) {
                            ForEach(group.items) { workout in
                                NavigationLink(value: workout) {
                                    WorkoutRow(workout: workout)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await store.loadWorkouts()
                }
            }
        }
        .navigationTitle(month.formatted(.dateTime.year().month(.wide)))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(for date: Date) -> String {
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.wide).day().weekday(.wide))
    }
}

// MARK: - Preview

#Preview("年度 - 示例数据") {
    NavigationStack {
        RunYearView(store: WorkoutStore.preview(Workout.preview))
    }
}

#Preview("月度 - 示例数据") {
    NavigationStack {
        RunMonthView(
            store: WorkoutStore.preview(Workout.preview),
            month: Date()
        )
    }
}
