//  RecoveryCard.swift
//  iHealth
//
//  职责：身体 Tab 中部右侧的「恢复度」卡片。
//
//  · 顶部：标题 + ⓘ + 分数标签
//  · 中部：MetricRing 显示恢复度分数
//  · 底部：三条贡献条 —— HRV × 40%、睡眠 × 35%、
//           RHR × 25%
//
//  与 ReadinessCard 并排组成 2 列网格，结构同构。

import SwiftUI

struct RecoveryCard: View {
    let snapshot: ReadinessSnapshot
    @Binding var activeExplanation: MetricExplanation?

    @Environment(\.cardCornerRadius) private var cardRadius

    private var tint: Color {
        CardStyle.scoreTint(snapshot.recovery)
    }

    private var label: String {
        CardStyle.recoveryLabel(snapshot.recovery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack {
                Spacer()
                MetricRing(
                    score: snapshot.recovery,
                    color: tint,
                    lineWidth: 8,
                    size: 72,
                    fontSize: 24
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("恢复度")
                .accessibilityValue("\(Int(snapshot.recovery.rounded())) 分")
                Spacer()
            }
            .padding(.vertical, 4)

            VStack(spacing: 0) {
                CompactContributionRow(
                    label: "HRV",
                    value: snapshot.hrvScore * 0.40,
                    maxValue: 40,
                    color: .blue
                )
                Spacer(minLength: 6)
                CompactContributionRow(
                    label: "睡眠",
                    value: snapshot.sleepScore * 0.35,
                    maxValue: 35,
                    color: .purple
                )
                Spacer(minLength: 6)
                CompactContributionRow(
                    label: "RHR",
                    value: snapshot.rhrScore * 0.25,
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

    private var header: some View {
        HStack(spacing: 4) {
            Text("恢复度")
                .font(.subheadline)
                .fontWeight(.semibold)

            InfoButton(
                explanation: MetricLibrary.recovery,
                activeExplanation: $activeExplanation,
                size: 10
            )

            Spacer()

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.12), in: Capsule())
                .contentTransition(.interpolate)
                .animation(.snappy(duration: 0.35), value: label)
        }
    }
}
