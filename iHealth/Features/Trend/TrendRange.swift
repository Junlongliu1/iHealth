//  TrendRange.swift
//  iHealth
//
//  趋势页共享的数据类型：时间范围枚举 + 通用数据点。

import Foundation

// MARK: - 时间范围

enum TrendRange: String, CaseIterable, Identifiable {
    case sevenDays  = "7 天"
    case thirtyDays = "30 天"
    case sixtyDays  = "60 天"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .sevenDays:  return 7
        case .thirtyDays: return 30
        case .sixtyDays:  return 60
        }
    }
}

// MARK: - 通用数据点

struct TrendDataPoint: Identifiable, Equatable {
    let date: Date
    let value: Double?
    var id: Date { date }
}
