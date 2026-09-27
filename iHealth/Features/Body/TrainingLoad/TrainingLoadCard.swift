//  TrainingLoadCard.swift
//  iHealth
//
//  职责：身体 Tab 最上方的「训练负荷」卡片。
//
//  · 一行三列：CTL / ATL / TSB
//  · 每个指标的 ⓘ 打开对应说明页
//  · 底部 TSB 状态刻度条 + 语义徽章
//  · 右上角「查看详情」→ TrainingLoadDetailView
//
//  只负责渲染，交互状态通过 Binding 向外层要。
import SwiftUI

struct TrainingLoadCard: View {
    let snapshot: ReadinessSnapshot
    @Binding var activeExplanation: MetricExplanation?
    @Binding var showDetail: Bool

    @Environment(\.cardCornerRadius) private var cardRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(spacing: 0) {
                HeroMetric(
                    title: "体能基础",
                    subtitle: "CTL",
                    value: String(format: "%.1f", snapshot.ctl),
                    color: .teal,
                    explanation: MetricLibrary.ctl,
                    activeExplanation: $activeExplanation
                )

                HeroDivider()

                HeroMetric(
                    title: "训练负荷",
                    subtitle: "ATL",
                    value: String(format: "%.1f", snapshot.atl),
                    color: CardStyle.atlColor(atl: snapshot.atl, ctl: snapshot.ctl),
                    explanation: MetricLibrary.atl,
                    activeExplanation: $activeExplanation
                )

                HeroDivider()

                HeroMetric(
                    title: "训练压力",
                    subtitle: "TSB",
                    value: String(format: "%+.1f", snapshot.tsb),
                    color: CardStyle.tsbColor(snapshot.tsb),
                    explanation: MetricLibrary.tsb,
                    activeExplanation: $activeExplanation
                )
            }

            TSBScaleBar(tsb: snapshot.tsb)
        }
        .glassCard(cornerRadius: cardRadius)
    }

    private var header: some View {
        HStack(spacing: 8) {
            // 状态指示点：外圈淡色 + 内圈实色
            ZStack {
                Circle()
                    .fill(CardStyle.tsbColor(snapshot.tsb).opacity(0.18))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(CardStyle.tsbColor(snapshot.tsb))
                    .frame(width: 8, height: 8)
            }
            .animation(.snappy(duration: 0.4), value: snapshot.tsb)
            .accessibilityDecorative()

            Text("训练负荷")
                .font(.headline)

            InfoButton(
                explanation: MetricLibrary.ctl,
                activeExplanation: $activeExplanation,
                size: 13
            )

            Spacer()

            ViewAllButton { showDetail = true }
        }
    }
}

// MARK: - TSB 状态刻度条

/// 横向刻度条：TSB ∈ [−40, +30]，7 段渐变色标出从「过度疲劳」到「训练不足」。
/// 指示圆点带同色光晕，顶部徽章实时显示当前语义。
private struct TSBScaleBar: View {
    let tsb: Double

    // 显示范围
    private let minTSB: Double = -40
    private let maxTSB: Double = 30

    // 尺寸
    private let barHeight: CGFloat = 10
    private let dotSize: CGFloat = 14

    private var totalRange: Double { maxTSB - minTSB }
    private var clampedTSB: Double { min(max(tsb, minTSB), maxTSB) }
    private var dotColor: Color { CardStyle.tsbColor(tsb) }

    /// 渐变的颜色停靠点（7 段）
    private var trackGradient: LinearGradient {
        let pts: [(Double, Color)] = [
            (-40, .red),
            (-30, Color(red: 0.90, green: 0.45, blue: 0.20)),
            (-20, .orange),
            (-10, .yellow),
            (  0, .mint),
            (  5, .green),
            ( 20, .green),
            ( 30, .blue)
        ]
        let stops = pts.map { value, color in
            Gradient.Stop(color: color, location: (value - minTSB) / totalRange)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// 当前 TSB 的语义标签
    private var zoneLabel: String {
        switch tsb {
        case 20...:        return "训练不足"
        case 5..<20:       return "理想竞技"
        case 0..<5:        return "正常训练"
        case -10..<0:      return "轻度负荷"
        case -20..<(-10):  return "训练负荷"
        case -30..<(-20):  return "高负荷"
        default:           return "过度疲劳"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            topRow
            track
            bottomLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("训练压力状态")
        .accessibilityValue("TSB \(String(format: "%+.1f", tsb))，\(zoneLabel)")
    }

    // MARK: 顶部：标题 + 状态徽章

    private var topRow: some View {
        HStack(spacing: 0) {
            Text("当前状态")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)

                Text(zoneLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(dotColor)
                    .contentTransition(.interpolate)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(dotColor.opacity(0.12), in: Capsule())
            .animation(.snappy(duration: 0.35), value: dotColor)
        }
    }

    // MARK: 轨道

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = dotSize * 1.9
            let half = dotSize / 2
            let ratio = CGFloat((clampedTSB - minTSB) / totalRange)
            let dotX = min(max(ratio * w, half), w - half)

            ZStack {
                // 渐变色带
                Capsule()
                    .fill(trackGradient)
                    .frame(height: barHeight)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )

                // 内部分隔刻度（−30 / −20 / −10 / 0 / +5 / +20）
                ForEach([-30.0, -20.0, -10.0, 0.0, 5.0, 20.0], id: \.self) { v in
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 1, height: barHeight * 0.7)
                        .offset(x: CGFloat((v - minTSB) / totalRange) * w - w / 2)
                }

                // 指示圆点
                ZStack {
                    // 同色光晕
                    Circle()
                        .fill(dotColor.opacity(0.25))
                        .frame(width: dotSize * 1.9, height: dotSize * 1.9)
                        .blur(radius: 4)

                    // 实心圆
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotSize, height: dotSize)
                        .overlay(
                            Circle().stroke(Color(.systemBackground), lineWidth: 2.5)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
                .offset(x: dotX - w / 2)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.78),
                    value: tsb
                )
            }
            .frame(width: w, height: h)
        }
        .frame(height: dotSize * 1.9)
    }

    // MARK: 底部轴标签

    private var bottomLabels: some View {
        HStack {
            Text("疲劳")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("平衡")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("恢复好")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
    }
}
