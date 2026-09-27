//
//  RunningShoe.swift
//  iHealth
//

import Foundation
import SwiftUI

// MARK: - 跑鞋模型

struct RunningShoe: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var brand: String
    var colorHex: String
    var purchaseDate: Date
    /// 建议使用寿命（米）
    var maxDistanceMeters: Double
    var isRetired: Bool
    /// 初始里程（米）：购鞋前已有里程，或换鞋前遗漏的历史跑量
    var initialDistanceMeters: Double

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        colorHex: String = "#FF6B35",
        purchaseDate: Date = Date(),
        maxDistanceMeters: Double = 800_000,
        isRetired: Bool = false,
        initialDistanceMeters: Double = 0
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.colorHex = colorHex
        self.purchaseDate = purchaseDate
        self.maxDistanceMeters = maxDistanceMeters
        self.isRetired = isRetired
        self.initialDistanceMeters = initialDistanceMeters
    }

    // MARK: - 向后兼容解码（旧数据无 initialDistanceMeters 字段）

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, colorHex, purchaseDate
        case maxDistanceMeters, isRetired, initialDistanceMeters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FF6B35"
        self.purchaseDate = try c.decodeIfPresent(Date.self, forKey: .purchaseDate) ?? Date()
        self.maxDistanceMeters = try c.decodeIfPresent(Double.self, forKey: .maxDistanceMeters) ?? 800_000
        self.isRetired = try c.decodeIfPresent(Bool.self, forKey: .isRetired) ?? false
        self.initialDistanceMeters = try c.decodeIfPresent(Double.self, forKey: .initialDistanceMeters) ?? 0
    }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) \(name)"
    }

    var color: Color {
        Color(hexString: colorHex) ?? .orange
    }

    /// 预设配色
    static let presetColors: [String] = [
        "#FF6B35", "#3B82F6", "#10B981", "#8B5CF6",
        "#EF4444", "#F59E0B", "#EC4899", "#6B7280"
    ]
}

// MARK: - 磨损等级

enum ShoeWearLevel {
    case fresh      // < 30%
    case good       // 30% - 60%
    case worn       // 60% - 85%
    case replace    // >= 85%

    static func from(progress: Double) -> ShoeWearLevel {
        switch progress {
        case ..<0.30: return .fresh
        case ..<0.60: return .good
        case ..<0.85: return .worn
        default:      return .replace
        }
    }

    var label: String {
        switch self {
        case .fresh:   return "崭新"
        case .good:    return "良好"
        case .worn:    return "磨损中"
        case .replace: return "建议更换"
        }
    }

    var color: Color {
        switch self {
        case .fresh:   return .green
        case .good:    return .blue
        case .worn:    return .orange
        case .replace: return .red
        }
    }
}

// MARK: - Color(hex)

extension Color {
    /// 从 "#RRGGBB" 字符串解析颜色
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >>  8) & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
