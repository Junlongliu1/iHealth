//
//  SleepChartView.swift
//  iHealth
//
//  睡眠数据图表视图。
//  使用 Swift Charts 绘制睡眠阶段图。
//  各阶段色块水平 + 竖直方向都首尾相连，形成连续带。
//  支持点击查看某段阶段的详细信息，选中位置显示竖线。
//  仅适配 iOS 26+。
//

import SwiftUI
import Charts
import HealthKit

struct SleepChartView: View {
    let samples: [HKCategorySample]

    /// 是否显示坐标轴与网格线，以及是否启用选择交互。
    /// 详情页用 true（默认），首页正方形卡片用 false（简洁模式）。
    var showsAxes: Bool = true

    @State private var selectedDate: Date?

    private struct SleepEntry: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let stage: SleepStage
    }

    private var entries: [SleepEntry] {
        samples.compactMap { sample in
            guard let stage = SleepStage.from(sample.value) else { return nil }
            return SleepEntry(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    private var selectedEntry: SleepEntry? {
        guard showsAxes, let date = selectedDate else { return nil }
        return entries.first { date >= $0.start && date < $0.end }
    }

    private var xDomain: ClosedRange<Date> {
        guard let minDate = entries.map(\.start).min(),
              let maxDate = entries.map(\.end).max(),
              minDate < maxDate else {
            let now = Date()
            return now...now.addingTimeInterval(3600)
        }
        let pad: TimeInterval = 10 * 60
        return minDate.addingTimeInterval(-pad)...maxDate.addingTimeInterval(pad)
    }

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                RectangleMark(
                    xStart: .value("开始", entry.start),
                    xEnd:   .value("结束", entry.end),
                    yStart: .value("下", entry.stage.plotIndex - 0.5),
                    yEnd:   .value("上", entry.stage.plotIndex + 0.5)
                )
                .foregroundStyle(by: .value("阶段", entry.stage.label))
                .cornerRadius(0)
            }

            if let date = selectedDate, showsAxes {
                RuleMark(x: .value("选中", date))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .zIndex(1)
            }
        }
        .chartForegroundStyleScale(
            domain: SleepStage.allCases.map { $0.label },
            range:  SleepStage.allCases.map { $0.color }
        )
        .chartYScale(domain: -0.5...3.5)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine(
                        stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
                    )
                    .foregroundStyle(Color.primary.opacity(0.12))

                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self),
                           let stage = SleepStage.allCases.first(where: { $0.plotIndex == v }) {
                            Text(stage.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedDate)
        .chartPlotStyle { plot in
            plot.padding(.vertical, showsAxes ? 4 : 0)
        }
        .overlay(alignment: .top) {
            if let entry = selectedEntry {
                selectionInfo(entry)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.smooth(duration: 0.18), value: selectedEntry?.id)
    }

    private func selectionInfo(_ entry: SleepEntry) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(entry.stage.color)
                .frame(width: 7, height: 7)

            Text(entry.stage.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("\(timeText(entry.start))–\(timeText(entry.end))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text("·")
                .foregroundStyle(.tertiary)

            Text(entry.end.timeIntervalSince(entry.start).shortHourMinuteText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
