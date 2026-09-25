//
//  VitalsDetailView.swift
//  iHealth
//
//  生命体征详情页。
//  只展示「睡眠期间」采集到的数据。
//  使用固定的睡眠场景参考范围判断正常 / 异常。
//

import SwiftUI
import HealthKit
import Charts

// MARK: - 详情页

struct VitalsDetailView: View {
    @State private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var trends: [VitalKind: [VitalSample]] = [:]
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                dayNavigator

                if let banner = jointBanner {
                    jointWarning(banner)
                }

                if isLoading && trends.isEmpty {
                    ProgressView()
                        .padding(.top, 60)
                } else {
                    ForEach(VitalKind.allCases) { kind in
                        metricCard(for: kind)
                    }
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("生命体征")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTrends(for: currentDay) }
    }

    // MARK: - 日期导航条

    private var dayNavigator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button { shiftDay(by: -1) } label: {
                    navArrow(systemName: "chevron.left", enabled: true)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Text(dayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.interpolate)

                Spacer(minLength: 4)

                Button { shiftDay(by: 1) } label: {
                    navArrow(systemName: "chevron.right", enabled: canGoForward)
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.indigo)
                Text("仅睡眠期间数据 · 按睡眠参考范围判断")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    private func navArrow(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(enabled ? 0.06 : 0.03)))
            .contentShape(Circle())
    }

    // MARK: - 日期切换（先加载再原子更新，避免闪旧数据）

    private var canGoForward: Bool {
        Calendar.current.startOfDay(for: currentDay) < Calendar.current.startOfDay(for: Date())
    }

    private func shiftDay(by offset: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let newDay = calendar.date(byAdding: .day, value: offset, to: currentDay),
              newDay <= today else { return }

        Task {
            let data = await VitalsCalculator.shared.dayData(for: newDay)
            withAnimation(.smooth(duration: 0.22)) {
                currentDay = newDay
                trends = data.samples
            }
        }
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: currentDay)
        let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0

        switch diff {
        case 0: return "今天"
        case 1: return "昨天"
        case 2: return "前天"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEE"
            return f.string(from: day)
        }
    }

    // MARK: - 多指标联合观察

    private var jointBanner: [String]? {
        var abnormal: [String] = []
        for kind in VitalKind.allCases {
            guard let avg = (trends[kind] ?? []).averageValue else { continue }
            if !kind.normalRange.contains(avg) {
                abnormal.append(kind.shortName)
            }
        }
        return abnormal.count >= 2 ? abnormal : nil
    }

    @ViewBuilder
    private func jointWarning(_ names: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.pink)

            VStack(alignment: .leading, spacing: 3) {
                Text("多项指标超出参考范围")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(names.joined(separator: "、")) 不在睡眠参考范围内，建议留意。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.pink.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.pink.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - 指标卡片

    private func metricCard(for kind: VitalKind) -> some View {
        let samples = trends[kind] ?? []
        let average = samples.averageValue
        let current = samples.last?.value

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(kind.color)

                Text(kind.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                statusBadge(value: average, range: kind.normalRange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(format(average, decimals: kind.decimals))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(colorFor(value: average, range: kind.normalRange, baseColor: kind.color))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(kind.unitText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                if let current, let average,
                   samples.count >= 2,
                   abs(current - average) > 0.05 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("最新")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(format(current, decimals: kind.decimals))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }
            }

            baselineInfoRow(kind: kind)

            Group {
                if samples.count >= 2 {
                    chart(for: kind, samples: samples)
                } else if let sample = samples.first {
                    singleSampleView(for: kind, sample: sample, range: kind.normalRange)
                } else {
                    emptyChartView()
                }
            }
            .frame(height: 80)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - 参考范围说明行

    @ViewBuilder
    private func baselineInfoRow(kind: VitalKind) -> some View {
        let lo = formatShort(kind.normalRange.lowerBound, decimals: kind.decimals)
        let hi = formatShort(kind.normalRange.upperBound, decimals: kind.decimals)

        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "scope")
                    .font(.system(size: 8, weight: .semibold))
                Text("参考范围")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))

            Text("\(lo)–\(hi) \(kind.unitText) · \(kind.rangeHint)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)

            Spacer()
        }
    }

    // MARK: - 趋势图

    @ViewBuilder
    private func chart(for kind: VitalKind, samples: [VitalSample]) -> some View {
        let values = samples.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, kind.decimals > 0 ? 0.2 : 2)
        let yLo = lo - pad
        let yHi = hi + pad

        Chart(samples) { sample in
            AreaMark(
                x: .value("时间", sample.date),
                yStart: .value("底", yLo),
                yEnd: .value("顶", sample.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [kind.color.opacity(0.28), kind.color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("时间", sample.date),
                y: .value(kind.shortName, sample.value)
            )
            .foregroundStyle(kind.color)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .chartYScale(domain: yLo...yHi)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatShort(v, decimals: kind.decimals))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 单样本视图

    private func singleSampleView(
        for kind: VitalKind,
        sample: VitalSample,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(kind.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(kind.color)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.isSleepOnly ? "睡眠期间采样" : "单次采样")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(sample.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            Spacer()

            rangeIndicator(kind: kind, value: sample.value, range: range)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(kind.color.opacity(0.06))
        )
    }

    // MARK: - 空状态

    private func emptyChartView() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 18))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text("睡眠期间暂无数据")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("请佩戴 Apple Watch 入睡")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - 相对范围指示

    private func rangeIndicator(
        kind: VitalKind,
        value: Double,
        range: ClosedRange<Double>
    ) -> some View {
        let relation: (text: String, color: Color)
        if value < range.lowerBound {
            relation = ("偏低", .blue)
        } else if value > range.upperBound {
            relation = ("偏高", .pink)
        } else {
            let mid = (range.lowerBound + range.upperBound) / 2
            relation = value >= mid ? ("偏上", .green) : ("偏下", .green)
        }

        return HStack(spacing: 3) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 9, weight: .semibold))
            Text(relation.text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(relation.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(relation.color.opacity(0.12)))
    }

    // MARK: - 状态胶囊

    private func statusBadge(
        value: Double?,
        range: ClosedRange<Double>
    ) -> some View {
        let hasValue = value != nil
        let normal = value.map { range.contains($0) } ?? false

        let color: Color = hasValue ? (normal ? .green : .pink) : .secondary
        let text: String = hasValue ? (normal ? "正常" : "异常") : "无数据"

        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - 颜色 / 格式化

    private func colorFor(value: Double?, range: ClosedRange<Double>, baseColor: Color) -> Color {
        guard let value else { return .secondary.opacity(0.5) }
        return range.contains(value) ? baseColor : .pink
    }

    private func format(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "--" }
        return decimals > 0 ? String(format: "%.\(decimals)f", value) : "\(Int(value))"
    }

    private func formatShort(_ value: Double, decimals: Int) -> String {
        decimals > 0 ? String(format: "%.\(decimals)f", value) : "\(Int(value))"
    }

    // MARK: - 数据加载（统一走 VitalsCalculator）

    private func loadTrends(for day: Date) async {
        let data = await VitalsCalculator.shared.dayData(for: day)
        trends = data.samples
        isLoading = false
    }
}
