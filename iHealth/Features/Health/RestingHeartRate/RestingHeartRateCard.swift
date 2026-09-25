//
//  RestingHeartRateCard.swift
//  iHealth
//
//  静息心率卡片。
//

import SwiftUI
import Charts

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

    private var average: Double? {
        let values = hourly.compactMap { $0.bpm }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageText: String {
        guard let avg = average else { return "--" }
        return "\(Int(avg.rounded()))"
    }

    private var hasData: Bool {
        hourly.contains { $0.bpm != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(averageText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("次/分")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("今天")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Group {
                if hasData {
                    chart
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .cardStyle(radius: 14)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)

            Text("静息心率")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(hourly) { item in
                if let bpm = item.bpm {
                    AreaMark(
                        x: .value("小时", item.hour),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("静息心率", bpm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.red.opacity(0.30), Color.red.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("小时", item.hour),
                        y: .value("静息心率", bpm)
                    )
                    .foregroundStyle(Color.red)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))

                    PointMark(
                        x: .value("小时", item.hour),
                        y: .value("静息心率", bpm)
                    )
                    .foregroundStyle(Color.red)
                    .symbolSize(28)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xTickValues) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(label(for: hour))
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.top, 2)
        }
    }

    private var emptyState: some View {
        Text("暂无数据")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var xDomain: ClosedRange<Int> {
        let maxHour = hourly.last?.hour ?? 0
        return 0...max(1, maxHour)
    }

    private var xTickValues: [Int] {
        guard let maxHour = hourly.last?.hour else { return [] }
        let step = maxHour <= 6 ? 1 : (maxHour <= 12 ? 2 : 3)
        return Array(stride(from: 0, through: maxHour, by: step))
    }

    private var yDomain: ClosedRange<Double> {
        let values = hourly.compactMap { $0.bpm }
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            return 45...75
        }
        let pad = max((hi - lo) * 0.4, 2)
        return (lo - pad)...(hi + pad)
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d", hour)
    }
}
