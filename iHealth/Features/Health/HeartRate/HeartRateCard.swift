//
//  HeartRateCard.swift
//  iHealth
//
//  心率卡片：显示当天平均心率与每小时心率曲线。
//

import SwiftUI

// MARK: - 每小时心率

struct HourlyHeartRate: Identifiable {
    let hour: Int
    let bpm: Double?
    var id: Int { hour }
}

// MARK: - 每日心率

struct DailyHeartRate: Identifiable {
    let date: Date
    let bpm: Double?
    var id: Date { date }
}

// MARK: - 心率卡片

struct HeartRateCard: View {
    let hourly: [HourlyHeartRate]

    var body: some View {
        MetricCard(
            icon: "heart.fill",
            iconColor: .red,
            title: "心率",
            unit: "次/分",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.bpm },
            style: .line,
            fallbackYRange: 50...100,
            yPaddingRatio: 0.25
        )
    }
}
