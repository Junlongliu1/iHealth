//
//  HeartRateDetailView.swift
//  iHealth
//
//  心率详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

struct HeartRateDetailView: View {
    var body: some View {
        MetricDetailScreen(
            title: "心率",
            fetchHourly: { await HealthManager.shared.fetchHourlyHeartRate(for: $0) },
            fetchDaily:  { await HealthManager.shared.fetchDailyHeartRate(from: $0, to: $1) },
            dayContent: { hourly, selectedHour in
                HeartRateDayCard(hourly: hourly, selectedHour: selectedHour)
            },
            trendContent: { range, daily, selectedTrendDay in
                HeartRateTrendCard(daily: daily, range: range, selectedTrendDay: selectedTrendDay)
            }
        )
    }
}

// MARK: - 日卡片

private struct HeartRateDayCard: View {
    let hourly: [HourlyHeartRate]
    @Binding var selectedHour: Int?

    private var values: [Double] { hourly.compactMap { $0.bpm } }
    private var hasAny: Bool { !values.isEmpty }
    private var avg: Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    private var peak: HourlyHeartRate? {
        hourly.compactMap { $0.bpm != nil ? $0 : nil }
            .max { ($0.bpm ?? 0) < ($1.bpm ?? 0) }
    }

    var body: some View {
        MetricDayCardLayout(
            label: "平均心率",
            value: hasAny ? "\(Int(avg.rounded()))" : "--",
            color: .red,
            unit: "次/分",
            chartTitle: "每小时心率"
        ) {
            if hasAny {
                HourlyLineChart(
                    data: hourly,
                    hour: { $0.hour },
                    value: { $0.bpm },
                    color: .red,
                    valueFormatter: { "\(Int($0.rounded())) 次/分" },
                    fallbackYRange: 50...100,
                    yPaddingRatio: 0.2,
                    selection: $selectedHour
                )
                .frame(height: 140)
            } else {
                MetricEmptyChart().frame(height: 140)
            }
        } footer: {
            if let peak, let bpm = peak.bpm {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("心率最高时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(String(format: "%02d", peak.hour)):00 · \(Int(bpm.rounded())) 次/分")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                )
            }
        }
    }
}

// MARK: - 趋势卡片

private struct HeartRateTrendCard: View {
    let daily: [DailyHeartRate]
    let range: MetricRange
    @Binding var selectedTrendDay: Date?

    private var values: [Double] { daily.compactMap { $0.bpm } }
    private var avg: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        MetricTrendCardLayout(
            label: "日均心率",
            value: avg.map { "\(Int($0.rounded()))" } ?? "--",
            color: .red,
            unit: "次/分",
            chartTitle: "每日平均心率"
        ) {
            TrendLineChart(
                data: daily,
                date: { $0.date },
                value: { $0.bpm },
                color: .red,
                range: range,
                valueFormatter: { "\(Int($0.rounded())) 次/分" },
                fallbackYRange: 50...100,
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

// MARK: - 通用统计网格

struct StatsGrid: View {
    let avg: Double?
    let highest: Double?
    let lowest: Double?
    let count: Int
    let color: Color
    let unit: String

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ], alignment: .leading, spacing: 8) {
            item(title: "平均", value: avg.map { "\(Int($0.rounded())) \(unit)" } ?? "--")
            item(title: "最高", value: highest.map { "\(Int($0.rounded())) \(unit)" } ?? "--")
            item(title: "最低", value: lowest.map { "\(Int($0.rounded())) \(unit)" } ?? "--")
            item(title: "有数据天数", value: "\(count) 天")
        }
    }

    private func item(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
