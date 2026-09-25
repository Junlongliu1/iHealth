//
//  HeartRateVariabilityDetailView.swift
//  iHealth
//
//  心率变异性（HRV / SDNN）详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

struct HeartRateVariabilityDetailView: View {
    var body: some View {
        MetricDetailScreen(
            title: "心率变异性",
            fetchHourly: { await HealthManager.shared.fetchHourlyHeartRateVariability(for: $0) },
            fetchDaily:  { await HealthManager.shared.fetchDailyHeartRateVariability(from: $0, to: $1) },
            dayContent: { hourly, selectedHour in
                HRVDayCard(hourly: hourly, selectedHour: selectedHour)
            },
            trendContent: { range, daily, selectedTrendDay in
                HRVTrendCard(daily: daily, range: range, selectedTrendDay: selectedTrendDay)
            }
        )
    }
}

private struct HRVDayCard: View {
    let hourly: [HourlyHeartRateVariability]
    @Binding var selectedHour: Int?

    private var values: [Double] { hourly.compactMap { $0.milliseconds } }
    private var hasAny: Bool { !values.isEmpty }
    private var avg: Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        MetricDayCardLayout(
            label: "心率变异性",
            value: hasAny ? "\(Int(avg.rounded()))" : "--",
            color: .red,
            unit: "毫秒",
            chartTitle: "每小时 HRV"
        ) {
            if hasAny {
                HourlyLineChart(
                    data: hourly,
                    hour: { $0.hour },
                    value: { $0.milliseconds },
                    color: .red,
                    valueFormatter: { "\(Int($0.rounded())) 毫秒" },
                    fallbackYRange: 20...80,
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

private struct HRVTrendCard: View {
    let daily: [DailyHeartRateVariability]
    let range: MetricRange
    @Binding var selectedTrendDay: Date?

    private var values: [Double] { daily.compactMap { $0.milliseconds } }
    private var avg: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        MetricTrendCardLayout(
            label: "日均 HRV",
            value: avg.map { "\(Int($0.rounded()))" } ?? "--",
            color: .red,
            unit: "毫秒",
            chartTitle: "每日 HRV"
        ) {
            TrendLineChart(
                data: daily,
                date: { $0.date },
                value: { $0.milliseconds },
                color: .red,
                range: range,
                valueFormatter: { "\(Int($0.rounded())) 毫秒" },
                fallbackYRange: 20...80,
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
                unit: "毫秒"
            )
        }
    }
}
