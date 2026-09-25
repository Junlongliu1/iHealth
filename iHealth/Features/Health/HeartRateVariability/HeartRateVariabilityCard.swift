//
//  HeartRateVariabilityCard.swift
//  iHealth
//
//  心率变异性（HRV / SDNN）卡片。
//

import SwiftUI

// MARK: - 每小时 HRV

struct HourlyHeartRateVariability: Identifiable {
    let hour: Int
    let milliseconds: Double?
    var id: Int { hour }
}

// MARK: - 每日 HRV

struct DailyHeartRateVariability: Identifiable {
    let date: Date
    let milliseconds: Double?
    var id: Date { date }
}

// MARK: - HRV 卡片

struct HeartRateVariabilityCard: View {
    let hourly: [HourlyHeartRateVariability]

    var body: some View {
        MetricCard(
            icon: "waveform.path.ecg",
            iconColor: .red,
            title: "心率变异性",
            unit: "毫秒",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.milliseconds },
            style: .line,
            fallbackYRange: 20...80,
            yPaddingRatio: 0.4
        )
    }
}
