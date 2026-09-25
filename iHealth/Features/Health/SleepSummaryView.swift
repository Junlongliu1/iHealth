//
//  SleepSummaryView.swift
//  iHealth
//
//  睡眠数据汇总视图。
//  顶部：总睡眠时长（大字）
//  中部：睡眠阶段图
//  底部：深睡/浅睡/眼动/清醒 四项统计
//

import SwiftUI
import HealthKit

// MARK: - 睡眠阶段汇总

struct SleepSummary {
    let total: TimeInterval      // 睡眠总时长（所有 asleep 阶段之和）
    let deep: TimeInterval       // 深睡
    let core: TimeInterval       // 浅睡
    let rem: TimeInterval        // 眼动（REM）
    let unspecified: TimeInterval// 未分类睡眠
    let awake: TimeInterval      // 清醒

    init(samples: [HKCategorySample]) {
        var deep: TimeInterval = 0
        var core: TimeInterval = 0
        var rem: TimeInterval = 0
        var unspecified: TimeInterval = 0
        var awake: TimeInterval = 0

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
        }

        self.deep = deep
        self.core = core
        self.rem = rem
        self.unspecified = unspecified
        self.awake = awake
        self.total = deep + core + rem + unspecified
    }
}

// MARK: - 睡眠汇总视图

struct SleepSummaryView: View {
    let samples: [HKCategorySample]

    private var summary: SleepSummary { SleepSummary(samples: samples) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 总睡眠时长
            VStack(alignment: .leading, spacing: 2) {
                Text("睡眠时间")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatHourMinute(summary.total))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }

            // 睡眠阶段图
            SleepChartView(samples: samples)
                .frame(height: 140)

            // 四项阶段统计（2×2 网格）
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

    /// 格式化为「X小时Y分」
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

    /// 紧凑格式：「1时12分」/「25分」
    private func format(_ t: TimeInterval) -> String {
        guard t > 0 else { return "0分" }
        let totalMinutes = Int(t / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)时\(minutes)分" : "\(minutes)分"
    }
}
