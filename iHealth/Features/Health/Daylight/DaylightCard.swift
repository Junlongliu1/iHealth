//
//  DaylightCard.swift
//  iHealth
//
//  日照卡片：显示当天累计日照时长与按小时分布的柱状图。
//  与「睡眠 / 生命体征 / 步数」卡片保持同样的方形外观。
//

import SwiftUI

// MARK: - 每小时日照

struct HourlyDaylight: Identifiable {
    let hour: Int
    let minutes: Double
    var id: Int { hour }
}

// MARK: - 每日日照

struct DailyDaylight: Identifiable {
    let date: Date
    let minutes: Double
    var id: Date { date }
}

// MARK: - 日照卡片

struct DaylightCard: View {
    let hourly: [HourlyDaylight]

    var body: some View {
        MetricCard(
            icon: "sun.max.fill",
            iconColor: .orange,
            title: "日照",
            unit: "分钟",
            hourly: hourly,
            hour: { $0.hour },
            value: { $0.minutes },
            style: .bar
        )
    }
}
