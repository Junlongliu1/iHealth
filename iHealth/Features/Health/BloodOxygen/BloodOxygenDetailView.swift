//
//  BloodOxygenDetailView.swift
//  iHealth
//
//  血氧详情页。支持「日 / 周 / 月」。
//

import SwiftUI
import Charts

struct BloodOxygenDetailView: View {
    var body: some View {
        MetricDetailScreen(
            title: "血氧",
            fetchHourly: { await HealthManager.shared.fetchHourlyBloodOxygen(for: $0) },
            fetchDaily:  { await HealthManager.shared.fetchDailyBloodOxygen(from: $0, to: $1) },
            dayContent: { hourly, selectedHour in
                BloodOxygenDayCard(hourly: hourly, selectedHour: selectedHour)
            },
            trendContent: { range, daily, selectedTrendDay in
                BloodOxygenTrendCard(daily: daily, range: range, selectedTrendDay: selectedTrendDay)
            }
        )
    }
}

private struct BloodOxygenDayCard: View {
    let hourly: [HourlyBloodOxygen]
    @Binding var selectedHour: Int?

    private var values: [Double] { hourly.compactMap { $0.percent } }
    private var hasAny: Bool { !values.isEmpty }
    private var avg: Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    private var lowest: HourlyBloodOxygen? {
        hourly.compactMap { $0.percent != nil ? $0 : nil }
            .min { ($0.percent ?? 100) < ($1.percent ?? 100) }
    }

    var body: some View {
        MetricDayCardLayout(
            label: "平均血氧",
            value: hasAny ? "\(Int(avg.rounded()))" : "--",
            color: .blue,
            unit: "%",
            chartTitle: "每小时血氧"
        ) {
            if hasAny {
                HourlyLineChart(
                    data: hourly,
                    hour: { $0.hour },
                    value: { $0.percent },
                    color: .blue,
                    valueFormatter: { "\(Int($0.rounded())) %" },
                    fallbackYRange: 90...100,
                    yPaddingRatio: 0.2,
                    clampRange: 0...100,
                    selection: $selectedHour
                )
                .frame(height: 140)
            } else {
                MetricEmptyChart().frame(height: 140)
            }
        } footer: {
            if let lowest, let p = lowest.percent {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("血氧最低时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(String(format: "%02d", lowest.hour)):00 · \(Int(p.rounded())) %")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.10))
                )
            }
        }
    }
}

private struct BloodOxygenTrendCard: View {
    let daily: [DailyBloodOxygen]
    let range: MetricRange
    @Binding var selectedTrendDay: Date?

    private var values: [Double] { daily.compactMap { $0.percent } }
    private var avg: Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    private var lowDays: Int { values.filter { $0 < 90 }.count }

    var body: some View {
        MetricTrendCardLayout(
            label: "日均血氧",
            value: avg.map { "\(Int($0.rounded()))" } ?? "--",
            color: .blue,
            unit: "%",
            chartTitle: "每日平均血氧"
        ) {
            TrendLineChart(
                data: daily,
                date: { $0.date },
                value: { $0.percent },
                color: .blue,
                range: range,
                valueFormatter: { "\(Int($0.rounded())) %" },
                fallbackYRange: 90...100,
                yPaddingRatio: 0.15,
                clampRange: 0...100,
                reference: .fixed(95),
                selection: $selectedTrendDay
            )
            .frame(height: 140)
        } footer: {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 8) {
                statItem(title: "平均", value: avg.map { "\(Int($0.rounded())) %" } ?? "--")
                statItem(title: "最高", value: values.max().map { "\(Int($0.rounded())) %" } ?? "--")
                statItem(title: "最低", value: values.min().map { "\(Int($0.rounded())) %" } ?? "--")
                statItem(title: "<90% 天数", value: "\(lowDays) 天")
            }
        }
    }

    private func statItem(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.blue).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
