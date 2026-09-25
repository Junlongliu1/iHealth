//
//  AppearanceStore.swift
//  iHealth
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppearanceStore {
    static let shared = AppearanceStore()

    var mode: AppearanceMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: AppearanceMode.storageKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: AppearanceMode.storageKey)
            ?? AppearanceMode.system.rawValue
        self.mode = AppearanceMode(rawValue: raw) ?? .system
    }
}
