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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最大摄氧量")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                if let level = info.classification {
                    Text(level.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(level.color.opacity(0.12)))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", info.value))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                    .monospacedDigit()

                Text("ml/(kg·min)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                if let text = deltaText {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isPositive ? Color.green : Color.red)
                        Text(text)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(isPositive ? Color.green : Color.red)
                            .monospacedDigit()
                    }
                }
            }

            // ★ 区间指示条
            if let thresholds = info.thresholds {
                VO2RangeBar(
                    value: info.value,
                    thresholds: thresholds,
                    classification: info.classification
                )
            }

            HStack(spacing: 8) {
                if deltaText != nil {
                    Text("较上次")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }

                Spacer()

                Button {
                    showDetail = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("了解分级")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
        .sheet(isPresented: $showDetail) {
            VO2MaxDetailSheet(info: info)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - 区间指示条

private struct VO2RangeBar: View {
    let value: Double
    let thresholds: VO2MaxThresholds
    let classification: VO2MaxClassification?

    /// 展示范围：low 下限往下留一点，high 上限往上留一点
    private var displayRange: (min: Double, max: Double) {
        let low = max(0, thresholds.low - 8)
        let high = thresholds.high + 8
        return (low, high)
    }

    private func ratio(_ v: Double) -> Double {
        let r = displayRange
        guard r.max > r.min else { return 0.5 }
        let x = (v - r.min) / (r.max - r.min)
        return min(max(x, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .leading) {
                    // 四段色条
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.red.opacity(0.75))
                            .frame(width: w * CGFloat(
                                (thresholds.low - displayRange.min) /
                                (displayRange.max - displayRange.min)
                            ))
                        Rectangle()
                            .fill(Color.orange.opacity(0.75))
                            .frame(width: w * CGFloat(
                                (thresholds.belowAvg - thresholds.low) /
                                (displayRange.max - displayRange.min)
                            ))
                        Rectangle()
                            .fill(Color.green.opacity(0.75))
                            .frame(width: w * CGFloat(
                                (thresholds.high - thresholds.belowAvg) /
                                (displayRange.max - displayRange.min)
                            ))
                        Rectangle()
                            .fill(Color.blue.opacity(0.75))
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())

                    // 当前值标记
                    let x = w * CGFloat(ratio(value))
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.20), radius: 2, y: 1)
                        .offset(x: x - 7)
                }
                .frame(height: 14)
            }
            .frame(height: 14)

            // 刻度标注
            HStack {
                Text("\(Int(displayRange.min))")
                Spacer()
                Text("\(Int(thresholds.low))")
                Spacer()
                Text("\(Int(thresholds.belowAvg))")
                Spacer()
                Text("\(Int(thresholds.high))")
                Spacer()
                Text("\(Int(displayRange.max))")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .monospacedDigit()
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

                    currentStatusSection

                    if let thresholds = info.thresholds,
                       let age = info.age,
                       let sex = info.sex {
                        standardsSection(thresholds: thresholds,
                                         age: age,
                                         sex: sex)
                    } else {
                        noProfileSection
                    }

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
