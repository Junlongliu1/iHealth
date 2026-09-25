//
//  ActivityRingsView.swift
//  iHealth
//

import SwiftUI
import HealthKit

// MARK: - 健身圆环

struct ActivityRingsView: View {
    let summary: HKActivitySummary?

    private let moveColor = Color.red
    private let exerciseColor = Color.green
    private let standColor = Color.cyan

    var body: some View {
        ZStack {
            RingView(progress: moveProgress, color: moveColor, lineWidth: 16, diameter: 200)
            RingView(progress: exerciseProgress, color: exerciseColor, lineWidth: 16, diameter: 156)
            RingView(progress: standProgress, color: standColor, lineWidth: 16, diameter: 112)
        }
        .frame(width: 220, height: 220)
    }

    private var moveProgress: Double {
        guard let s = summary else { return 0 }
        let cur = s.activeEnergyBurned.doubleValue(for: .kilocalorie())
        let goal = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        return goal > 0 ? min(cur / goal, 1.0) : 0
    }

    private var exerciseProgress: Double {
        guard let s = summary else { return 0 }
        let cur = s.appleExerciseTime.doubleValue(for: .minute())
        let goal = s.appleExerciseTimeGoal.doubleValue(for: .minute())
        return goal > 0 ? min(cur / goal, 1.0) : 0
    }

    private var standProgress: Double {
        guard let s = summary else { return 0 }
        let cur = s.appleStandHours.doubleValue(for: .count())
        let goal = s.appleStandHoursGoal.doubleValue(for: .count())
        return goal > 0 ? min(cur / goal, 1.0) : 0
    }
}

// MARK: - 单个圆环

struct RingView: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.2), value: progress)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - 圆环详情

struct RingsSummaryDetails: View {
    let summary: HKActivitySummary

    var body: some View {
        VStack(spacing: 16) {
            DetailRow(
                color: .red,
                icon: "flame.fill",
                title: "活动",
                value: "\(Int(summary.activeEnergyBurned.doubleValue(for: .kilocalorie())))",
                goal: "\(Int(summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())))",
                unit: "千卡"
            )
            DetailRow(
                color: .green,
                icon: "figure.run",
                title: "锻炼",
                value: "\(Int(summary.appleExerciseTime.doubleValue(for: .minute())))",
                goal: "\(Int(summary.appleExerciseTimeGoal.doubleValue(for: .minute())))",
                unit: "分钟"
            )
            DetailRow(
                color: .cyan,
                icon: "figure.stand",
                title: "站立",
                value: "\(Int(summary.appleStandHours.doubleValue(for: .count())))",
                goal: "\(Int(summary.appleStandHoursGoal.doubleValue(for: .count())))",
                unit: "小时"
            )
        }
        .padding(16)
        .cardGlass()
    }
}

struct DetailRow: View {
    let color: Color
    let icon: String
    let title: String
    let value: String
    let goal: String
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26)

            Text(title)
                .font(.system(size: 15, weight: .medium))

            Spacer()

            Text("\(value) / \(goal) \(unit)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
