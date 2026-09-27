//
//  RunningShoeViews.swift
//  iHealth
//

import SwiftUI

// MARK: - 跑鞋列表

struct RunningShoeListView: View {
    @State private var store = RunningShoeStore.shared
    @State private var workoutStore = WorkoutStore()
    @State private var showAddSheet = false

    private var runningWorkouts: [Workout] {
        workoutStore.workouts.filter { $0.type == .running }
    }

    private var activeShoes: [RunningShoe] {
        store.shoes
            .filter { !$0.isRetired }
            .sorted {
                store.totalDistance(for: $0, workouts: runningWorkouts)
                > store.totalDistance(for: $1, workouts: runningWorkouts)
            }
    }

    private var retiredShoes: [RunningShoe] {
        store.shoes.filter { $0.isRetired }
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    if activeShoes.isEmpty && retiredShoes.isEmpty {
                        emptyCard
                    } else {
                        if !activeShoes.isEmpty {
                            shoeSection(title: "在役", shoes: activeShoes)
                        }
                        if !retiredShoes.isEmpty {
                            shoeSection(title: "已退役", shoes: retiredShoes)
                        }
                    }
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("跑鞋")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            RunningShoeEditView(shoe: nil) { newShoe in
                store.add(newShoe)
            }
        }
        .task {
            if workoutStore.workouts.isEmpty {
                await workoutStore.loadWorkouts()
            }
        }
    }

    // MARK: 分组

    private func shoeSection(title: String, shoes: [RunningShoe]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(shoes.enumerated()), id: \.element.id) { idx, shoe in
                    NavigationLink {
                        RunningShoeDetailView(shoe: shoe, workouts: runningWorkouts)
                    } label: {
                        ShoeRowView(
                            shoe: shoe,
                            distance: store.totalDistance(for: shoe, workouts: runningWorkouts),
                            runCount: store.runCount(for: shoe, workouts: runningWorkouts),
                            isDefault: store.isDefault(shoe)
                        )
                    }
                    .buttonStyle(.plain)

                    if idx < shoes.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Color(.systemBackground),
                        in: RoundedRectangle(cornerRadius: DSLayout.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DSLayout.cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
    }

    // MARK: 空态

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.55))

            Text("还没有跑鞋")
                .font(.system(size: 16, weight: .semibold))

            Text("添加一双跑鞋，记录每次跑步的装备使用情况")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button { showAddSheet = true } label: {
                Text("添加跑鞋")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(.orange, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardGlass()
    }
}

// MARK: - 单行显示

private struct ShoeRowView: View {
    let shoe: RunningShoe
    let distance: Double
    let runCount: Int
    let isDefault: Bool

    private var progress: Double {
        guard shoe.maxDistanceMeters > 0 else { return 0 }
        return min(distance / shoe.maxDistanceMeters, 1.5)
    }

