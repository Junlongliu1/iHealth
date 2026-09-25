//  RingsSummaryDetails.swift
//  iHealth
//
//  健身圆环右侧的数据面板。
//  从 HKActivitySummary 中读取活动、锻炼、站立的当前值与目标值，
//  以“标题 + 彩色数值/目标 + 单位”的格式展示。
//

import SwiftUI
import HealthKit

// MARK: - 健身配色
extension Color {
    static let fitnessMove     = Color(red: 0.98, green: 0.12, blue: 0.35)
    static let fitnessExercise = Color(red: 0.55, green: 0.88, blue: 0.10)
    static let fitnessStand    = Color(red: 0.05, green: 0.78, blue: 0.85)
}

// MARK: - 圆环详情
struct RingsSummaryDetails: View {
    let summary: HKActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailRow(
                color: .fitnessMove,
                title: "活动",
                value: "\(Int(summary.activeEnergyBurned.doubleValue(for: .kilocalorie())))",
                goal:  "\(Int(summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())))",
                unit: "大卡"
            )
            DetailRow(
                color: .fitnessExercise,
                title: "锻炼",
                value: "\(Int(summary.appleExerciseTime.doubleValue(for: .minute())))",
                goal:  "\(Int(summary.appleExerciseTimeGoal.doubleValue(for: .minute())))",
                unit: "分钟"
            )
            DetailRow(
                color: .fitnessStand,
                title: "站立",
                value: "\(Int(summary.appleStandHours.doubleValue(for: .count())))",
                goal:  "\(Int(summary.appleStandHoursGoal.doubleValue(for: .count())))",
                unit: "小时"
            )
        }
    }
}

// MARK: - 数据行
struct DetailRow: View {
    let color: Color
    let title: String
    let value: String
    let goal: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)

            HStack(spacing: 2) {
                Text("\(value)/\(goal)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(unit)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
            }
        }
    }
}
