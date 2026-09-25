//
//  MainTabView.swift
//  iHealth
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("健康", systemImage: "heart.fill") {
                NavigationStack {
                    HealthTabView()
                }
            }

            Tab("运动", systemImage: "figure.run") {
                NavigationStack {
                    SportTabView()
                }
            }

            Tab("洞察", systemImage: "chart.line.uptrend.xyaxis") {
                NavigationStack {
                    PlaceholderView(title: "洞察", icon: "chart.line.uptrend.xyaxis")
                }
            }

            Tab("设置", systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
    }
}

// MARK: - 占位页

struct PlaceholderView: View {
    let title: String
    let icon: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text("功能开发中")
        )
        .navigationTitle(title)
    }
}
