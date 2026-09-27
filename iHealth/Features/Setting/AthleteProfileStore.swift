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
    
    /// 用户设置的显示名称；空字符串 → UI 回退到「我」
    var displayName: String {
        didSet { save() }
    }

    var age: Int {
        didSet { save() }
    }

    var customMaxHR: Int? {
        didSet { save() }
    }

    var customThresholds: [String: Int] {
        didSet { save() }
    }

    /// 用户手动指定的静息心率（覆盖自动同步值）
    var customRestingHR: Int? {
        didSet { save() }
    }

    /// 从 HealthKit 同步到的静息心率中位数（供展示和计算使用）
    var syncedRestingHR: Int? {
        didSet { save() }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.displayName = defaults.string(forKey: Keys.displayName) ?? ""
        self.age = defaults.object(forKey: Keys.age) as? Int ?? 30

        let maxHRStored = defaults.object(forKey: Keys.maxHR) as? Int
        self.customMaxHR = (maxHRStored == 0) ? nil : maxHRStored

        self.customThresholds = defaults.object(forKey: Keys.thresholds) as? [String: Int] ?? [:]

        let customRHR = defaults.object(forKey: Keys.customRHR) as? Int
        self.customRestingHR = (customRHR == 0) ? nil : customRHR

        let syncedRHR = defaults.object(forKey: Keys.syncedRHR) as? Int
        self.syncedRestingHR = (syncedRHR == 0) ? nil : syncedRHR
    }

    // MARK: - 最大心率

    var maxHR: Double {
        if let custom = customMaxHR, custom > 0 {
            return Double(custom)
        }
        return Double(max(220 - age, 100))
    }

    var maxHRSource: String {
        (customMaxHR ?? 0) > 0 ? "自定义" : "220 - 年龄"
    }

    // MARK: - 静息心率

    /// 生效的静息心率：用户手填 > HealthKit 同步 > 默认 60
    var restingHR: Double {
        if let custom = customRestingHR, custom > 0 {
            return Double(custom)
        }
        if let synced = syncedRestingHR, synced > 0 {
            return Double(synced)
        }
        return 60
    }

    var restingHRSource: String {
        if (customRestingHR ?? 0) > 0 { return "自定义" }
        if (syncedRestingHR ?? 0) > 0 { return "健康数据" }
        return "默认值"
    }

    /// 心率储备 = 最大心率 − 静息心率
    var heartRateReserve: Double {
        max(maxHR - restingHR, 0)
    }

    // MARK: - 阈值心率（Karvonen）

    /// 目标阈值 = HRrest + (HRmax − HRrest) × 系数
    func thresholdHR(for sport: SportType) -> Double {
        if let custom = customThresholds[sport.rawValue], custom > 0 {
            return Double(custom)
        }
        return restingHR + heartRateReserve * sport.defaultThresholdFraction
    }

    func isCustomThreshold(for sport: SportType) -> Bool {
        (customThresholds[sport.rawValue] ?? 0) > 0
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
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(age, forKey: Keys.age)

        if let hr = customMaxHR {
            defaults.set(hr, forKey: Keys.maxHR)
        } else {
            defaults.removeObject(forKey: Keys.maxHR)
        }
        defaults.set(customThresholds, forKey: Keys.thresholds)

        if let rhr = customRestingHR {
            defaults.set(rhr, forKey: Keys.customRHR)
        } else {
            defaults.removeObject(forKey: Keys.customRHR)
        }
        if let rhr = syncedRestingHR {
            defaults.set(rhr, forKey: Keys.syncedRHR)
        } else {
            defaults.removeObject(forKey: Keys.syncedRHR)
        }
    }

    private enum Keys {
        static let displayName = "athlete.displayName"
        static let age        = "athlete.age"
        static let maxHR      = "athlete.maxHR"
        static let thresholds = "athlete.thresholds"
        static let customRHR  = "athlete.customRestingHR"
        static let syncedRHR  = "athlete.syncedRestingHR"
    }
}
