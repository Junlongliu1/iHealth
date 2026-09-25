//
//  BloodOxygenCard.swift
//  iHealth
//
//  血氧卡片：显示当天平均血氧与每小时血氧曲线。
//

import SwiftUI

// MARK: - 每小时血氧

struct HourlyBloodOxygen: Identifiable {
    let hour: Int
    let percent: Double?
    var id: Int { hour }
}

// MARK: - 每日血氧

struct DailyBloodOxygen: Identifiable {
    let date: Date
    let percent: Double?
    var id: Date { date }
}

// MARK: - 血氧卡片

struct BloodOxygenCard: View {
    let hourly: [HourlyBloodOxygen]

    var body: some View {
        MetricCard(
            icon: "drop.fill",
            iconColor: .blue,
            title: "血氧",
            unit: "%",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.percent },
            style: .line,
            fallbackYRange: 90...100,
            yPaddingRatio: 0.25,
            clampRange: 0...100
        )
    }
}
