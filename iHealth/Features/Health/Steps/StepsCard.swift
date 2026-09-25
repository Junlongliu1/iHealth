//
//  StepsCard.swift
//  iHealth
//
//  步数卡片：显示当天累计步数与按小时分布的柱状图。
//  与「睡眠 / 生命体征」卡片保持同样的方形外观。
//

import SwiftUI

// MARK: - 每小时步数

struct HourlySteps: Identifiable {
    let hour: Int
    let steps: Double
    var id: Int { hour }
}

// MARK: - 每日步数

struct DailySteps: Identifiable {
    let date: Date
    let steps: Double
    var id: Date { date }
}

// MARK: - 步数卡片

struct StepsCard: View {
    let hourly: [HourlySteps]

    var body: some View {
        MetricCard(
            icon: "figure.walk",
            iconColor: .green,
            title: "步数",
            unit: "步",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.steps },
            style: .bar
        )
    }
}
