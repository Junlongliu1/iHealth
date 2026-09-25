//
//  RestingHeartRateCard.swift
//  iHealth
//
//  静息心率卡片。
//

import SwiftUI

// MARK: - 每小时静息心率

struct HourlyRestingHeartRate: Identifiable {
    let hour: Int
    let bpm: Double?
    var id: Int { hour }
}

// MARK: - 每日静息心率

struct DailyRestingHeartRate: Identifiable {
    let date: Date
    let bpm: Double?
    var id: Date { date }
}

// MARK: - 静息心率卡片

struct RestingHeartRateCard: View {
    let hourly: [HourlyRestingHeartRate]

    var body: some View {
        MetricCard(
            icon: "heart.circle.fill",
            iconColor: .red,
            title: "静息心率",
            unit: "次/分",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.bpm },
            style: .line,
            fallbackYRange: 45...75,
            yPaddingRatio: 0.4
        )
    }
}
