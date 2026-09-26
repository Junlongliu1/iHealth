//
//  AthleteProfileStore.swift
//  iHealth
//

import Foundation
import Observation

@MainActor
@Observable
final class AthleteProfileStore {
    static let shared = AthleteProfileStore()

    /// 年龄
    var age: Int {
        didSet { save() }
    }

    /// 自定义最大心率（可选，优先于 220-年龄）
    var customMaxHR: Int? {
        didSet { save() }
    }

    /// 各运动的自定义阈值心率（可选）
    var customThresholds: [String: Int] {
        didSet { save() }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.age = defaults.object(forKey: Keys.age) as? Int ?? 30
        let maxHRStored = defaults.object(forKey: Keys.maxHR) as? Int
        self.customMaxHR = (maxHRStored == 0) ? nil : maxHRStored
        self.customThresholds = defaults.object(forKey: Keys.thresholds) as? [String: Int] ?? [:]
    }

    // MARK: - 计算属性

    var maxHR: Double {
        if let custom = customMaxHR, custom > 0 {
            return Double(custom)
        }
        return Double(max(220 - age, 100))
    }

    var maxHRSource: String {
        if let _ = customMaxHR, customMaxHR! > 0 {
            return "自定义"
        }
        return "220 - 年龄"
    }

    /// 获取某运动的阈值心率
    func thresholdHR(for sport: SportType) -> Double {
        if let custom = customThresholds[sport.rawValue], custom > 0 {
            return Double(custom)
        }
        return maxHR * sport.defaultThresholdFraction
    }

    /// 判断某运动是否用了自定义阈值
    func isCustomThreshold(for sport: SportType) -> Bool {
        if let custom = customThresholds[sport.rawValue], custom > 0 {
            return true
        }
        return false
    }

    func setThreshold(_ value: Int?, for sport: SportType) {
        var copy = customThresholds
        if let v = value, v > 0 {
            copy[sport.rawValue] = v
        } else {
            copy.removeValue(forKey: sport.rawValue)
        }
        customThresholds = copy
    }

    // MARK: - 保存

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(age, forKey: Keys.age)
        if let hr = customMaxHR {
            defaults.set(hr, forKey: Keys.maxHR)
        } else {
            defaults.removeObject(forKey: Keys.maxHR)
        }
        defaults.set(customThresholds, forKey: Keys.thresholds)
    }

    private enum Keys {
        static let age        = "athlete.age"
        static let maxHR      = "athlete.maxHR"
        static let thresholds = "athlete.thresholds"
    }
}
