//
//  HealthCardPreferences.swift
//  iHealth
//
//  记录健康首页卡片的顺序与可见性，持久化到 UserDefaults。
//

import Foundation
import Observation

@MainActor
@Observable
final class HealthCardPreferences {
    static let shared = HealthCardPreferences()

    private let orderKey  = "health.cards.order"
    private let hiddenKey = "health.cards.hidden"

    /// 卡片顺序（包含隐藏的卡片）
    var order: [HealthCardKind] {
        didSet { persistOrder() }
    }

    /// 被隐藏的卡片
    var hidden: Set<HealthCardKind> {
        didSet { persistHidden() }
    }

    private init() {
        // 顺序
        if let data = UserDefaults.standard.data(forKey: orderKey),
           let decoded = try? JSONDecoder().decode([HealthCardKind].self, from: data) {
            var normalized = decoded.filter { HealthCardKind.allCases.contains($0) }
            for kind in HealthCardKind.allCases where !normalized.contains(kind) {
                normalized.append(kind)
            }
            order = normalized
        } else {
            order = HealthCardKind.allCases
        }

        // 隐藏集合
        if let data = UserDefaults.standard.data(forKey: hiddenKey),
           let decoded = try? JSONDecoder().decode([HealthCardKind].self, from: data) {
            hidden = Set(decoded)
        } else {
            hidden = []
        }
    }

    /// 可见卡片，按用户顺序
    var visibleCards: [HealthCardKind] {
        order.filter { !hidden.contains($0) }
    }

    func setVisible(_ visible: Bool, for kind: HealthCardKind) {
        if visible {
            hidden.remove(kind)
        } else {
            hidden.insert(kind)
        }
    }

    func isVisible(_ kind: HealthCardKind) -> Bool {
        !hidden.contains(kind)
    }

    func reset() {
        order = HealthCardKind.allCases
        hidden = []
    }

    // MARK: - 持久化

    private func persistOrder() {
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: orderKey)
        }
    }

    private func persistHidden() {
        if let data = try? JSONEncoder().encode(Array(hidden)) {
            UserDefaults.standard.set(data, forKey: hiddenKey)
        }
    }
}
