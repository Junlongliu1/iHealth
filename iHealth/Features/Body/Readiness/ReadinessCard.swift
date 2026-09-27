//  ReadinessCard.swift
//  iHealth
//
//  职责：身体 Tab 中部左侧的「准备度」卡片。
//
//  · 顶部：标题 + ⓘ + 状态徽章（来自 StateStyle）
//  · 中部：MetricRing 显示准备度分数
//  · 底部：两条贡献条 —— 恢复度 × 70%、TSB分 × 30%
//
//  整卡可点，打开 SubScoresView（分项评分）。

import SwiftUI

struct ReadinessCard: View {
    let snapshot: ReadinessSnapshot
    @Binding var activeExplanation: MetricExplanation?
    @Binding var showDetail: Bool

    @Environment(\.cardCornerRadius) private var cardRadius

    private var state: StateStyle {
        StateStyle.from(readiness: snapshot.readiness)
    }

    private var tint: Color {
        CardStyle.scoreTint(snapshot.readiness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack {
                Spacer()
                MetricRing(
                    score: snapshot.readiness,
                    color: tint,
                    lineWidth: 8,
                    size: 72,
                    fontSize: 24
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("准备度")
                .accessibilityValue("\(Int(snapshot.readiness.rounded())) 分")
                Spacer()
            }
            .padding(.vertical, 4)

            VStack(spacing: 0) {
                CompactContributionRow(
                    label: "恢复",
                    value: snapshot.recovery * 0.70,
                    maxValue: 70,
                    color: .blue
                )
                Spacer(minLength: 6)
                CompactContributionRow(
                    label: "TSB",
                    value: snapshot.tsbScore * 0.30,
                    maxValue: 30,
                    color: .orange
                )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 先裁剪内容，再绘制玻璃背景：让卡片圆角成为硬边界
        .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: cardRadius))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("准备度")
                .font(.subheadline)
                .fontWeight(.semibold)

            InfoButton(
                explanation: MetricLibrary.readiness,
                activeExplanation: $activeExplanation,
                size: 10
            )

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
    }
}
