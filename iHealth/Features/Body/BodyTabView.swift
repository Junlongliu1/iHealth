//
//  BodyTabView.swift
//  iHealth
//

import SwiftUI

struct BodyTabView: View {
    @State private var store = BodyMetricsStore.shared
    @State private var profile = AthleteProfileStore.shared
    @State private var activeExplanation: MetricExplanation?
    @State private var showSubScores = false
    @State private var showTrainingLoad = false
    @State private var selectedSport: SportType = .running

    var body: some View {
        Group {
            if store.isLoading {
                loadingView
            } else if let error = store.loadError, store.history.isEmpty {
                errorView(error)
            } else if let s = store.todaySnapshot {
                content(s)
            } else {
                emptyView
            }
        }
        .navigationTitle("身体")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AthleteProfileView()
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17, weight: .medium))
                }
            }

            if store.isSyncing {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task {
            await store.load()
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

    // MARK: - 主内容

    private func content(_ s: ReadinessSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                trainingLoadCard(s)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    readinessCard(s)
                    recoveryCard(s)
                }

                scoresCard(s)
                sportAdviceCard(s)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await store.refresh()
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
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
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
                }
                .buttonStyle(.plain)

                Spacer()

                Text(state.badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: Capsule())
            }

            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(s.readiness / 100, 1)))
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: s.readiness)

                    Text("\(Int(s.readiness.rounded()))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(width: 72, height: 72)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                }
                .buttonStyle(.plain)

                Spacer()

                Text(recoveryLabel(s.recovery))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.12), in: Capsule())
            }

            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(s.recovery / 100, 1)))
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: s.recovery)

                    Text("\(Int(s.recovery.rounded()))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(width: 72, height: 72)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * max(0.02, min(value / maxValue, 1)))
                }
            }
            .frame(height: 4)

            Text("\(Int(value.rounded()))")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 18, alignment: .trailing)
        }
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
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scoreRingTile(
        title: String,
        score: Double,
        detail: String,
        color: Color,
        explanation: MetricExplanation
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.02, min(score / 100, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: score)

                Text("\(Int(score.rounded()))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .frame(width: 46, height: 46)

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
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 运动建议卡片（多运动）

    private func sportAdviceCard(_ s: ReadinessSnapshot) -> some View {
        let advice = SportAdviceEngine.advice(for: selectedSport, snapshot: s)
        return VStack(alignment: .leading, spacing: 12) {
            // 运动选择器
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SportType.allCases) { sport in
                        sportChip(sport)
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
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("\(selectedSport.displayName)建议")
                            .font(.headline)

                        Text(advice.tag)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(advice.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(advice.color.opacity(0.12), in: Capsule())
                    }

                    Text(advice.title)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(advice.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sportChip(_ sport: SportType) -> some View {
        let isSelected = sport == selectedSport
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSport = sport
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sport.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(sport.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - 辅助

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
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

// MARK: - 运动建议引擎

enum SportAdviceLevel {
    case rest       // 休息
    case easy       // 轻松
    case moderate   // 中等
    case hard       // 高强度
}

struct SportAdvice {
    let tag: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

enum SportAdviceEngine {

    static func advice(for sport: SportType, snapshot s: ReadinessSnapshot) -> SportAdvice {
        let level = level(for: s)
        return advice(for: sport, level: level, snapshot: s)
    }

    // 根据准备度和 TSB 确定强度等级
    private static func level(for s: ReadinessSnapshot) -> SportAdviceLevel {
        if s.tsb < -30 { return .rest }
        if s.readiness >= 85 && s.tsb >= -10 { return .hard }
        if s.readiness >= 70 && s.tsb >= -20 { return .moderate }
        if s.readiness >= 50 && s.tsb >= -30 { return .easy }
        return .rest
    }

    private static func advice(
        for sport: SportType,
        level: SportAdviceLevel,
        snapshot s: ReadinessSnapshot
    ) -> SportAdvice {
        let readiness = Int(s.readiness.rounded())
        let tsb = String(format: "%+.0f", s.tsb)

        switch sport {
        case .running:
            return runningAdvice(level: level, readiness: readiness, tsb: tsb)
        case .walking:
            return walkingAdvice(level: level, readiness: readiness, tsb: tsb)
        case .badminton:
            return badmintonAdvice(level: level, readiness: readiness, tsb: tsb)
        case .hiking:
            return hikingAdvice(level: level, readiness: readiness, tsb: tsb)
        case .mountaineering:
            return mountaineeringAdvice(level: level, readiness: readiness, tsb: tsb)
        case .cycling:
            return cyclingAdvice(level: level, readiness: readiness, tsb: tsb)
        case .other:
            return genericAdvice(level: level, readiness: readiness, tsb: tsb)
        }
    }

    // MARK: - 跑步

    private static func runningAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议跑步",
                detail: "准备度 \(readiness)，TSB \(tsb)。建议完全休息，或只做散步和拉伸。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松跑 30–45 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。以轻松配速跑 30–45 分钟，心率控制在有氧区间。",
                icon: "figure.run",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "节奏跑或有氧跑",
                detail: "准备度 \(readiness)，TSB \(tsb)。可跑 30–50 分钟节奏跑，配速接近阈值。",
                icon: "figure.run",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "间歇跑或节奏跑",
                detail: "准备度 \(readiness)，TSB \(tsb)。可安排 4–6 组 800m–1km 间歇，或 20–30 分钟阈值跑。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 步行

    private static func walkingAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "轻松散步",
                detail: "准备度 \(readiness)，TSB \(tsb)。可慢走 15–20 分钟，避免长时间或快走。",
                icon: "figure.walk",
                color: .orange
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "日常步行 30–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。保持正常步速，心率控制在低有氧区间。",
                icon: "figure.walk",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "快走 40–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。可加速到微喘但能对话的程度，保持 40–60 分钟。",
                icon: "figure.walk",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "坡度快走或长距离步行",
                detail: "准备度 \(readiness)，TSB \(tsb)。可安排 60 分钟以上的快走，加入坡度或间歇加速段。",
                icon: "figure.walk",
                color: .green
            )
        }
    }

    // MARK: - 羽毛球

    private static func badmintonAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议高强度对抗",
                detail: "准备度 \(readiness)，TSB \(tsb)。可做轻松挥拍或技术练习，避免比赛。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松对打 30–45 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。以技术练习和轻松对打为主，避免全力扣杀。",
                icon: "figure.badminton",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "常规对抗 45–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。可进行常规双打或强度适中的单打，注意补水。",
                icon: "figure.badminton",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "高强度比赛或训练",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合正式比赛或高强度单打，赛前充分热身。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 徒步

    private static func hikingAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议徒步",
                detail: "准备度 \(readiness)，TSB \(tsb)。身体需要恢复，建议改做轻松散步。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "短途平缓徒步",
                detail: "准备度 \(readiness)，TSB \(tsb)。可走 1–2 小时平缓路线，爬升控制在 200m 内。",
                icon: "figure.hiking",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "中等徒步 2–4 小时",
                detail: "准备度 \(readiness)，TSB \(tsb)。可走 2–4 小时，爬升 300–600m，注意节奏。",
                icon: "figure.hiking",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "长距离或大爬升徒步",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合 4 小时以上或爬升 600m+ 的路线，补给要跟上。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 登山

    private static func mountaineeringAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。登山对体能要求高，建议改期或改做轻松活动。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "低强度短途登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。选择难度较低、爬升 300m 内的路线，控制时间在 2–3 小时。",
                icon: "mountain.2.fill",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "中等强度登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。可挑战爬升 600–1000m 的路线，注意配速和补水。",
                icon: "mountain.2.fill",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "高强度登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合长距离、大爬升或技术性路线，需充分准备装备和补给。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 骑行

    private static func cyclingAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议骑行",
                detail: "准备度 \(readiness)，TSB \(tsb)。建议完全休息，或只做非常轻松的活动。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松骑行 45–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。保持有氧区间，避免爬坡或冲刺。",
                icon: "figure.outdoor.cycle",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "节奏骑行 60–90 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。可进行 60–90 分钟稳定节奏骑行，接近阈值强度。",
                icon: "figure.outdoor.cycle",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "间歇或阈值骑行",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合 FTP 间歇或长距离高强度骑行。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 其他

    private static func genericAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "建议休息",
                detail: "准备度 \(readiness)，TSB \(tsb)。身体需要恢复，建议改做轻松活动。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松活动 30–45 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。以轻松强度进行，注意控制时长。",
                icon: "figure.mixed.cardio",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "中等强度训练",
                detail: "准备度 \(readiness)，TSB \(tsb)。可按计划进行中等强度训练。",
                icon: "figure.mixed.cardio",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "适合高强度训练",
                detail: "准备度 \(readiness)，TSB \(tsb)。状态良好，可进行高强度训练或测试。",
                icon: "bolt.fill",
                color: .green
            )
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
        BodyTabView()
    }
}
