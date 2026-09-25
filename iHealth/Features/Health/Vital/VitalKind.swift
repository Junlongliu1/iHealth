//
//  VitalKind.swift
//  iHealth
//
//  生命体征指标类型：名称、单位、颜色、睡眠参考范围、HealthKit 映射。
//

import SwiftUI
import HealthKit

enum VitalKind: String, CaseIterable, Identifiable {
    case heartRate
    case respiratoryRate
    case wristTemperature
    case bloodOxygen

    var id: String { rawValue }

    var name: String {
        switch self {
        case .heartRate:        return "心率"
        case .respiratoryRate:  return "呼吸频率"
        case .wristTemperature: return "手腕温度"
        case .bloodOxygen:      return "血氧"
        }
    }

    var shortName: String {
        switch self {
        case .heartRate:        return "心率"
        case .respiratoryRate:  return "呼吸"
        case .wristTemperature: return "体温"
        case .bloodOxygen:      return "血氧"
        }
    }

    var icon: String {
        switch self {
        case .heartRate:        return "heart.fill"
        case .respiratoryRate:  return "wind"
        case .wristTemperature: return "thermometer.medium"
        case .bloodOxygen:      return "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .heartRate:        return .red
        case .respiratoryRate:  return .cyan
        case .wristTemperature: return .orange
        case .bloodOxygen:      return .blue
        }
    }

    var unitText: String {
        switch self {
        case .heartRate, .respiratoryRate: return "次/分"
        case .wristTemperature:            return "°C"
        case .bloodOxygen:                 return "%"
        }
    }

    var decimals: Int { 1 }

    /// 睡眠场景参考范围
    var normalRange: ClosedRange<Double> {
        switch self {
        case .heartRate:        return 40...60
        case .respiratoryRate:  return 12...20
        case .wristTemperature: return 33.0...36.0
        case .bloodOxygen:      return 95...100
        }
    }

    var rangeHint: String {
        switch self {
        case .heartRate:        return "睡眠静息参考"
        case .respiratoryRate:  return "睡眠呼吸参考"
        case .wristTemperature: return "手腕皮肤温度参考"
        case .bloodOxygen:      return "血氧参考"
        }
    }

    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .heartRate:        return .heartRate
        case .respiratoryRate:  return .respiratoryRate
        case .wristTemperature: return .appleSleepingWristTemperature
        case .bloodOxygen:      return .oxygenSaturation
        }
    }

    var unitHK: HKUnit {
        switch self {
        case .heartRate, .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .wristTemperature:
            return .degreeCelsius()
        case .bloodOxygen:
            return .percent()
        }
    }

    var needsPercentFix: Bool { self == .bloodOxygen }
    var isSleepOnly: Bool { self == .wristTemperature }
}
