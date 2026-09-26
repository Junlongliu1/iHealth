//
//  TrainingLoadDetailView.swift
//  iHealth
//

import SwiftUI

struct TrainingLoadDetailView: View {
    let snapshot: ReadinessSnapshot?
    let previousSnapshot: ReadinessSnapshot?
    let todayTSS: Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let s = snapshot {
                    content(s)
                } else {
                    ContentUnavailableView(
                        "暂无数据",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("训练负荷详情")
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
                ctlCard(s)
                atlCard(s)
                tsbCard(s)
            }
            .padding(16)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 摘要

    private func summaryCard(_ s: ReadinessSnapshot) -> some View {
        HStack(spacing: 0) {
            summaryItem(
                title: "体能基础",
                subtitle: "CTL",
                value: String(format: "%.1f", s.ctl),
                color: .teal
            )
            Divider().frame(height: 40)
            summaryItem(
                title: "训练负荷",
                subtitle: "ATL",
                value: String(format: "%.1f", s.atl),
                color: .orange
            )
            Divider().frame(height: 40)
            summaryItem(
                title: "训练压力",
                subtitle: "TSB",
                value: String(format: "%+.1f", s.tsb),
                color: s.tsb >= 0 ? .green : .red
            )
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func summaryItem(
        title: String,
        subtitle: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - CTL 计算

    private func ctlCard(_ s: ReadinessSnapshot) -> some View {
        calcCard(
            icon: "chart.line.uptrend.xyaxis",
            color: .teal,
            title: "体能基础 CTL",
            formula: "CTL今日 = CTL昨日 + (今日TSS − CTL昨日) ÷ 42",
            steps: [
                ("昨日 CTL", String(format: "%.1f", prevCTL)),
                ("今日 TSS", String(format: "%.1f", todayTSS)),
                ("差值", String(format: "%.1f", todayTSS - prevCTL)),
                ("差值 ÷ 42", String(format: "%.2f", (todayTSS - prevCTL) / 42))
            ],
            result: String(format: "%.1f", s.ctl),
            note: "以 42 天为窗口的指数加权移动平均，反映长期训练积累的体能基础。"
        )
    }

    // MARK: - ATL 计算

    private func atlCard(_ s: ReadinessSnapshot) -> some View {
        calcCard(
            icon: "chart.line.flattrend.down",
            color: .orange,
            title: "训练负荷 ATL",
            formula: "ATL今日 = ATL昨日 + (今日TSS − ATL昨日) ÷ 7",
            steps: [
                ("昨日 ATL", String(format: "%.1f", prevATL)),
                ("今日 TSS", String(format: "%.1f", todayTSS)),
                ("差值", String(format: "%.1f", todayTSS - prevATL)),
                ("差值 ÷ 7", String(format: "%.2f", (todayTSS - prevATL) / 7))
            ],
            result: String(format: "%.1f", s.atl),
            note: "以 7 天为窗口的指数加权移动平均，反映近期训练带来的疲劳。"
        )
    }

    // MARK: - TSB 计算

    private func tsbCard(_ s: ReadinessSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.caption)
                    .foregroundStyle(s.tsb >= 0 ? .green : .red)
                Text("训练压力 TSB")
                    .font(.headline)
            }

            Text("TSB = CTL − ATL")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 6) {
                calcRow(label: "CTL", value: String(format: "%.1f", s.ctl))
                calcRow(label: "ATL", value: String(format: "%.1f", s.atl))
                Divider().padding(.vertical, 2)
                calcRow(
                    label: "TSB",
                    value: String(format: "%+.1f", s.tsb),
                    emphasized: true,
                    color: s.tsb >= 0 ? .green : .red
                )
            }

            Text(tsbInterpretation(s.tsb))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 通用计算卡片

    private func calcCard(
        icon: String,
        color: Color,
        title: String,
        formula: String,
        steps: [(String, String)],
        result: String,
        note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }

            Text(formula)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 6) {
                ForEach(steps, id: \.0) { step in
                    calcRow(label: step.0, value: step.1)
                }
                Divider().padding(.vertical, 2)
                calcRow(label: "结果", value: result, emphasized: true, color: color)
            }

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func calcRow(
        label: String,
        value: String,
        emphasized: Bool = false,
        color: Color = .primary
    ) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .subheadline : .caption)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(emphasized ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(emphasized
                      ? .system(size: 16, weight: .bold, design: .rounded)
                      : .system(size: 13, design: .monospaced))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    // MARK: - 辅助

    private var prevCTL: Double {
        previousSnapshot?.ctl ?? 40.0
    }

    private var prevATL: Double {
        previousSnapshot?.atl ?? 40.0
    }

    private func tsbInterpretation(_ tsb: Double) -> String {
        switch tsb {
        case 10...:
            return "TSB ≥ +10：非常新鲜，可能训练不足。"
        case 0..<10:
            return "TSB 0 到 +10：新鲜，适合高质量训练。"
        case -10..<0:
            return "TSB −10 到 0：中性，正常训练区。"
        case -30..<(-10):
            return "TSB −10 到 −30：有目的的训练负荷区。"
        default:
            return "TSB < −30：过度负荷，需要恢复。"
        }
    }
}
