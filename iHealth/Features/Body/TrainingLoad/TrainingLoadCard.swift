//  TrainingLoadCard.swift
//  iHealth
//
//  职责：身体 Tab 最上方的「训练负荷」卡片。
//
//  · 一行三列：CTL / ATL / TSB
//  · 每个指标的 ⓘ 打开对应说明页
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
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
            .padding(.top, 4)
        }
        .glassCard(cornerRadius: cardRadius)
    }
}
