//
//  BodyTabView.swift
//  iHealth
//

import SwiftUI

struct BodyTabView: View {
    /// 由 MainTabView 传入，每次切换 tab 时变化，用于重播入场动画
    let activationID: UUID

    @State private var store = BodyMetricsStore.shared
    @State private var profile = AthleteProfileStore.shared
    @State private var activeExplanation: MetricExplanation?
    @State private var showSubScores = false
    @State private var showTrainingLoad = false
    @State private var selectedSport: SportType = .running

    @State private var revealed = false

    @Environment(\.cardCornerRadius) private var cardRadius

    var body: some View {
        Group {
            if store.isLoading {
                loadingView
                    .transition(.opacity)
            } else if let error = store.loadError, store.history.isEmpty {
                errorView(error)
                    .transition(.opacity)
            } else if let s = store.todaySnapshot {
                content(s)
                    .transition(.opacity)
            } else {
                emptyView
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: store.isLoading)
        .environment(\.cardCornerRadius, 16)
        .environment(\.cardPadding, 16)
        .environment(\.cardSpacing, 16)
        .navigationTitle("身体")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if store.isSyncing {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: store.isSyncing)
        .task {
            await store.load()
            // 首次进入时播放一次
            triggerReveal()
        }
        .onChange(of: activationID) { _, _ in
            // 每次切换回本 tab，重播级联
            triggerReveal()
        }
        .sheet(item: $activeExplanation) { explanation in
            MetricExplanationView(explanation: explanation)
        }
        .sheet(isPresented: $showSubScores) {
            SubScoresView(snapshot: store.todaySnapshot)
        }
        .sheet(isPresented: $showTrainingLoad) {
            TrainingLoadDetailView(
                snapshot: store.todaySnapshot,
                previousSnapshot: store.allSnapshots.dropLast().last,
                todayTSS: store.history.last?.tss ?? 0
            )
        }
    }

    /// 重置 + 重播级联动画
    private func triggerReveal() {
        revealed = false
        Task { @MainActor in
            // 让 false 有一帧渲染，再置 true
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                revealed = true
            }
        }
    }

    // MARK: - 主内容

    private func content(_ s: ReadinessSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                trainingLoadCard(s)
                    .cardReveal(revealed, delay: 0)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    readinessCard(s)
                        .cardReveal(revealed, delay: 0.06)
                    recoveryCard(s)
                        .cardReveal(revealed, delay: 0.12)
                }

                scoresCard(s)
                    .cardReveal(revealed, delay: 0.18)

