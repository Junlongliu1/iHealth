//  ReadinessTrendView.swift
//  iHealth
//
//  职责：趋势页（依赖 Charts 框架）。
//
//  · 7 / 30 / 60 天范围切换
//  · 三张图表：准备度与恢复度 / 分项评分 / 训练负荷
//  · 五张指标图：睡眠 / 静息心率 / 步数 / 基础代谢 / 活动消耗
//  · 长按卡片头部 → 打开对应详情页
//  · 每张卡片独立竖线
//  · 多线图表气泡：横排单行，不溢出、不变色
//  · 加载态：居中脉冲加载器
//
//  依赖：
//    TrendRange.swift              —— 枚举 + 数据点
//    MultiLineCallout.swift        —— 多线气泡
//    TrendMetricCard.swift         —— 通用卡片
//    TrendLoadingIndicator.swift   —— 加载指示器

import SwiftUI
import Charts

struct ReadinessTrendView: View {
    @State private var store = BodyMetricsStore.shared
    @State private var range: TrendRange = .thirtyDays

    // 三张原图表各自的选中日期
    @State private var readinessSelection: Date?
    @State private var recoverySelection: Date?
    @State private var loadSelection: Date?

    // 从 HealthManager 拉取的指标
    @State private var stepsPoints: [TrendDataPoint] = []
    @State private var basalEnergyPoints: [TrendDataPoint] = []
    @State private var activeEnergyPoints: [TrendDataPoint] = []

    // 加载与入场状态
    @State private var hasLoadedOnce = false
    @State private var revealed = false

    /// 首屏加载最短时长（避免加载器一闪而过）
    private let minimumLoadingSeconds: TimeInterval = 0.6

    // MARK: - 准备度快照

    private var snapshots: [ReadinessSnapshot] {
        let all = store.allSnapshots
        return all.count > range.days ? Array(all.suffix(range.days)) : all
    }

    private var selectedSnapshot: ReadinessSnapshot? {
        guard let readinessSelection else { return nil }
        return snapshots.first {
            Calendar.current.isDate($0.date, inSameDayAs: readinessSelection)
        }
    }

    private var selectedRecoverySnapshot: ReadinessSnapshot? {
        guard let recoverySelection else { return nil }
        return snapshots.first {
            Calendar.current.isDate($0.date, inSameDayAs: recoverySelection)
        }
    }

    private var selectedLoadSnapshot: ReadinessSnapshot? {
        guard let loadSelection else { return nil }
        return snapshots.first {
            Calendar.current.isDate($0.date, inSameDayAs: loadSelection)
        }
    }

    // MARK: - 睡眠 / 静息心率

    private var sleepPoints: [TrendDataPoint] {
        let all = store.history
        let trimmed = all.count > range.days ? Array(all.suffix(range.days)) : all
        return trimmed.map {
            TrendDataPoint(date: $0.date,
                           value: $0.sleepHours > 0 ? $0.sleepHours : nil)
        }
    }

    private var restingHRPoints: [TrendDataPoint] {
        let all = store.history
        let trimmed = all.count > range.days ? Array(all.suffix(range.days)) : all
        return trimmed.map {
            TrendDataPoint(date: $0.date,
                           value: $0.rhr > 0 ? $0.rhr : nil)
        }
    }

    private var hasAnyData: Bool {
        !snapshots.isEmpty || !stepsPoints.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("范围", selection: $range) {
                    ForEach(TrendRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: range) { _, _ in
                    readinessSelection = nil
                    recoverySelection = nil
                    loadSelection = nil
                    Task { await loadHealthKitMetrics() }
                }

                if !hasLoadedOnce {
                    TrendLoadingIndicator()
                        .transition(
                            .asymmetric(
                                insertion: .opacity,
                                removal: .opacity.combined(with: .scale(scale: 1.06))
                            )
                        )
                } else if !hasAnyData {
                    ContentUnavailableView(
                        "暂无趋势数据",
                        systemImage: "chart.xyaxis.line",
                        description: Text("累积几天数据后即可查看趋势")
                    )
                    .padding(.top, 60)
                    .transition(.opacity)
                } else {
                    content
                        .transition(.opacity)
                }
            }
            .padding(.vertical)
            .animation(.smooth(duration: 0.4), value: hasLoadedOnce)
            .animation(.smooth(duration: 0.4), value: hasAnyData)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("趋势")
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
    }

