//
//  MainTabView.swift
//  iHealth
//
//  职责：App 的根 Tab 容器。
//
//  · 定义 AppTab 枚举（body / trend / health / sport / settings）
//  · 每个 tab 各自包一个 NavigationStack，独立管理导航栈
//  · 切换 tab 时刷新 activationID，触发内容级联重播
//

import SwiftUI

enum AppTab: Hashable {
    case body
    case trend
    case health
    case sport
    case settings
}

struct MainTabView: View {
    @State private var selection: AppTab = .body
    /// 每次切换 tab 时变化，触发内容的级联入场重播
    @State private var activationID = UUID()

    var body: some View {
        TabView(selection: $selection) {
            Tab("身体", systemImage: "figure.mind.and.body", value: AppTab.body) {
                NavigationStack {
                    BodyTabView(activationID: activationID)
                }
            }

            Tab("趋势", systemImage: "chart.xyaxis.line", value: AppTab.trend) {
                NavigationStack {
                    ReadinessTrendView()
                }
            }

            Tab("健康", systemImage: "heart.fill", value: AppTab.health) {
                NavigationStack {
                    HealthTabView()
                }
            }

            Tab("运动", systemImage: "figure.run", value: AppTab.sport) {
                NavigationStack {
                    SportTabView()
                }
            }

            Tab("设置", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: selection)
        .onChange(of: selection) { _, _ in
            activationID = UUID()
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

#Preview {
    MainTabView()
}