                sportAdviceCard(s)
                    .cardReveal(revealed, delay: 0.24)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await store.refresh()
            // 刷新完再做一次轻微脉冲，强化"数据已更新"的反馈
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                revealed = false
            }
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                revealed = true
            }
        }
    }

    // MARK: - 训练负荷卡片

    private func trainingLoadCard(_ s: ReadinessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("训练负荷")
                    .font(.headline)

                Button {
                    activeExplanation = MetricLibrary.ctl
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关于训练负荷")

                Spacer()

                Button {
                    showTrainingLoad = true
                } label: {
                    HStack(spacing: 2) {
                        Text("查看详情")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                heroMetric(
                    title: "体能基础",
                    subtitle: "CTL",
                    value: String(format: "%.1f", s.ctl),
                    color: .teal,
                    explanation: MetricLibrary.ctl
                )

                heroDivider

                heroMetric(
                    title: "训练负荷",
                    subtitle: "ATL",
                    value: String(format: "%.1f", s.atl),
                    color: atlColor(atl: s.atl, ctl: s.ctl),
                    explanation: MetricLibrary.atl
                )

                heroDivider

                heroMetric(
                    title: "训练压力",
                    subtitle: "TSB",
                    value: String(format: "%+.1f", s.tsb),
                    color: tsbColor(tsb: s.tsb),
                    explanation: MetricLibrary.tsb
                )
            }
            .padding(.top, 4)
        }
        .glassCard(cornerRadius: cardRadius)
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 1, height: 36)
    }

    private func heroMetric(
        title: String,
        subtitle: String,
        value: String,
        color: Color,
        explanation: MetricExplanation
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    activeExplanation = explanation
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关于 \(title)")
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.45), value: value)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 准备度卡片

    private func readinessCard(_ s: ReadinessSnapshot) -> some View {
        let state = StateStyle.from(readiness: s.readiness)
        let tint = scoreTint(s.readiness)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("准备度")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Button {
                    activeExplanation = MetricLibrary.readiness
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关于准备度")

                Spacer()

                Text(state.badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: Capsule())
                    .contentTransition(.interpolate)
                    .animation(.snappy(duration: 0.35), value: state.badge)
            }

            HStack {
                Spacer()
                MetricRing(score: s.readiness, color: tint, lineWidth: 8, size: 72, fontSize: 24)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("准备度")
                    .accessibilityValue("\(Int(s.readiness.rounded())) 分")
                Spacer()
            }
            .padding(.vertical, 4)

            VStack(spacing: 0) {
                compactContributionRow(
                    label: "恢复",
                    value: s.recovery * 0.70,
                    maxValue: 70,
                    color: .blue
                )
                Spacer(minLength: 6)
                compactContributionRow(
                    label: "TSB",
                    value: s.tsbScore * 0.30,
                    maxValue: 30,
                    color: .orange
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: cardRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            showSubScores = true
        }
    }

    // MARK: - 恢复度卡片

    private func recoveryCard(_ s: ReadinessSnapshot) -> some View {
        let tint = scoreTint(s.recovery)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("恢复度")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Button {
                    activeExplanation = MetricLibrary.recovery
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关于恢复度")

                Spacer()

                Text(recoveryLabel(s.recovery))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: Capsule())
                    .contentTransition(.interpolate)
                    .animation(.snappy(duration: 0.35), value: recoveryLabel(s.recovery))
            }

            HStack {
                Spacer()
                MetricRing(score: s.recovery, color: tint, lineWidth: 8, size: 72, fontSize: 24)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("恢复度")
                    .accessibilityValue("\(Int(s.recovery.rounded())) 分")
                Spacer()
            }
            .padding(.vertical, 4)

            VStack(spacing: 0) {
                compactContributionRow(
                    label: "HRV",
                    value: s.hrvScore * 0.40,
                    maxValue: 40,
                    color: .blue
                )
                Spacer(minLength: 6)
                compactContributionRow(
                    label: "睡眠",
                    value: s.sleepScore * 0.35,
                    maxValue: 35,
                    color: .purple
                )
                Spacer(minLength: 6)
                compactContributionRow(
                    label: "RHR",
                    value: s.rhrScore * 0.25,
                    maxValue: 25,
                    color: .pink
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: cardRadius))
    }

    private func compactContributionRow(
        label: String,
        value: Double,
        maxValue: Double,
        color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            ContributionBar(color: color, fraction: value / maxValue, height: 4)

            Text("\(Int(value.rounded()))")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.4), value: value)
                .frame(width: 18, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded()))，满分 \(Int(maxValue))")
    }

    private func scoreTint(_ score: Double) -> Color {
        switch score {
        case 85...:    return .green
        case 70..<85:  return .mint
        case 50..<70:  return .yellow
        case 30..<50:  return .orange
        default:       return .red
        }
    }

    private func recoveryLabel(_ score: Double) -> String {
        switch score {
        case 85...:    return "极佳"
        case 70..<85:  return "良好"
        case 50..<70:  return "一般"
        case 30..<50:  return "偏低"
        default:       return "很差"
        }
    }

    // MARK: - 分项评分卡片

    private func scoresCard(_ s: ReadinessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("分项评分")
                    .font(.headline)

                Button {
                    activeExplanation = MetricLibrary.subScores
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关于分项评分")

                Spacer()

                Button {
                    showSubScores = true
                } label: {
                    HStack(spacing: 2) {
                        Text("查看详情")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                scoreRingTile(
                    title: "HRV",
                    score: s.hrvScore,
                    detail: s.hrvBaseline > 0
                        ? "\(Int(s.hrvTrend)) / \(Int(s.hrvBaseline))"
                        : "无基线",
                    color: .blue,
                    explanation: MetricLibrary.hrv
                )
                scoreRingTile(
                    title: "睡眠",
                    score: s.sleepScore,
                    detail: "目标 8h",
                    color: .purple,
                    explanation: MetricLibrary.sleep
                )
                scoreRingTile(
                    title: "静息心率",
                    score: s.rhrScore,
                    detail: s.rhrBaseline > 0
                        ? "\(Int(s.rhrBaseline)) bpm"
                        : "无基线",
                    color: .pink,
                    explanation: MetricLibrary.rhr
                )
                scoreRingTile(
                    title: "TSB",
                    score: s.tsbScore,
                    detail: String(format: "%+.0f", s.tsb),
                    color: .orange,
                    explanation: MetricLibrary.tsb
                )
            }
        }
        .glassCard(cornerRadius: cardRadius)
    }

    private func scoreRingTile(
        title: String,
        score: Double,
        detail: String,
        color: Color,
        explanation: MetricExplanation
    ) -> some View {
        HStack(spacing: 10) {
            MetricRing(score: score, color: color, lineWidth: 5, size: 46, fontSize: 15)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                    Button {
                        activeExplanation = explanation
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关于 \(title)")
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.4), value: detail)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 运动建议卡片

    private func sportAdviceCard(_ s: ReadinessSnapshot) -> some View {
        let advice = SportAdviceEngine.advice(for: selectedSport, snapshot: s)
        return VStack(alignment: .leading, spacing: 12) {
            // 运动选择器
            GlassEffectContainer(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SportType.allCases) { sport in
                            sportChip(sport)
                        }
                    }
                }
            }

            Divider()

            // 建议内容
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(advice.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: advice.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(advice.color)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityDecorative()

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("\(selectedSport.displayName)建议")
                            .font(.headline)
                            .contentTransition(.interpolate)
                            .animation(.snappy(duration: 0.3), value: selectedSport)

                        Text(advice.tag)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(advice.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(advice.color.opacity(0.12), in: Capsule())
                            .contentTransition(.interpolate)
                            .animation(.snappy(duration: 0.3), value: advice.tag)
                    }

                    Text(advice.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .contentTransition(.interpolate)
                        .animation(.snappy(duration: 0.3), value: advice.title)

                    Text(advice.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                        .animation(.snappy(duration: 0.3), value: advice.detail)
                }
                Spacer(minLength: 0)
            }
        }
        .glassCard(cornerRadius: cardRadius)
        .animation(.snappy(duration: 0.3), value: selectedSport)
    }

    private func sportChip(_ sport: SportType) -> some View {
        let isSelected = sport == selectedSport
        return Button {
            withAnimation(.snappy(duration: 0.32)) {
                selectedSport = sport
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sport.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(sport.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.accentColor) : .regular, in: .capsule)
        .animation(.snappy(duration: 0.32), value: isSelected)
        .accessibilityLabel(sport.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 状态页

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在读取健康数据…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView(
            "无法读取数据",
            systemImage: "heart.slash",
            description: Text(message)
        )
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "暂无数据",
            systemImage: "waveform.path.ecg",
            description: Text("请先在健康 App 中授权数据访问")
        )
    }

    // MARK: - 状态色

    private func tsbColor(tsb: Double) -> Color {
        switch tsb {
        case 10...:        return .green
        case 0..<10:       return Color(red: 0.30, green: 0.75, blue: 0.50)
        case -10..<0:      return .orange
        case -30..<(-10):  return Color(red: 0.90, green: 0.45, blue: 0.20)
        default:           return .red
        }
    }

    private func atlColor(atl: Double, ctl: Double) -> Color {
        let diff = atl - ctl
        switch diff {
        case ..<(-5):       return .blue
        case -5..<5:        return .primary
        case 5..<15:        return .orange
        case 15..<30:       return Color(red: 0.90, green: 0.45, blue: 0.20)
        default:            return .red
        }
    }
}