    // MARK: - 内容（级联入场）

    @ViewBuilder
    private var content: some View {
        readinessChart.cardReveal(revealed, delay: 0)
        recoveryChart.cardReveal(revealed, delay: 0.04)
        loadChart.cardReveal(revealed, delay: 0.08)
        sleepChart.cardReveal(revealed, delay: 0.12)
        restingHRChart.cardReveal(revealed, delay: 0.16)
        stepsChart.cardReveal(revealed, delay: 0.20)
        basalEnergyChart.cardReveal(revealed, delay: 0.24)
        activeEnergyChart.cardReveal(revealed, delay: 0.28)
    }

    // MARK: - 首屏加载

    private func initialLoad() async {
        let start = Date()

        await store.load()
        await loadHealthKitMetrics()

        // 最短加载时长（避免加载器一闪而过）
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimumLoadingSeconds {
            try? await Task.sleep(for: .seconds(minimumLoadingSeconds - elapsed))
        }

        withAnimation(.smooth(duration: 0.35)) {
            hasLoadedOnce = true
        }

        // 让内容先落位，再触发级联入场
        try? await Task.sleep(for: .milliseconds(40))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            revealed = true
        }
    }

    // MARK: - 准备度与恢复度

    private var readinessChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("准备度与恢复度")
                    .font(.headline)
                Spacer()
                if let s = selectedSnapshot {
                    Text(dayLabel(s.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(snapshots) { s in
                    LineMark(
                        x: .value("日期", s.date),
                        y: .value("分数", s.readiness),
                        series: .value("类型", "准备度")
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("日期", s.date),
                        y: .value("分数", s.recovery),
                        series: .value("类型", "恢复度")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }

                if let s = selectedSnapshot {
                    RuleMark(x: .value("选中", s.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            MultiLineCallout(items: [
                                .init(color: .green, name: "准备", value: "\(Int(s.readiness.rounded()))"),
                                .init(color: .blue,  name: "恢复", value: "\(Int(s.recovery.rounded()))")
                            ])
                        }
                }

                RuleMark(y: .value("良好线", 70))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.green.opacity(0.4))
                RuleMark(y: .value("警告线", 50))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.orange.opacity(0.4))
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: $readinessSelection)
            .frame(height: 220)
            .animation(.smooth(duration: 0.5), value: snapshots.count)
            .animation(.snappy(duration: 0.18), value: selectedSnapshot?.id)

            HStack(spacing: 16) {
                Label("准备度", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
                Label("恢复度", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 分项评分

    private var recoveryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("分项评分")
                    .font(.headline)
                Spacer()
                if let s = selectedRecoverySnapshot {
                    Text(dayLabel(s.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(snapshots) { s in
                    LineMark(x: .value("日期", s.date), y: .value("HRV", s.hrvScore), series: .value("类型", "HRV"))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("睡眠", s.sleepScore), series: .value("类型", "睡眠"))
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("RHR", s.rhrScore), series: .value("类型", "RHR"))
                        .foregroundStyle(.pink)
                        .interpolationMethod(.catmullRom)
                }
                if let s = selectedRecoverySnapshot {
                    RuleMark(x: .value("选中", s.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            MultiLineCallout(items: [
                                .init(color: .blue,   name: "HRV",  value: "\(Int(s.hrvScore.rounded()))"),
                                .init(color: .purple, name: "睡眠", value: "\(Int(s.sleepScore.rounded()))"),
                                .init(color: .pink,   name: "RHR",  value: "\(Int(s.rhrScore.rounded()))")
                            ])
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: $recoverySelection)
            .frame(height: 220)
            .animation(.smooth(duration: 0.5), value: snapshots.count)
            .animation(.snappy(duration: 0.18), value: selectedRecoverySnapshot?.id)

            HStack(spacing: 16) {
                Label("HRV", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
                Label("睡眠", systemImage: "circle.fill").foregroundStyle(.purple).font(.caption)
                Label("RHR", systemImage: "circle.fill").foregroundStyle(.pink).font(.caption)
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 训练负荷

    private var loadChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练负荷")
                    .font(.headline)
                Spacer()
                if let s = selectedLoadSnapshot {
                    Text(dayLabel(s.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }

            Chart {
                ForEach(snapshots) { s in
                    LineMark(x: .value("日期", s.date), y: .value("CTL", s.ctl), series: .value("类型", "CTL"))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("ATL", s.atl), series: .value("类型", "ATL"))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("TSB", s.tsb), series: .value("类型", "TSB"))
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("零线", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.4))
                if let s = selectedLoadSnapshot {
                    RuleMark(x: .value("选中", s.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            MultiLineCallout(items: [
                                .init(color: .blue,   name: "CTL", value: String(format: "%.1f", s.ctl)),
                                .init(color: .orange, name: "ATL", value: String(format: "%.1f", s.atl)),
                                .init(color: .green,  name: "TSB", value: String(format: "%+.1f", s.tsb))
                            ])
                        }
                }
            }
            .chartXSelection(value: $loadSelection)
            .frame(height: 220)
            .animation(.smooth(duration: 0.5), value: snapshots.count)
            .animation(.snappy(duration: 0.18), value: selectedLoadSnapshot?.id)

            HStack(spacing: 16) {
                Label("CTL", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
                Label("ATL", systemImage: "circle.fill").foregroundStyle(.orange).font(.caption)
                Label("TSB", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 5 张生活方式指标卡片

    private var sleepChart: some View {
        TrendMetricCard(
            title: "睡眠",
            icon: "bed.double.fill",
            color: .indigo,
            points: sleepPoints,
            trendRange: range,
            valueFormatter: { String(format: "%.1f 小时", $0) },
            yAxisFormatter: { String(format: "%.0fh", $0) }
        ) {
            SleepDetailView()
        }
    }

    private var restingHRChart: some View {
        TrendMetricCard(
            title: "静息心率",
            icon: "heart.circle.fill",
            color: .red,
            points: restingHRPoints,
            trendRange: range,
            valueFormatter: { "\(Int($0.rounded())) 次/分" },
            yAxisFormatter: { "\(Int($0.rounded()))" }
        ) {
            RestingHeartRateDetailView()
        }
    }

    private var stepsChart: some View {
        TrendMetricCard(
            title: "步数",
            icon: "figure.walk",
            color: .green,
            points: stepsPoints,
            trendRange: range,
            valueFormatter: { "\(Int($0.rounded())) 步" },
            yAxisFormatter: { $0 >= 10_000 ? "\(Int($0 / 1000))k" : "\(Int($0))" }
        ) {
            StepsDetailView()
        }
    }

    private var basalEnergyChart: some View {
        TrendMetricCard(
            title: "基础代谢",
            icon: "flame.fill",
            color: .yellow,
            points: basalEnergyPoints,
            trendRange: range,
            valueFormatter: { "\(Int($0.rounded())) 大卡" },
            yAxisFormatter: { "\(Int($0.rounded()))" }
        ) {
            BasalEnergyDetailView()
        }
    }

    private var activeEnergyChart: some View {
        TrendMetricCard(
            title: "活动消耗",
            icon: "figure.run",
            color: .red,
            points: activeEnergyPoints,
            trendRange: range,
            valueFormatter: { "\(Int($0.rounded())) 大卡" },
            yAxisFormatter: { "\(Int($0.rounded()))" }
        ) {
            ActiveEnergyDetailView()
        }
    }

    // MARK: - HealthKit 加载

    private func loadHealthKitMetrics() async {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -range.days, to: end) ?? end

        async let steps = HealthManager.shared.fetchDailySteps(from: start, to: end)
        async let basal = HealthManager.shared.fetchDailyBasalEnergy(from: start, to: end)
        async let active = HealthManager.shared.fetchDailyActiveEnergy(from: start, to: end)

        let (s, b, a) = await (steps, basal, active)

        withAnimation(.smooth(duration: 0.45)) {
            stepsPoints = s.map {
                TrendDataPoint(date: $0.date, value: $0.steps > 0 ? $0.steps : nil)
            }
            basalEnergyPoints = b.map {
                TrendDataPoint(date: $0.date, value: $0.kilocalories > 0 ? $0.kilocalories : nil)
            }
            activeEnergyPoints = a.map {
                TrendDataPoint(date: $0.date, value: $0.kilocalories > 0 ? $0.kilocalories : nil)
            }
        }
    }

    // MARK: - 辅助

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
    }
}

#Preview {
    NavigationStack {
        ReadinessTrendView()
    }
}
