//
//  SleepChartView.swift
//  iHealth
//
//  睡眠数据图表视图。
//  使用 Swift Charts 绘制睡眠阶段图。
//  仅适配 iOS 26+。
//

import SwiftUI
import Charts
import HealthKit

struct SleepChartView: View {
    let samples: [HKCategorySample]

    /// 是否显示坐标轴与网格线。
    /// 详情页用 true（默认），首页正方形卡片用 false（简洁模式）。
    var showsAxes: Bool = true

    private enum SleepStage: Int, Comparable, CaseIterable {
        case deep = 0, core, rem, awake

        var label: String {
            switch self {
            case .deep:  return "深睡"
            case .core:  return "浅睡"
            case .rem:   return "眼动"
            case .awake: return "清醒"
            }
        }

        var color: Color {
            switch self {
            case .deep:  return .indigo
            case .core:  return .blue
            case .rem:   return .cyan
            case .awake: return .orange
            }
        }

        static func from(_ value: Int) -> SleepStage? {
            switch HKCategoryValueSleepAnalysis(rawValue: value) {
            case .asleepDeep: return .deep
            case .asleepCore: return .core
            case .asleepREM:  return .rem
            case .awake:      return .awake
            default:          return nil
            }
        }

        static func < (lhs: SleepStage, rhs: SleepStage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Y 轴从上到下的显示顺序：清醒 → 眼动 → 浅睡 → 深睡
    private static let displayOrder: [SleepStage] = [.awake, .rem, .core, .deep]

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

    var body: some View {
        Chart(entries) { entry in
            BarMark(
                xStart: .value("开始", entry.start),
                xEnd:   .value("结束", entry.end),
                y:      .value("阶段", entry.stage.label)
            )
            .foregroundStyle(by: .value("阶段", entry.stage.label))
            .cornerRadius(showsAxes ? 3 : 5)
        }
        .chartForegroundStyleScale(
            domain: Self.displayOrder.map { $0.label },
            range:  Self.displayOrder.map { $0.color }
        )
        .chartYScale(domain: Self.displayOrder.map { $0.label })
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.padding(showsAxes ? 6 : 0)
        }
    }
}