    private var wear: ShoeWearLevel { .from(progress: progress) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(shoe.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(shoe.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(shoe.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isDefault {
                        Text("默认")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(wear.color.gradient)
                            .frame(width: max(geo.size.width * min(progress, 1), 4))
                    }
                }
                .frame(height: 4)

                HStack(spacing: 6) {
                    Text(String(format: "%.1f km", distance / 1000))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text("·").foregroundStyle(.tertiary)

                    Text("\(runCount) 次")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(wear.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(wear.color)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 跑鞋详情

struct RunningShoeDetailView: View {
    let shoe: RunningShoe
    let workouts: [Workout]

    @State private var store = RunningShoeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showAllWorkouts = false

    /// 列表中一次最多展示的记录数，超过折叠
    private let collapsedWorkoutLimit = 10

    private var currentShoe: RunningShoe {
        store.shoes.first { $0.id == shoe.id } ?? shoe
    }

    // MARK: 里程

    private var distance: Double {
        store.totalDistance(for: currentShoe, workouts: workouts)
    }

    private var recordedDistance: Double {
        store.recordedDistance(for: currentShoe, workouts: workouts)
    }

    private var runCount: Int {
        store.runCount(for: currentShoe, workouts: workouts)
    }

    private var progress: Double {
        guard currentShoe.maxDistanceMeters > 0 else { return 0 }
        return min(distance / currentShoe.maxDistanceMeters, 1.5)
    }

    private var wear: ShoeWearLevel { .from(progress: progress) }

    // MARK: 关联的跑步记录

    /// 关联到当前跑鞋的所有跑步，按时间倒序
    private var assignedWorkouts: [Workout] {
        workouts
            .filter { store.workoutShoeMap[$0.id] == currentShoe.id }
            .sorted { $0.startDate > $1.startDate }
    }

    private var visibleWorkouts: [Workout] {
        showAllWorkouts
            ? assignedWorkouts
            : Array(assignedWorkouts.prefix(collapsedWorkoutLimit))
    }

    private var hasMoreWorkouts: Bool {
        assignedWorkouts.count > collapsedWorkoutLimit
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    heroCard
                    statsCard
                    if currentShoe.initialDistanceMeters > 0 {
                        initialCard
                    }
                    if !assignedWorkouts.isEmpty {
                        workoutsCard
                    }
                    defaultCard
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(currentShoe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditSheet = true } label: {
                        Label("编辑", systemImage: "pencil")
                    }

                    if currentShoe.isRetired {
                        Button {
                            var s = currentShoe
                            s.isRetired = false
                            store.update(s)
                        } label: {
                            Label("重新启用", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button {
                            var s = currentShoe
                            s.isRetired = true
                            store.update(s)
                        } label: {
                            Label("退役", systemImage: "archivebox")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            RunningShoeEditView(shoe: currentShoe) { updated in
                store.update(updated)
            }
        }
        .alert("删除跑鞋？", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                store.delete(currentShoe)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("与此跑鞋关联的跑步记录不会被删除，仅取消关联。")
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(currentShoe.color.opacity(0.15))
                    .frame(width: 88, height: 88)
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(currentShoe.color)
            }

            VStack(spacing: 6) {
                Text(currentShoe.displayName)
                    .font(.title2.bold())

                if currentShoe.isRetired {
                    Text("已退役")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                } else {
                    Text(wear.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(wear.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(wear.color.opacity(0.15), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .cardGlass()
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                statItem(
                    title: "累计里程",
                    value: String(format: "%.1f", distance / 1000),
                    unit: "km",
                    color: currentShoe.color
                )

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 40)

                statItem(
                    title: "跑步次数",
                    value: "\(runCount)",
                    unit: "次",
                    color: currentShoe.color
                )

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1, height: 40)

                statItem(
                    title: "磨损",
                    value: "\(Int(min(progress, 1) * 100))",
                    unit: "%",
                    color: wear.color
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(wear.color.gradient)
                            .frame(width: max(geo.size.width * min(progress, 1), 4))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("已用 \(Int(distance / 1000)) / \(Int(currentShoe.maxDistanceMeters / 1000)) km")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    if progress >= 1 {
                        Text("建议更换")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                    } else {
                        Text("剩余 \(Int((currentShoe.maxDistanceMeters - distance) / 1000)) km")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardGlass()
    }

    private func statItem(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 里程拆分

    private var initialCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("里程拆分")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack {
                Text("初始里程")
                    .font(.system(size: 14))
                Spacer()
                Text(String(format: "%.2f km", currentShoe.initialDistanceMeters / 1000))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.vertical, 10)

            Divider().padding(.leading, DSLayout.rowHorizontalPadding)

            HStack {
                Text("已记录跑步")
                    .font(.system(size: 14))
                Spacer()
                Text(String(format: "%.2f km", recordedDistance / 1000))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.vertical, 10)

            Divider().padding(.leading, DSLayout.rowHorizontalPadding)

            HStack {
                Text("合计")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(String(format: "%.2f km", distance / 1000))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(currentShoe.color)
                    .monospacedDigit()
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: 关联的跑步记录（新增）

    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("跑步记录")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(assignedWorkouts.count) 次")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 4)

            // 记录列表
            VStack(spacing: 0) {
                ForEach(Array(visibleWorkouts.enumerated()), id: \.element.id) { idx, workout in
                    NavigationLink {
                        RunDetailView(workout: workout)
                    } label: {
                        ShoeWorkoutRow(workout: workout, shoeColor: currentShoe.color)
                    }
                    .buttonStyle(.plain)

                    if idx < visibleWorkouts.count - 1 {
                        Divider().padding(.leading, DSLayout.rowHorizontalPadding + 44)
                    }
                }
            }

            // 展开 / 收起
            if hasMoreWorkouts {
                Divider().padding(.leading, DSLayout.rowHorizontalPadding)

                Button {
                    withAnimation(.snappy) { showAllWorkouts.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showAllWorkouts ? "收起" : "显示全部 \(assignedWorkouts.count) 条")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: showAllWorkouts ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: 默认跑鞋

    private var defaultCard: some View {
        Button {
            if store.isDefault(currentShoe) {
                store.defaultShoeID = nil
            } else {
                store.defaultShoeID = currentShoe.id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: store.isDefault(currentShoe)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(store.isDefault(currentShoe) ? .orange : .secondary)

                Text(store.isDefault(currentShoe) ? "取消默认跑鞋" : "设为默认跑鞋")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Spacer()

                if store.isDefault(currentShoe) {
                    Text("默认")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardGlass()
    }
}

// MARK: - 关联记录单行

private struct ShoeWorkoutRow: View {
    let workout: Workout
    let shoeColor: Color

    private var pace: TimeInterval? {
        guard let d = workout.distance, d > 100, workout.duration > 0 else { return nil }
        return workout.duration / (d / 1000)
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(shoeColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(shoeColor)
            }

            // 日期 + 时间
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.startDate.formatted(
                    .dateTime.month(.twoDigits).day(.twoDigits)
                        .weekday(.abbreviated)
                ))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

                Text(workout.startDate.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            // 距离 + 配速
            VStack(alignment: .trailing, spacing: 2) {
                if let distance = workout.distance {
                    Text(String(format: "%.2f km", distance / 1000))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }

                HStack(spacing: 4) {
                    if let pace {
                        Text(Self.formatPace(pace))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(workout.formattedDuration)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private static func formatPace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }
}

// MARK: - 添加 / 编辑

struct RunningShoeEditView: View {
    let shoe: RunningShoe?
    let onSave: (RunningShoe) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand: String
    @State private var colorHex: String
    @State private var purchaseDate: Date
    @State private var maxKm: Double
    @State private var initialKm: Double

    init(shoe: RunningShoe?, onSave: @escaping (RunningShoe) -> Void) {
        self.shoe = shoe
        self.onSave = onSave
        _name = State(initialValue: shoe?.name ?? "")
        _brand = State(initialValue: shoe?.brand ?? "")
        _colorHex = State(initialValue: shoe?.colorHex ?? RunningShoe.presetColors[0])
        _purchaseDate = State(initialValue: shoe?.purchaseDate ?? Date())
        _maxKm = State(initialValue: (shoe?.maxDistanceMeters ?? 800_000) / 1000)
        _initialKm = State(initialValue: (shoe?.initialDistanceMeters ?? 0) / 1000)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称，如 Pegasus 40", text: $name)
                    TextField("品牌，如 Nike", text: $brand)
                }

                Section("颜色") {
                    colorPicker
                        .padding(.vertical, 4)
                }

                Section("购买") {
                    DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("已有里程")
                        Spacer()
                        TextField("", value: $initialKm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 80)
                        Text("km").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("初始里程")
                } footer: {
                    Text("购鞋前已跑的里程，或换鞋前遗漏的历史跑量。会与 App 内记录的跑步里程合并，一起计入累计里程与磨损进度。")
                }

                Section {
                    HStack {
                        Text("建议寿命")
                        Spacer()
                        TextField("", value: $maxKm, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 64)
                        Text("km").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("寿命")
                } footer: {
                    Text("达到此里程后建议更换。一般跑鞋寿命在 500–800 公里之间。")
                }
            }
            .navigationTitle(shoe == nil ? "添加跑鞋" : "编辑跑鞋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let result = RunningShoe(
                            id: shoe?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            brand: brand.trimmingCharacters(in: .whitespaces),
                            colorHex: colorHex,
                            purchaseDate: purchaseDate,
                            maxDistanceMeters: max(1, maxKm) * 1000,
                            isRetired: shoe?.isRetired ?? false,
                            initialDistanceMeters: max(0, initialKm) * 1000
                        )
                        onSave(result)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var colorPicker: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8),
            spacing: 14
        ) {
            ForEach(RunningShoe.presetColors, id: \.self) { hex in
                Button { colorHex = hex } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hexString: hex) ?? .orange)
                            .frame(width: 30, height: 30)
                        if colorHex == hex {
                            Circle()
                                .stroke(Color.primary, lineWidth: 2)
                                .frame(width: 38, height: 38)
                        }
                    }
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 选择器 Sheet（跑步详情页用）

struct ShoePickerSheet: View {
    let workout: Workout

    @Environment(\.dismiss) private var dismiss
    @State private var store = RunningShoeStore.shared
    @State private var showAddSheet = false

    private var assignedID: UUID? { store.workoutShoeMap[workout.id] }

    private var availableShoes: [RunningShoe] {
        let active = store.shoes.filter { !$0.isRetired }
        return active.sorted { a, b in
            let aDefault = store.isDefault(a)
            let bDefault = store.isDefault(b)
            if aDefault != bDefault { return aDefault }
            return a.name < b.name
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if assignedID != nil {
                    Section {
                        Button(role: .destructive) {
                            store.assign(nil, to: workout)
                            dismiss()
                        } label: {
                            Label("取消关联", systemImage: "xmark.circle")
                        }
                    }
                }

                if availableShoes.isEmpty {
                    Section {
                        Text("还没有跑鞋，点击下方按钮添加")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("选择跑鞋") {
                        ForEach(availableShoes) { shoe in
                            shoeOption(shoe)
                        }
                    }
                }

                Section {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("添加新跑鞋", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("选择跑鞋")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                RunningShoeEditView(shoe: nil) { newShoe in
                    store.add(newShoe)
                    store.assign(newShoe.id, to: workout)
                    dismiss()
                }
            }
        }
    }

    private func shoeOption(_ shoe: RunningShoe) -> some View {
        Button {
            store.assign(shoe.id, to: workout)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(shoe.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(shoe.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(shoe.displayName)
                            .foregroundStyle(.primary)
                        if store.isDefault(shoe) {
                            Text("默认")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange, in: Capsule())
                        }
                    }
                    Text("寿命 \(Int(shoe.maxDistanceMeters / 1000)) km")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if assignedID == shoe.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
