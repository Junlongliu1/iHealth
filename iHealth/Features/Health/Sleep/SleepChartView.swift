//
//  SleepChartView.swift
//  iHealth
//
//  睡眠数据图表视图。
//  同一阶段的相邻时间段合并为连续色块；
//  上下相邻阶段略微重叠，让圆角缝隙被互相遮盖，
//  视觉上既连续又保留左右圆角。仅适配 iOS 26+。
//

import SwiftUI
import Charts
import HealthKit

struct SleepChartView: View {
    let samples: [HKCategorySample]
    var showsAxes: Bool = true

    @State private var selectedDate: Date?

    private struct SleepEntry: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let stage: SleepStage
    }

    private var rawEntries: [SleepEntry] {
        samples
            .compactMap { sample in
                guard let stage = SleepStage.from(sample.value) else { return nil }
                return SleepEntry(start: sample.startDate, end: sample.endDate, stage: stage)
            }
            .sorted { $0.start < $1.start }
    }

    /// 合并同一阶段的相邻时间段，消除水平接缝
    private var entries: [SleepEntry] {
        var result: [SleepEntry] = []
        for entry in rawEntries {
            if let last = result.last,
               last.stage == entry.stage,
               entry.start <= last.end {
                result[result.count - 1] = SleepEntry(
                    start: last.start,
                    end: max(last.end, entry.end),
                    stage: last.stage
                )
            } else {
                result.append(entry)
            }
        }
        return result
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

    // MARK: - 布局参数

    /// 色块垂直半高。> 0.5 让上下相邻阶段重叠，遮住圆角缝隙。
    /// 0.55 → 重叠 0.1 行高，足以盖住 3pt 圆角。
    private let bandHalfHeight: Double = 0.55
    /// 左右圆角半径（只影响水平边缘的视觉，垂直方向靠重叠遮缝）。
    private let bandCornerRadius: CGFloat = 3

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                RectangleMark(
                    xStart: .value("开始", entry.start),
                    xEnd:   .value("结束", entry.end),
                    yStart: .value("下", entry.stage.plotIndex - bandHalfHeight),
                    yEnd:   .value("上", entry.stage.plotIndex + bandHalfHeight)
                )
                .foregroundStyle(entry.stage.color)
                .cornerRadius(bandCornerRadius)
            }

            if let date = selectedDate, showsAxes {
                RuleMark(x: .value("选中", date))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .zIndex(1)
            }
        }
        // 上下各留 0.05 行高，容纳超出 0.5 的部分
        .chartYScale(domain: -0.55...3.55)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.primary.opacity(0.12))

                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.primary.opacity(0.08))

                    AxisValueLabel {
                        if let v = value.as(Double.self),
                           let stage = SleepStage.allCases.first(where: { $0.plotIndex == v }) {
                            Text(stage.label)
                                .font(.system(size: 13))
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

            Text("·").foregroundStyle(.tertiary)

            Text("\(timeText(entry.start))–\(timeText(entry.end))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text("·").foregroundStyle(.tertiary)

            Text(entry.end.timeIntervalSince(entry.start).shortHourMinuteText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: Capsule())
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
