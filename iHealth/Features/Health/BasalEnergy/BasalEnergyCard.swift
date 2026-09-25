//
//  BasalEnergyCard.swift
//  iHealth
//
//  基础代谢卡片：显示当天累计基础代谢消耗与按小时分布的柱状图。
//  与「睡眠 / 生命体征 / 步数 / 日照」卡片保持同样的方形外观。
//

import SwiftUI

// MARK: - 每小时基础代谢

struct HourlyBasalEnergy: Identifiable {
    let hour: Int
    let kilocalories: Double
    var id: Int { hour }
}

// MARK: - 每日基础代谢

struct DailyBasalEnergy: Identifiable {
    let date: Date
    let kilocalories: Double
    var id: Date { date }
}

// MARK: - 基础代谢卡片

struct BasalEnergyCard: View {
    let hourly: [HourlyBasalEnergy]

    var body: some View {
        MetricCard(
            icon: "flame.fill",
            iconColor: .yellow,
            title: "基础代谢",
            unit: "大卡",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.kilocalories },
            style: .bar
        )
    }
}
