//
//  HealthCardKind.swift
//  iHealth
//
//  健康首页可编辑卡片的种类。
//

import SwiftUI

enum HealthCardKind: String, CaseIterable, Identifiable, Codable {
    case sleep
    case vitals
    case steps
    case daylight
    case basalEnergy
    case activeEnergy
    case heartRate
    case bloodOxygen
    case restingHeartRate
    case hrv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:            return "睡眠"
        case .vitals:           return "生命体征"
        case .steps:            return "步数"
        case .daylight:         return "日照"
        case .basalEnergy:      return "基础代谢"
        case .activeEnergy:     return "活动消耗"
        case .heartRate:        return "心率"
        case .bloodOxygen:      return "血氧"
        case .restingHeartRate: return "静息心率"
        case .hrv:              return "心率变异性"
        }
    }

    var icon: String {
        switch self {
        case .sleep:            return "bed.double.fill"
        case .vitals:           return "heart.text.square.fill"
        case .steps:            return "figure.walk"
        case .daylight:         return "sun.max.fill"
        case .basalEnergy:      return "flame.fill"
        case .activeEnergy:     return "figure.run"
        case .heartRate:        return "heart.fill"
        case .bloodOxygen:      return "drop.fill"
        case .restingHeartRate: return "heart.circle.fill"
        case .hrv:              return "waveform.path.ecg"
        }
    }

    var iconColor: Color {
        switch self {
        case .sleep:            return .indigo
        case .vitals:           return .pink
        case .steps:            return .green
        case .daylight:         return .orange
        case .basalEnergy:      return .yellow
        case .activeEnergy:     return .red
        case .heartRate:        return .red
        case .bloodOxygen:      return .blue
        case .restingHeartRate: return .red
        case .hrv:              return .red
        }
    }
}
