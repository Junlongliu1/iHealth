//
//  HRZone.swift
//  iHealth
//

import SwiftUI

/// 标准 5 区训练模型（Karvonen / HRR 基准）
struct HRZone: Identifiable, Hashable {
    let id: Int
    let name: String
    let purpose: String
    let lowerFraction: Double   // HRR 百分比
    let upperFraction: Double
    let color: Color

    /// Karvonen 公式：目标心率 = HRrest + (HRmax − HRrest) × 百分比
    func range(maxHR: Double, restingHR: Double) -> (low: Int, high: Int) {
        let reserve = max(maxHR - restingHR, 0)
        let low  = Int((restingHR + reserve * lowerFraction).rounded())
        let high = Int((restingHR + reserve * upperFraction).rounded())
        return (low, high)
    }

    static let all: [HRZone] = [
        HRZone(id: 1, name: "恢复",     purpose: "热身 / 冷身 / 主动恢复", lowerFraction: 0.50, upperFraction: 0.60, color: .blue),
        HRZone(id: 2, name: "有氧基础", purpose: "长距离耐力 / 燃脂",       lowerFraction: 0.60, upperFraction: 0.70, color: .green),
        HRZone(id: 3, name: "节奏",     purpose: "中强度有氧 / 配速跑",     lowerFraction: 0.70, upperFraction: 0.80, color: .yellow),
        HRZone(id: 4, name: "阈值",     purpose: "乳酸阈值 / 提升配速",     lowerFraction: 0.80, upperFraction: 0.90, color: .orange),
        HRZone(id: 5, name: "无氧",     purpose: "间歇 / 冲刺 / 爆发力",    lowerFraction: 0.90, upperFraction: 1.00, color: .red),
    ]
}
