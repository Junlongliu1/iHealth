//
//  SportTabView.swift
//  iHealth
//

import SwiftUI

struct SportTabView: View {
    @State private var store: WorkoutStore
    @State private var selectedType: WorkoutType?

    /// 默认从 HealthKit 读取；Preview 或测试时可注入数据
    init(store: WorkoutStore = WorkoutStore()) {
        _store = State(initialValue: store)
    }

    // MARK: - 时间过滤

    /// 本周的时间区间（遵循用户日历设置，中国区一般为周一到周日）
    private var thisWeekInterval: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())
    }

    /// 仅保留本周内开始的运动
    private var thisWeekWorkouts: [Workout] {
        guard let interval = thisWeekInterval else { return store.workouts }
        return store.workouts.filter { interval.contains($0.startDate) }
    }

    // MARK: - 计算属性

    /// 本周记录按类型筛选后再分组（日期倒序）
    private var groupedWorkouts: [(date: Date, items: [Workout])] {
        let cal = Calendar.current

        let source: [Workout]
        if let selectedType {
            source = thisWeekWorkouts.filter { $0.type == selectedType }
        } else {
            source = thisWeekWorkouts
        }

        let dict = Dictionary(grouping: source) {
            cal.startOfDay(for: $0.startDate)
        }
        return dict
            .map { (date: $0.key,
                    items: $0.value.sorted { $0.startDate > $1.startDate }) }
            .sorted { $0.date > $1.date }
    }

    /// 只显示本周出现过的运动类型
    private var availableTypes: [WorkoutType] {
        WorkoutType.allCases.filter { type in
            thisWeekWorkouts.contains { $0.type == type }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if store.isLoading && store.workouts.isEmpty {
                ProgressView("正在读取运动记录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if thisWeekWorkouts.isEmpty {
                ContentUnavailableView(
                    "本周暂无运动记录",
                    systemImage: "figure.run",
                    description: Text(
                        store.workouts.isEmpty
                        ? "在「健康」App 或 Apple Watch 中记录一次运动后，这里会显示"
                        : "本周还没有运动，继续加油！"
                    )
                )
            } else {
                VStack(spacing: 0) {
                    WorkoutFilterBar(types: availableTypes, selection: $selectedType)

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
        }
        .navigationTitle("运动")
        .navigationDestination(for: Workout.self) { workout in
            if workout.type == .running {
                RunDetailView(workout: workout)
            } else {
                WorkoutDetailView(workout: workout)
            }
        }
        .task {
            await store.requestAuthorization()
            await store.loadWorkouts()
        }
        .onChange(of: availableTypes) { _, newTypes in
            if let selected = selectedType, !newTypes.contains(selected) {
                selectedType = nil
            }
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

    // MARK: - 分组标题

    private func sectionTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.wide).day().weekday(.wide))
    }
}

// MARK: - 筛选栏

private struct WorkoutFilterBar: View {
    let types: [WorkoutType]
    @Binding var selection: WorkoutType?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", icon: "square.grid.2x2", isSelected: selection == nil) {
                    selection = nil
                }

                ForEach(types) { type in
                    chip(title: type.rawValue, icon: type.icon,
                         isSelected: selection == type) {
                        selection = (selection == type) ? nil : type
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func chip(title: String,
                      icon: String,
                      isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 记录行

private struct WorkoutRow: View {
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
        .padding(.vertical, 4)
    }
}

// MARK: - 通用详情页

struct WorkoutDetailView: View {
    let workout: Workout

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(workout.type.color.opacity(0.15))
                        Image(systemName: workout.type.icon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(workout.type.color)
                    }
                    .frame(width: 72, height: 72)

                    Text(workout.type.rawValue)
                        .font(.title3.weight(.semibold))

                    Text(workout.startDate.formatted(
                        .dateTime.year().month().day().hour().minute()
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("数据") {
                LabeledContent("时长", value: workout.formattedDuration)
                if let distance = workout.formattedDistance {
                    LabeledContent("距离", value: distance)
                }
                if let calories = workout.formattedCalories {
                    LabeledContent("消耗", value: calories)
                }
            }

            if let note = workout.note, !note.isEmpty {
                Section("备注") {
                    Text(note)
                }
            }
        }
        .navigationTitle(workout.type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
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
