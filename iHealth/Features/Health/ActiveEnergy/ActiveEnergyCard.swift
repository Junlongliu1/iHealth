//
//  ActiveEnergyCard.swift
//  iHealth
//
//  活动消耗卡片：显示当天累计活动消耗与按小时分布的柱状图。
//  与「睡眠 / 生命体征 / 步数 / 日照 / 基础代谢」卡片保持同样的方形外观。
//

import SwiftUI

// MARK: - 每小时活动消耗

struct HourlyActiveEnergy: Identifiable {
    let hour: Int
    let kilocalories: Double
    var id: Int { hour }
}

// MARK: - 每日活动消耗

struct DailyActiveEnergy: Identifiable {
    let date: Date
    let kilocalories: Double
    var id: Date { date }
}

// MARK: - 活动消耗卡片

struct ActiveEnergyCard: View {
    let hourly: [HourlyActiveEnergy]

    var body: some View {
        MetricCard(
            icon: "figure.run",
            iconColor: .red,
            title: "活动消耗",
            unit: "大卡",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.kilocalories },
            style: .bar
        )
    }
}
