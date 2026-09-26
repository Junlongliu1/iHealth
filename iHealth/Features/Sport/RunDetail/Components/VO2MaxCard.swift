//
//  VO2MaxCard.swift
//  iHealth
//

import SwiftUI
import HealthKit

// MARK: - 最大摄氧量卡片

struct VO2MaxCard: View {
    let info: VO2MaxInfo

    @State private var showDetail = false

    private var deltaText: String? {
        guard let delta = info.delta, abs(delta) > 0.001 else { return nil }
        return String(format: "%+.2f", delta)
    }

    private var isPositive: Bool { (info.delta ?? 0) >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最大摄氧量")
                .font(.system(size: 16, weight: .semibold))

            HStack(alignment: .center, spacing: 8) {
                Text(String(format: "%.2f", info.value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                    .monospacedDigit()

                Spacer(minLength: 8)

                if let text = deltaText {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(text)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(isPositive ? Color.green : Color.red)
                            .monospacedDigit()
                        Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isPositive ? Color.green : Color.red)
                        Button {
                            showDetail = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                if let level = info.classification {
                    Text(level.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(level.color.opacity(0.12))
                        )
                }

                if deltaText != nil {
                    Text("较上次")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .sheet(isPresented: $showDetail) {
            VO2MaxDetailSheet(info: info)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - VO2 Max 详情弹窗

private struct VO2MaxDetailSheet: View {
    let info: VO2MaxInfo

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ① 当前状态
                    currentStatusSection

                    // ② 年龄段标准
                    if let thresholds = info.thresholds,
                       let age = info.age,
                       let sex = info.sex {
                        standardsSection(thresholds: thresholds,
                                         age: age,
                                         sex: sex)
                    } else {
                        noProfileSection
                    }

                    // ③ 对比记录
                    if let prev = info.previousValue {
                        comparisonSection(previous: prev)
                    } else {
                        noHistorySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("最大摄氧量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: ① 当前状态

    private var currentStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前状态")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", info.value))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                    .monospacedDigit()

                Text("ml/(kg·min)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer()

                if let level = info.classification {
                    Text(level.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(level.color.opacity(0.15)))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: ② 年龄段标准

    private func standardsSection(
        thresholds: VO2MaxThresholds,
        age: Int,
        sex: HKBiologicalSex
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("年龄段标准")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(age) 岁 · \(sexLabel(sex))")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(ranges(thresholds).enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item.level.color)
                            .frame(width: 8, height: 8)

                        Text(item.level.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(item.isCurrent ? item.level.color : .primary)

                        Spacer()

                        Text(item.range)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(item.isCurrent ? item.level.color : .secondary)
                            .monospacedDigit()

                        if item.isCurrent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(item.level.color)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        item.isCurrent
                            ? item.level.color.opacity(0.10)
                            : (idx % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private struct RangeItem {
        let level: VO2MaxClassification
        let range: String
        let isCurrent: Bool
    }

    private func ranges(_ t: VO2MaxThresholds) -> [RangeItem] {
        let current = info.classification
        return [
            RangeItem(level: .low,
                      range: "< \(Int(t.low))",
                      isCurrent: current == .low),
            RangeItem(level: .belowAverage,
                      range: "\(Int(t.low)) – \(Int(t.belowAvg) - 1)",
                      isCurrent: current == .belowAverage),
            RangeItem(level: .aboveAverage,
                      range: "\(Int(t.belowAvg)) – \(Int(t.high) - 1)",
                      isCurrent: current == .aboveAverage),
            RangeItem(level: .high,
                      range: "≥ \(Int(t.high))",
                      isCurrent: current == .high)
        ]
    }

    private func sexLabel(_ sex: HKBiologicalSex) -> String {
        switch sex {
        case .male:   return "男"
        case .female: return "女"
        default:      return "—"
        }
    }

    // MARK: 无用户资料

    private var noProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("年龄段标准")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("请在「健康」App 中设置出生日期和生物性别，以显示年龄分组标准")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: ③ 对比记录

    private func comparisonSection(previous: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("对比记录")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                comparisonCell(
                    title: "上次",
                    value: String(format: "%.2f", previous),
                    color: .secondary
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)

                comparisonCell(
                    title: "本次",
                    value: String(format: "%.2f", info.value),
                    color: Color(red: 0.20, green: 0.55, blue: 0.95)
                )

                Spacer()

                if let delta = info.delta {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.2f", abs(delta)))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(delta >= 0 ? Color.green : Color.red)

                        Text("变化")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonCell(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private var noHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("对比记录")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("暂无历史记录可供对比")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}
