//
//  DaylightDetailView.swift
//  iHealth
//
//  日照详情页。
//  支持「日 / 周 / 月」三种时间范围。
//  日视图点击柱状图查看该小时日照时长。
//  周 / 月切换带方向感的 push 过渡。
//

import SwiftUI
import Charts

struct DaylightDetailView: View {
    var body: some View {
        MetricDetailScreen(
            title: "日照",
            fetchHourly: { await HealthManager.shared.fetchHourlyDaylight(for: $0) },
            fetchDaily:  { await HealthManager.shared.fetchDailyDaylight(from: $0, to: $1) },
            dayContent: { hourly, selectedHour in
                DaylightDayCard(hourly: hourly, selectedHour: selectedHour)
            },
            trendContent: { range, daily, selectedTrendDay in
                DaylightTrendCard(daily: daily, range: range, selectedTrendDay: selectedTrendDay)
            }
        )
    }
}

private struct DaylightDayCard: View {
    let hourly: [HourlyDaylight]
    @Binding var selectedHour: Int?

    private var total: Double { hourly.reduce(0) { $0 + $1.minutes } }
    private var hasAny: Bool { hourly.contains { $0.minutes > 0 } }
    private var peak: HourlyDaylight? { hourly.max { $0.minutes < $1.minutes } }

    var body: some View {
        MetricDayCardLayout(
            label: "日照时长",
            value: "\(Int(total.rounded()))",
            color: .orange,
            unit: "分钟",
            chartTitle: "每小时分布"
        ) {
            if hasAny {
                DaylightHourlyChart(data: hourly, selection: $selectedHour)
                    .frame(height: 140)
            } else {
                MetricEmptyChart().frame(height: 140)
            }
        } footer: {
            if let peak, peak.minutes > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("日照最长时段")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(String(format: "%02d", peak.hour)):00 · \(Int(peak.minutes)) 分钟")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
    }
}

private struct DaylightTrendCard: View {
    let daily: [DailyDaylight]
    let range: MetricRange
    @Binding var selectedTrendDay: Date?

    private var total: Double { daily.reduce(0) { $0 + $1.minutes } }
    private var avg: Double {
        daily.isEmpty ? 0 : total / Double(daily.count)
    }
    private var best: DailyDaylight? { daily.max { $0.minutes < $1.minutes } }
    private var reachedDays: Int { daily.filter { $0.minutes >= 30 }.count }

    var body: some View {
        MetricTrendCardLayout(
            label: "日均日照",
            value: "\(Int(avg.rounded()))",
            color: .orange,
            unit: "分钟",
            chartTitle: "每日日照"
        ) {
            DaylightTrendChart(data: daily, range: range, selection: $selectedTrendDay)
                .frame(height: 140)
        } footer: {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 8) {
                statItem(title: "总时长", value: "\(Int(total.rounded())) 分")
                statItem(title: "日均", value: "\(Int(avg.rounded())) 分")
                statItem(title: "最高一天", value: best.map { "\(Int($0.minutes.rounded())) 分" } ?? "--")
                statItem(title: "≥30分天数", value: "\(reachedDays) 天")
            }
        }
    }

    private func statItem(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.orange).frame(width: 8, height: 8)
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

private struct DaylightHourlyChart: View {
    let data: [HourlyDaylight]
    @Binding var selection: Int?

    private var selectedItem: HourlyDaylight? {
        guard let selection else { return nil }
        return data.first { $0.hour == selection }
    }

    var body: some View {
        Chart {
            ForEach(data) { item in
                BarMark(x: .value("小时", item.hour), y: .value("分钟", item.minutes))
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
                        Text(item.minutes > 0 ? "\(Int(item.minutes)) 分钟" : "无数据")
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

    private func barColor(_ item: HourlyDaylight) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .orange }
        return Color.orange.opacity(0.5)
    }
}

private struct DaylightTrendChart: View {
    let data: [DailyDaylight]
    let range: MetricRange
    @Binding var selection: Date?

    private var selectedItem: DailyDaylight? {
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
                BarMark(x: .value("日期", item.date, unit: .day), y: .value("分钟", item.minutes))
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
        .chartYAxis { metricYAxis(width: 34) }
        .overlay(alignment: .top) {
            if let item = selectedItem {
                MetricBubble {
                    HStack(spacing: 5) {
                        Text(shortDate(item.date))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(item.minutes > 0 ? "\(Int(item.minutes)) 分钟" : "无数据")
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

    private func barColor(_ item: DailyDaylight) -> Color {
        if let selected = selectedItem, selected.id == item.id { return .orange }
        return Color.orange.opacity(0.5)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}
