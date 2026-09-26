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

    var age: Int {
        didSet { save() }
    }

    var customMaxHR: Int? {
        didSet { save() }
    }

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
        (customMaxHR ?? 0) > 0 ? "自定义" : "220 - 年龄"
    }

    func thresholdHR(for sport: SportType) -> Double {
        if let custom = customThresholds[sport.rawValue], custom > 0 {
            return Double(custom)
        }
        return maxHR * sport.defaultThresholdFraction
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
