//
//  TimeInterval+Format.swift
//  iHealth
//
//  时间间隔与 VitalSample 的通用格式化 / 聚合。
//

import Foundation

extension TimeInterval {
    /// "1小时30分" / "30分"
    var hourMinuteText: String {
        guard self > 0 else { return "0分" }
        let totalMinutes = Int(self / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)小时\(m)分" : "\(m)分"
    }

    /// "1时30分" / "30分"
    var shortHourMinuteText: String {
        guard self > 0 else { return "0分" }
        let totalMinutes = Int(self / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)时\(m)分" : "\(m)分"
    }
}

extension Collection where Element == VitalSample {
    var averageValue: Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1.value } / Double(count)
    }
}
