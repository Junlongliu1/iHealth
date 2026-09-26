//
//  SportType.swift
//  iHealth
//

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

    /// 阈值心率默认占最大心率的比例
    var defaultThresholdFraction: Double {
        switch self {
        case .running:        return 0.85
        case .walking:        return 0.70
        case .badminton:      return 0.85
        case .hiking:         return 0.75
        case .mountaineering: return 0.78
        case .cycling:        return 0.85
        case .other:          return 0.80
        }
    }

    /// 跨运动生理负荷权重（以骑行为基准 1.0）
    var tssWeight: Double {
        switch self {
        case .running:        return 1.5
        case .walking:        return 0.8
        case .badminton:      return 1.2
        case .hiking:         return 1.2
        case .mountaineering: return 1.4
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
