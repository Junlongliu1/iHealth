//
//  iHealthApp.swift
//  iHealth
//

import SwiftUI

@main
struct iHealthApp: App {
    @State private var appearance = AppearanceStore.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(appearance.mode.colorScheme)
        }
    }
}
