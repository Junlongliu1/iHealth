//
//  ActiveEnergyDetailView.swift
//  iHealth
//
//  活动消耗详情页。
//  支持「日 / 周 / 月」三种时间范围。
//  日视图按住柱状图查看该小时消耗量。
//  周 / 月切换带方向感的 push 过渡。
//

import SwiftUI
import Charts

struct ActiveEnergyDetailView: View {
    var body: some View {
        MetricDetailScreen(
            title: "活动消耗",
            fetchHourly: { await HealthManager.shared.fetchHourlyActiveEnergy(for: $0) },
            fetchDaily:  { await HealthManager.shared.fetchDailyActiveEnergy(from: $0, to: $1) },
            dayContent: { hourly, selectedHour in
                ActiveEnergyDayCard(hourly: hourly, selectedHour: selectedHour)
            },
            trendContent: { range, daily, selectedTrendDay in
                ActiveEnergyTrendCard(daily: daily, range: range, selectedTrendDay: selectedTrendDay)
            }
        )
    }
}

private struct ActiveEnergyDayCard: View {
    let hourly: [HourlyActiveEnergy]
    @Binding var selectedHour: Int?

    private var total: Double { hourly.reduce(0) { $0 + $1.kilocalories } }
    private var hasAny: Bool { hourly.contains { $0.kilocalories > 0 } }
    private var peak: HourlyActiveEnergy? { hourly.max { $0.kilocalories < $1.kilocalories } }

    var body: some View {
        MetricDayCardLayout(
            label: "活动消耗",
            value: "\(Int(total.rounded()))",
            color: .red,
            unit: "大卡",
            chartTitle: "每小时分布"
        ) {
            if hasAny {
                ActiveEnergyHourlyChart(data: hourly, selection: $selectedHour)
                    .frame(height: 140)
            } else {
                MetricEmptyChart().frame(height: 140)
            }
        } footer: {
            if let peak, peak.kilocalories > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("消耗最高时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(String(format: "%02d", peak.hour)):00 · \(Int(peak.kilocalories.rounded())) 大卡")
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

private struct ActiveEnergyTrendCard: View {
    let daily: [DailyActiveEnergy]
    let range: MetricRange
    @Binding var selectedTrendDay: Date?

    private var total: Double { daily.reduce(0) { $0 + $1.kilocalories } }
    private var avg: Double {
        daily.isEmpty ? 0 : total / Double(daily.count)
    }
    private var best: DailyActiveEnergy? { daily.max { $0.kilocalories < $1.kilocalories } }
    private var lowest: DailyActiveEnergy? { daily.min { $0.kilocalories < $1.kilocalories } }

    var body: some View {
        MetricTrendCardLayout(
            label: "日均活动消耗",
            value: "\(Int(avg.rounded()))",
            color: .red,
            unit: "大卡",
            chartTitle: "每日活动消耗"
        ) {
            ActiveEnergyTrendChart(data: daily, range: range, selection: $selectedTrendDay)
                .frame(height: 140)
        } footer: {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 8) {
                statItem(title: "总消耗", value: "\(Int(total.rounded())) 大卡")
                statItem(title: "日均", value: "\(Int(avg.rounded())) 大卡")
                statItem(title: "最高一天", value: best.map { "\(Int($0.kilocalories.rounded())) 大卡" } ?? "--")
                statItem(title: "最低一天", value: lowest.map { "\(Int($0.kilocalories.rounded())) 大卡" } ?? "--")
            }
        }
    }

    private func statItem(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13)).foregroundStyle(.primary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - 图表

private struct ActiveEnergyHourlyChart: View {
    let data: [HourlyActiveEnergy]
    @Binding var selection: Int?

    private var selectedItem: HourlyActiveEnergy? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(x: .value("小时", item.hour), y: .value("大卡", item.kilocalories))
                    .foregroundStyle(barColor(item))
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: 0...max(1, data.last?.hour ?? 23))
        .chartXAxis {
            AxisMarks(values: MetricHourAxis.ticks(upTo: data.last?.hour ?? 23)) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(MetricHourAxis.label(for: hour))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis { metricYAxis(width: 30) }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let raw = proxy.value(atX: value.location.x, as: Double.self) else { return }
                            let hour = Int(raw.rounded())
                            let maxHour = data.last?.hour ?? 23
                            guard (0...maxHour).contains(hour) else { return }
                            if selection != hour { selection = hour }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.15)) { selection = nil }
                        }
                )
        }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                MetricBubble {
                    HStack(spacing: 5) {
                        Text("\(String(format: "%02d", item.hour)):00")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary).monospacedDigit()
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.kilocalories > 0 ? "\(Int(item.kilocalories.rounded())) 大卡" : "无数据")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.15), value: selectedItem?.id)
    }

    private func barColor(_ item: HourlyActiveEnergy) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .red }
        return Color.red.opacity(0.5)
    }
}

private struct ActiveEnergyTrendChart: View {
    let data: [DailyActiveEnergy]
    let range: MetricRange
    @Binding var selection: Date?

    private var selectedItem: DailyActiveEnergy? {
        guard let selection else { return nil }
        let nearest = data.min {
            abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection))
        }
        guard let nearest,
              abs(nearest.date.timeIntervalSince(selection)) <= 12 * 3600 else { return nil }
        return nearest
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(x: .value("日期", item.date, unit: .day), y: .value("大卡", item.kilocalories))
                    .foregroundStyle(barColor(item))
                    .cornerRadius(3)
            }
        }
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: MetricXAxis.stride(for: range)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(MetricXAxis.label(for: date, range: range))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis { metricYAxis(width: 38) }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                MetricBubble {
                    HStack(spacing: 5) {
                        Text(shortDate(item.date))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.kilocalories > 0 ? "\(Int(item.kilocalories.rounded())) 大卡" : "无数据")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.18), value: selectedItem?.id)
    }

    private func barColor(_ item: DailyActiveEnergy) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .red }
        return Color.red.opacity(0.5)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}
