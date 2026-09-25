//
//  SleepSummaryView.swift
//  iHealth
//
//  睡眠数据汇总视图。
//  顶部：总睡眠时长（大字）
//  中部：入睡 / 醒来 时间 + 睡眠阶段图
//  底部：深睡/浅睡/眼动/清醒 四项统计
//

import SwiftUI
import HealthKit

// MARK: - 睡眠阶段汇总

struct SleepSummary {
    let total: TimeInterval
    let deep: TimeInterval
    let core: TimeInterval
    let rem: TimeInterval
    let unspecified: TimeInterval
    let awake: TimeInterval

    let sleepStart: Date?
    let sleepEnd: Date?

    init(samples: [HKCategorySample]) {
        var deep: TimeInterval = 0
        var core: TimeInterval = 0
        var rem: TimeInterval = 0
        var unspecified: TimeInterval = 0
        var awake: TimeInterval = 0

        var firstStart: Date?
        var lastEnd: Date?

        for s in samples {
            let d = s.endDate.timeIntervalSince(s.startDate)
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepDeep:        deep += d
            case .asleepCore:        core += d
            case .asleepREM:         rem += d
            case .asleepUnspecified: unspecified += d
            case .awake:             awake += d
            default:                 break
            }

            if let v = HKCategoryValueSleepAnalysis(rawValue: s.value),
               v != .awake, v != .inBed {
                if firstStart == nil || s.startDate < firstStart! {
                    firstStart = s.startDate
                }
                if lastEnd == nil || s.endDate > lastEnd! {
                    lastEnd = s.endDate
                }
            }
        }

        self.deep = deep
        self.core = core
        self.rem = rem
        self.unspecified = unspecified
        self.awake = awake
        self.total = deep + core + rem + unspecified
        self.sleepStart = firstStart
        self.sleepEnd = lastEnd
    }
}

// MARK: - 睡眠汇总视图

struct SleepSummaryView: View {
    let samples: [HKCategorySample]

    private var summary: SleepSummary { SleepSummary(samples: samples) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 总睡眠时长
            VStack(alignment: .leading, spacing: 2) {
                Text("睡眠时间")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text(formatHourMinute(summary.total))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            // 入睡 / 醒来 + 阶段图
            VStack(alignment: .leading, spacing: 6) {
                sleepTimeRow

                SleepChartView(samples: samples)
                    .frame(height: 120)   // 更紧凑
            }

            // 四项阶段统计
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                SleepStageItem(label: "深睡", duration: summary.deep,  color: .indigo)
                SleepStageItem(label: "浅睡", duration: summary.core,  color: .blue)
                SleepStageItem(label: "眼动", duration: summary.rem,   color: .cyan)
                SleepStageItem(label: "清醒", duration: summary.awake, color: .orange)
            }
        }
    }

    // MARK: - 入睡 / 醒来 时间行

    @ViewBuilder
    private var sleepTimeRow: some View {
        if let start = summary.sleepStart, let end = summary.sleepEnd {
            HStack(spacing: 6) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.indigo)

                Text(start, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Spacer(minLength: 4)

                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(end, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }

    private func formatHourMinute(_ t: TimeInterval) -> String {
        guard t > 0 else { return "0分" }
        let totalMinutes = Int(t / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes)分"
    }
}

// MARK: - 单个阶段统计项

struct SleepStageItem: View {
    let label: String
    let duration: TimeInterval
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Text(format(duration))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func format(_ t: TimeInterval) -> String {
        guard t > 0 else { return "0分" }
        let totalMinutes = Int(t / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)时\(minutes)分" : "\(minutes)分"
    }
}
