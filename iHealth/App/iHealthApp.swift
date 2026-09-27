//
//  iHealthApp.swift
//  iHealth
//

import SwiftUI

@main
struct iHealthApp: App {
    @State private var appearance = AppearanceStore.shared
    @AppStorage("hasSeenHealthAuth") private var hasSeenHealthAuth = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenHealthAuth {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    HealthAuthView {
                        withAnimation(.smooth(duration: 0.45)) {
                            hasSeenHealthAuth = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(appearance.mode.colorScheme)
        }
    }
}
