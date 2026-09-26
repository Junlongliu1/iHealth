//
//  KilometerSplit.swift
//  iHealth
//

import Foundation

/// 一次跑步的每 1 公里分段
struct KilometerSplit: Identifiable, Hashable {
    var id: Int { index }

    /// 第几公里（1-based）
    let index: Int
    /// 该段距离（米），完整段为 1000，尾段可能 < 1000
    let distance: Double
    /// 该段用时（秒），已剔除暂停时间
    let duration: TimeInterval
    /// 该段起始时间（墙钟时间）
    let startDate: Date

    // MARK: 聚合指标（PB 计算不使用这些字段）
    var averageHeartRate: Double? = nil      // bpm
    var averageStrideLength: Double? = nil   // 米
    var averageCadence: Double? = nil        // 步 / 分钟
    var averagePower: Double? = nil          // 瓦
}

// MARK: - 派生属性 / 展示格式化

extension KilometerSplit {

    /// 配速（秒 / 公里），按实际距离换算
    var pace: Double? {
        let km = distance / 1000
        guard km > 0.01 else { return nil }
        return duration / km
    }

    /// 是否为完整 1 公里段
    var isFullKilometer: Bool { distance >= 1000 }

    /// "5'20\"" 格式
    var formattedPace: String {
        guard let pace, pace.isFinite, pace > 0 else { return "--" }
        let total = Int(pace.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    var formattedHeartRate: String {
        guard let v = averageHeartRate else { return "--" }
        return "\(Int(v.rounded()))"
    }

    var formattedCadence: String {
        guard let v = averageCadence else { return "--" }
        return "\(Int(v.rounded()))"
    }

    var formattedPower: String {
        guard let v = averagePower else { return "--" }
        return "\(Int(v.rounded()))"
    }

    /// 步幅按厘米展示
    var formattedStride: String {
        guard let v = averageStrideLength else { return "--" }
        return "\(Int(v * 100))"
    }
}
