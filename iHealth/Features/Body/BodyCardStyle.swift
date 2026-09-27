//  BodyCardStyle.swift
//  iHealth
//
//  职责：身体 Tab 的"数值 → 颜色 / 文案"映射规则。
//
//  · CardStyle       —— 纯映射工具：
//                       scoreTint / recoveryLabel /
//                       tsbColor / atlColor
//  · StateStyle      —— 按准备度映射到"整体状态"的
//                       语义描述（badge / title / detail /
//                       icon / gradient）
//
//  只放映射，不放视图、不放长文本。

import SwiftUI

// MARK: - 分数着色规则

enum CardStyle {

    /// 0–100 分数 → 颜色
    static func scoreTint(_ score: Double) -> Color {
        switch score {
        case 85...:    return .green
        case 70..<85:  return .mint
        case 50..<70:  return .yellow
        case 30..<50:  return .orange
        default:       return .red
        }
    }

    /// 恢复度文字标签
    static func recoveryLabel(_ score: Double) -> String {
        switch score {
        case 85...:    return "极佳"
        case 70..<85:  return "良好"
        case 50..<70:  return "一般"
        case 30..<50:  return "偏低"
        default:       return "很差"
        }
    }

    /// TSB 着色
    static func tsbColor(_ tsb: Double) -> Color {
        switch tsb {
        case 20...:        return .blue
        case 5..<20:       return .green
        case 0..<5:        return .mint
        case -10..<0:      return .yellow
        case -20..<(-10):  return .orange
        case -30..<(-20):  return Color(red: 0.90, green: 0.45, blue: 0.20)
        default:           return .red
        }
    }

    /// ATL 相对 CTL 偏离着色
    static func atlColor(atl: Double, ctl: Double) -> Color {
        let diff = atl - ctl
        switch diff {
        case ..<(-5):       return .blue
        case -5..<5:        return .primary
        case 5..<15:        return .orange
        case 15..<30:       return Color(red: 0.90, green: 0.45, blue: 0.20)
        default:            return .red
        }
    }
}

// MARK: - 状态样式

struct StateStyle {
    let badge: String
    let subtitle: String
    let title: String
    let detail: String
    let icon: String
    let gradient: [Color]

    static func from(readiness: Double) -> StateStyle {
        switch readiness {
        case 85...:
            return StateStyle(
                badge: "巅峰",
                subtitle: "身体状态极佳，适合挑战",
                title: "状态极佳",
                detail: "适合安排高质量或高强度训练，可尝试突破或测试。",
                icon: "bolt.fill",
                gradient: [Color(red: 0.18, green: 0.80, blue: 0.44),
                           Color(red: 0.10, green: 0.65, blue: 0.55)]
            )
        case 70..<85:
            return StateStyle(
                badge: "良好",
                subtitle: "恢复充分，按计划执行",
                title: "状态良好",
                detail: "按计划执行训练即可，注意保持节奏。",
                icon: "checkmark.circle.fill",
                gradient: [Color(red: 0.20, green: 0.72, blue: 0.65),
                           Color(red: 0.16, green: 0.60, blue: 0.72)]
            )
        case 50..<70:
            return StateStyle(
                badge: "一般",
                subtitle: "适度训练，避免过量",
                title: "状态一般",
                detail: "建议降低强度或缩短时长，以有氧为主。",
                icon: "exclamationmark.triangle.fill",
                gradient: [Color(red: 0.96, green: 0.72, blue: 0.20),
                           Color(red: 0.92, green: 0.58, blue: 0.16)]
            )
        case 30..<50:
            return StateStyle(
                badge: "偏低",
                subtitle: "需要主动恢复",
                title: "需要恢复",
                detail: "安排主动恢复：散步、拉伸、轻松游泳。",
                icon: "arrow.down.circle.fill",
                gradient: [Color(red: 0.95, green: 0.50, blue: 0.25),
                           Color(red: 0.88, green: 0.36, blue: 0.24)]
            )
        default:
            return StateStyle(
                badge: "恢复优先",
                subtitle: "身体需要休息",
                title: "恢复优先",
                detail: "建议完全休息或极低强度活动，避免加量。",
                icon: "bed.double.fill",
                gradient: [Color(red: 0.90, green: 0.30, blue: 0.35),
                           Color(red: 0.75, green: 0.18, blue: 0.40)]
            )
        }
    }
}
