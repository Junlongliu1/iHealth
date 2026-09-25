//
//  SleepStage.swift
//  iHealth
//
//  睡眠阶段枚举：名称、颜色、图表纵轴索引、从 HealthKit 值映射。
//

import SwiftUI
import HealthKit

enum SleepStage: Int, CaseIterable, Identifiable {
    case deep = 0
    case core
    case rem
    case awake

    var id: Int { rawValue }

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

    var plotIndex: Double {
        switch self {
        case .deep:  return 0
        case .core:  return 1
        case .rem:   return 2
        case .awake: return 3
        }
    }

    /// asleepUnspecified 归入浅睡，避免总时长与图表阶段不一致。
    static func from(_ value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepDeep:                     return .deep
        case .asleepCore, .asleepUnspecified: return .core
        case .asleepREM:                      return .rem
        case .awake:                          return .awake
        default:                              return nil
        }
    }
}
