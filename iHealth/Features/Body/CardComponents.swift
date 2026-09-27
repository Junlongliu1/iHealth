//  CardComponents.swift
//  iHealth
//
//  职责：跨卡片复用的卡片积木。
//
//  · InfoButton             —— 标题旁 ⓘ，点击弹出说明页
//  · ViewAllButton          —— "查看详情 ›" 按钮
//  · HeroMetric             —— 训练负荷卡的大数字指标
//  · HeroDivider            —— HeroMetric 之间的竖线
//  · CompactContributionRow —— 小型贡献条（标签 + 条 + 数值）
//
//  这些组件只有尺寸差异、没有业务差异。

import SwiftUI

// MARK: - Info 按钮

/// 卡片标题旁的「关于 xxx」信息按钮
struct InfoButton: View {
    let explanation: MetricExplanation
    @Binding var activeExplanation: MetricExplanation?
    var size: CGFloat = 10

    var body: some View {
        Button {
            activeExplanation = explanation
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size))
                .foregroundStyle(.tertiary)
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关于 \(explanation.title)")
    }
}

// MARK: - 「查看详情」按钮

struct ViewAllButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
}

// MARK: - 训练负荷卡片用的 Hero 指标

struct HeroMetric: View {
    let title: String
    let subtitle: String
    let value: String
    let color: Color
    let explanation: MetricExplanation
    @Binding var activeExplanation: MetricExplanation?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                InfoButton(
                    explanation: explanation,
                    activeExplanation: $activeExplanation,
                    size: 10
                )
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
}

/// HeroMetric 之间的细分隔线
struct HeroDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 1, height: 36)
    }
}

// MARK: - 小型贡献度行

struct CompactContributionRow: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
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
}
