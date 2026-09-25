//
//  RestingHeartRateDetailView.swift
//  iHealth
//
//  静息心率详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

struct RestingHeartRateDetailView: View {
    var body: some View {
        MetricDetailScreen(
            title: "静息心率",
            fetchHourly: { await HealthManager.shared.fetchHourlyRestingHeartRate(for: $0) },
            fetchDaily:  { await HealthManager.shared.fetchDailyRestingHeartRate(from: $0, to: $1) },
            dayContent: { hourly, selectedHour in
                RestingHeartRateDayCard(hourly: hourly, selectedHour: selectedHour)
            },
            trendContent: { range, daily, selectedTrendDay in
                RestingHeartRateTrendCard(daily: daily, range: range, selectedTrendDay: selectedTrendDay)
            }
        )
    }
}

private struct RestingHeartRateDayCard: View {
    let hourly: [HourlyRestingHeartRate]
    @Binding var selectedHour: Int?

    private var values: [Double] { hourly.compactMap { $0.bpm } }
    private var hasAny: Bool { !values.isEmpty }
    private var avg: Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        MetricDayCardLayout(
            label: "静息心率",
            value: hasAny ? "\(Int(avg.rounded()))" : "--",
            color: .red,
            unit: "次/分",
            chartTitle: "每小时静息心率"
        ) {
            if hasAny {
                HourlyLineChart(
                    data: hourly,
                    hour: { $0.hour },
                    value: { $0.bpm },
                    color: .red,
                    valueFormatter: { "\(Int($0.rounded())) 次/分" },
                    fallbackYRange: 45...75,
                    yPaddingRatio: 0.3,
                    selection: $selectedHour
                )
                .frame(height: 140)
            } else {
                MetricEmptyChart().frame(height: 140)
            }
        } footer: {
            EmptyView()
        }
    }
}

private struct RestingHeartRateTrendCard: View {
    let daily: [DailyRestingHeartRate]
    let range: MetricRange
    @Binding var selectedTrendDay: Date?

    private var values: [Double] { daily.compactMap { $0.bpm } }
    private var avg: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        MetricTrendCardLayout(
            label: "日均静息心率",
            value: avg.map { "\(Int($0.rounded()))" } ?? "--",
            color: .red,
            unit: "次/分",
            chartTitle: "每日静息心率"
        ) {
            TrendLineChart(
                data: daily,
                date: { $0.date },
                value: { $0.bpm },
                color: .red,
                range: range,
                valueFormatter: { "\(Int($0.rounded())) 次/分" },
                fallbackYRange: 45...75,
                yPaddingRatio: 0.25,
                selection: $selectedTrendDay
            )
            .frame(height: 140)
        } footer: {
            StatsGrid(
                avg: avg,
                highest: values.max(),
                lowest: values.min(),
                count: values.count,
                color: .red,
                unit: "次/分"
            )
        }
    }
}