// MARK: - 状态样式

struct StateStyle {
    let badge: String
    let subtitle: String
    let title: String
    let detail: String
    let icon: String
    let gradient: [Color]

    static func from(readiness: Double) -> StateStyle {
        switch readiness {
        case 85...:
            return StateStyle(
                badge: "巅峰",
                subtitle: "身体状态极佳，适合挑战",
                title: "状态极佳",
                detail: "适合安排高质量或高强度训练，可尝试突破或测试。",
                icon: "bolt.fill",
                gradient: [Color(red: 0.18, green: 0.80, blue: 0.44),
                           Color(red: 0.10, green: 0.65, blue: 0.55)]
            )
        case 70..<85:
            return StateStyle(
                badge: "良好",
                subtitle: "恢复充分，按计划执行",
                title: "状态良好",
                detail: "按计划执行训练即可，注意保持节奏。",
                icon: "checkmark.circle.fill",
                gradient: [Color(red: 0.20, green: 0.72, blue: 0.65),
                           Color(red: 0.16, green: 0.60, blue: 0.72)]
            )
        case 50..<70:
            return StateStyle(
                badge: "一般",
                subtitle: "适度训练，避免过量",
                title: "状态一般",
                detail: "建议降低强度或缩短时长，以有氧为主。",
                icon: "exclamationmark.triangle.fill",
                gradient: [Color(red: 0.96, green: 0.72, blue: 0.20),
                           Color(red: 0.92, green: 0.58, blue: 0.16)]
            )
        case 30..<50:
            return StateStyle(
                badge: "偏低",
                subtitle: "需要主动恢复",
                title: "需要恢复",
                detail: "安排主动恢复：散步、拉伸、轻松游泳。",
                icon: "arrow.down.circle.fill",
                gradient: [Color(red: 0.95, green: 0.50, blue: 0.25),
                           Color(red: 0.88, green: 0.36, blue: 0.24)]
            )
        default:
            return StateStyle(
                badge: "恢复优先",
                subtitle: "身体需要休息",
                title: "恢复优先",
                detail: "建议完全休息或极低强度活动，避免加量。",
                icon: "bed.double.fill",
                gradient: [Color(red: 0.90, green: 0.30, blue: 0.35),
                           Color(red: 0.75, green: 0.18, blue: 0.40)]
            )
        }
    }
}

#Preview {
    NavigationStack {
        BodyTabView(activationID: UUID())
    }
}
