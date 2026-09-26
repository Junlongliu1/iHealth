//
//  SubScoresView.swift
//  iHealth
//

import SwiftUI

struct SubScoresView: View {
    let snapshot: ReadinessSnapshot?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let s = snapshot {
                    content(s)
                } else {
                    ContentUnavailableView(
                        "暂无数据",
                        systemImage: "waveform.path.ecg"
                    )
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("分项评分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func content(_ s: ReadinessSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard(s)
                detailCard(
                    icon: "waveform.path.ecg",
                    color: .blue,
                    title: "HRV",
                    subtitle: "自主神经恢复",
                    score: s.hrvScore,
                    weight: "40%",
                    detail: s.hrvBaseline > 0
                        ? "趋势 \(Int(s.hrvTrend)) / 基线 \(Int(s.hrvBaseline)) ms"
                        : "无基线数据"
                )
                detailCard(
                    icon: "moon.zzz.fill",
                    color: .purple,
                    title: "睡眠",
                    subtitle: "恢复基础",
                    score: s.sleepScore,
                    weight: "35%",
                    detail: "目标 8 小时"
                )
                detailCard(
                    icon: "heart.fill",
                    color: .pink,
                    title: "静息心率",
                    subtitle: "心血管负担",
                    score: s.rhrScore,
                    weight: "25%",
                    detail: s.rhrBaseline > 0
                        ? "14 天基线 \(Int(s.rhrBaseline)) bpm"
                        : "无基线数据"
                )
                contributionCard(s)
            }
            .padding(16)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 摘要

    private func summaryCard(_ s: ReadinessSnapshot) -> some View {
        let state = StateStyle.from(readiness: s.readiness)
        let tint = state.gradient.first ?? .gray
        return HStack(spacing: 16) {
            MetricRing(score: s.recovery, color: tint, lineWidth: 8, size: 86, fontSize: 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("恢复度")
                .accessibilityValue("\(Int(s.recovery.rounded())) 分")

            VStack(alignment: .leading, spacing: 4) {
                Text("恢复度由三个维度合成")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("HRV 40% · 睡眠 35% · RHR 25%\n并叠加一致性加成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 分项详情

    private func detailCard(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        score: Double,
        weight: String,
        detail: String
    ) -> some View {
        HStack(spacing: 14) {
            MetricRing(score: score, color: color, lineWidth: 6, size: 56, fontSize: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                        .accessibilityDecorative()
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(weight)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.12), in: Capsule())
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 16, padding: 14)
    }

    // MARK: - 对恢复度的贡献

    private func contributionCard(_ s: ReadinessSnapshot) -> some View {
        let hrvContrib   = s.hrvScore * 0.40
        let sleepContrib = s.sleepScore * 0.35
        let rhrContrib   = s.rhrScore * 0.25

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("对恢复度的贡献")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("合计 \(Int(s.recovery.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            contributionRow(color: .blue,   label: "HRV",    value: hrvContrib,   maxValue: 40)
            contributionRow(color: .purple, label: "睡眠",   value: sleepContrib, maxValue: 35)
            contributionRow(color: .pink,   label: "静息心率", value: rhrContrib,  maxValue: 25)

            Divider().padding(.vertical, 2)

            HStack {
                Text("原始合成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", hrvContrib + sleepContrib + rhrContrib))
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            HStack {
                Text("一致性加成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let bonus = s.recovery - (hrvContrib + sleepContrib + rhrContrib)
                Text(String(format: "%+.1f", bonus))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(bonus >= 0 ? .green : .red)
                    .monospacedDigit()
            }
        }
        .glassCard(cornerRadius: 16)
    }

    private func contributionRow(color: Color, label: String, value: Double, maxValue: Double) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            ContributionBar(color: color, fraction: value / maxValue, height: 5)

            Text(String(format: "%.1f / %.0f", value, maxValue))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.1f，满分 %.0f", value, maxValue))
    }
}
