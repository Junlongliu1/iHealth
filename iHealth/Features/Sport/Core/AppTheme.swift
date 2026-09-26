//
//  AppTheme.swift
//  iHealth
//

import SwiftUI
import Foundation

extension ShapeStyle where Self == LinearGradient {
    /// 跑步主题橙色渐变（全局统一）
    static var runGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.62, blue: 0.2),
                Color(red: 1.0, green: 0.42, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Double {
    /// 向下截断到指定小数位（对齐 Apple 健身 App 的距离显示规则）
    func truncated(to places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded(.down) / multiplier
    }
}
