//  SportType.swift
//  iHealth
//
//  职责：运动类型枚举及其元数据。
//
//  · displayName / icon         —— UI 展示用
//  · defaultThresholdFraction   —— 默认阈值心率占比
//  · tssWeight                  —— 跨运动生理负荷权重
//  · from(workout:)             —— 从 HKWorkout 推断运动类型
//
//  是"运动"这一概念的唯一定义源，
//  卡片展示、TSS 计算、建议引擎都引用它。

import Foundation
import HealthKit

enum SportType: String, Codable, CaseIterable, Identifiable {
    case running
    case walking
    case badminton
    case hiking
    case mountaineering
    case cycling
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running:        return "跑步"
        case .walking:        return "步行"
        case .badminton:      return "羽毛球"
        case .hiking:         return "徒步"
        case .mountaineering: return "登山"
        case .cycling:        return "骑行"
        case .other:          return "其他"
        }
    }

    var icon: String {
        switch self {
        case .running:        return "figure.run"
        case .walking:        return "figure.walk"
        case .badminton:      return "figure.badminton"
        case .hiking:         return "figure.hiking"
        case .mountaineering: return "mountain.2.fill"
        case .cycling:        return "figure.outdoor.cycle"
        case .other:          return "figure.mixed.cardio"
        }
    }

    /// 默认阈值心率系数（Karvonen / HRR 基准）
    ///
    /// 目标阈值 = HRrest + (HRmax − HRrest) × 该系数。
    /// 换算自常见 HRmax 系数（如跑步 85% HRmax ≈ 78% HRR），
    /// 让阈值心率在不同静息心率的个体间具备生理等效性。
    var defaultThresholdFraction: Double {
        switch self {
        case .running:        return 0.78
        case .walking:        return 0.56
        case .badminton:      return 0.78
        case .hiking:         return 0.64
        case .mountaineering: return 0.68
        case .cycling:        return 0.78
        case .other:          return 0.71
        }
    }

    /// 跨运动生理负荷权重（以阈值强度 1 小时 = 100 TSS 为基准）
    ///
    /// 修正说明：原以骑行为 1.0、跑步 1.5，会让所有跑者的 CTL 无端虚高 50%，
    /// TSB 常年为负。标准 TSS 定义下，任何运动的"1 小时阈值"都等于 100 TSS。
    /// 所以跑步和骑行都应为 1.0，差异体现在默认阈值比例上。
    var tssWeight: Double {
        switch self {
        case .running:        return 1.0
        case .walking:        return 0.5
        case .badminton:      return 1.0
        case .hiking:         return 0.8
        case .mountaineering: return 1.0
        case .cycling:        return 1.0
        case .other:          return 1.0
        }
    }

    /// 从 HKWorkout 推断运动类型
    static func from(workout: HKWorkout) -> SportType {
        switch workout.workoutActivityType {
        case .running:
            return .running
        case .walking:
            return .walking
        case .badminton:
            return .badminton
        case .cycling:
            return .cycling
        case .hiking:
            // 用爬升区分徒步和登山
            if let elevation = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
                let meters = elevation.doubleValue(for: .meter())
                return meters >= 600 ? .mountaineering : .hiking
            }
            return .hiking
        default:
            return .other
        }
    }
}
