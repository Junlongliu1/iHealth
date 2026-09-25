//
//  BasalEnergyCard.swift
//  iHealth
//
//  基础代谢卡片：显示当天累计基础代谢消耗与按小时分布的柱状图。
//  与「睡眠 / 生命体征 / 步数 / 日照」卡片保持同样的方形外观。
//

import SwiftUI
import Charts

// MARK: - 每小时基础代谢

struct HourlyBasalEnergy: Identifiable {
    /// 小时（0–23）
    let hour: Int
    /// 该小时累计基础代谢（大卡）
    let kilocalories: Double

    var id: Int { hour }
}

// MARK: - 每日基础代谢

struct DailyBasalEnergy: Identifiable {
    let date: Date
    /// 该日累计基础代谢（大卡）
    let kilocalories: Double

    var id: Date { date }
}

// MARK: - 基础代谢卡片

struct BasalEnergyCard: View {
    /// 当天各小时基础代谢（从 0 点到当前小时）
    let hourly: [HourlyBasalEnergy]

    private var total: Double {
        hourly.reduce(0) { $0 + $1.kilocalories }
    }

    private var totalText: String {
        "\(Int(total.rounded()))"
    }

    private var hasData: Bool {
        !hourly.isEmpty && total > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(totalText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("大卡")
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

    // MARK: - 标题

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.yellow)

            Text("基础代谢")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 每小时柱状图

    private var chart: some View {
        Chart(hourly) { item in
            BarMark(
                x: .value("小时", item.hour),
                y: .value("大卡", item.kilocalories),
                width: .fixed(6)
            )
            .foregroundStyle(Color.yellow.gradient)
            .cornerRadius(2)
        }
        .chartXScale(domain: xDomain)
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

    // MARK: - 坐标轴配置

    private var xDomain: ClosedRange<Int> {
        let maxHour = hourly.last?.hour ?? 0
        return 0...max(1, maxHour)
    }

    private var xTickValues: [Int] {
        guard let maxHour = hourly.last?.hour else { return [] }
        let step = maxHour <= 6 ? 1 : (maxHour <= 12 ? 2 : 3)
        return Array(stride(from: 0, through: maxHour, by: step))
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d", hour)
    }
}
