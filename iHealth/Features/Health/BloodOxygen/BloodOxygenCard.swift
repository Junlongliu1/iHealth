//
//  BloodOxygenCard.swift
//  iHealth
//
//  血氧卡片：显示当天平均血氧与每小时血氧曲线。
//

import SwiftUI
import Charts

// MARK: - 每小时血氧（平均值，nil 表示该小时无数据）

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

    private var average: Double? {
        let values = hourly.compactMap { $0.percent }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageText: String {
        guard let avg = average else { return "--" }
        return "\(Int(avg.rounded()))"
    }

    private var hasData: Bool {
        hourly.contains { $0.percent != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(averageText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("%")
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
            Image(systemName: "drop.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.blue)

            Text("血氧")
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
                if let p = item.percent {
                    AreaMark(
                        x: .value("小时", item.hour),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("血氧", p)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.30), Color.blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("小时", item.hour),
                        y: .value("血氧", p)
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
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
        let values = hourly.compactMap { $0.percent }
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            return 90...100
        }
        let pad = max((hi - lo) * 0.25, 1)
        return max(0, lo - pad)...min(100, hi + pad)
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d", hour)
    }
}
