//  SubScoresCard.swift
//  iHealth
//
//  职责：身体 Tab 的「分项评分」卡片。
//
//  · 2×2 网格展示 HRV / 睡眠 / RHR / TSB 四个分项
//  · 每格：小环 + 标题 + 次要信息（趋势 / 目标 / 基线）
//  · 右上角「查看详情」→ SubScoresView
//
//  内部 ScoreRingTile 私有，仅本文件使用。
import SwiftUI

struct SubScoresCard: View {
    let snapshot: ReadinessSnapshot
    @Binding var activeExplanation: MetricExplanation?
    @Binding var showDetail: Bool

    @Environment(\.cardCornerRadius) private var cardRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ScoreRingTile(
                    title: "HRV",
                    score: snapshot.hrvScore,
                    detail: snapshot.hrvBaseline > 0
                        ? "\(Int(snapshot.hrvTrend)) / \(Int(snapshot.hrvBaseline))"
                        : "无基线",
                    color: .blue,
                    explanation: MetricLibrary.hrv,
                    activeExplanation: $activeExplanation
                )
                ScoreRingTile(
                    title: "睡眠",
                    score: snapshot.sleepScore,
                    detail: "目标 8h",
                    color: .purple,
                    explanation: MetricLibrary.sleep,
                    activeExplanation: $activeExplanation
                )
                ScoreRingTile(
                    title: "静息心率",
                    score: snapshot.rhrScore,
                    detail: snapshot.rhrBaseline > 0
                        ? "\(Int(snapshot.rhrBaseline)) bpm"
                        : "无基线",
                    color: .pink,
                    explanation: MetricLibrary.rhr,
                    activeExplanation: $activeExplanation
                )
                ScoreRingTile(
                    title: "TSB",
                    score: snapshot.tsbScore,
                    detail: String(format: "%+.0f", snapshot.tsb),
                    color: .orange,
                    explanation: MetricLibrary.tsb,
                    activeExplanation: $activeExplanation
                )
            }
        }
        .glassCard(cornerRadius: cardRadius)
    }

    private var header: some View {
        HStack {
            Text("分项评分")
                .font(.headline)

            InfoButton(
                explanation: MetricLibrary.subScores,
                activeExplanation: $activeExplanation,
                size: 13
            )

            Spacer()

            ViewAllButton { showDetail = true }
        }
    }
}

// MARK: - 单个环形瓦片

private struct ScoreRingTile: View {
    let title: String
    let score: Double
    let detail: String
    let color: Color
    let explanation: MetricExplanation
    @Binding var activeExplanation: MetricExplanation?

    var body: some View {
        HStack(spacing: 10) {
            MetricRing(score: score, color: color, lineWidth: 5, size: 46, fontSize: 15)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)

                    InfoButton(
                        explanation: explanation,
                        activeExplanation: $activeExplanation,
                        size: 9
                    )
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
        .background(
            color.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
