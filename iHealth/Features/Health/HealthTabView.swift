//
//  HealthTabView.swift
//  iHealth
//

import SwiftUI
import HealthKit

struct HealthTabView: View {
    @State private var healthManager = HealthManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ActivityRingsView(summary: healthManager.activitySummary)
                    .padding(.top, 24)

                if healthManager.isLoading {
                    ProgressView("加载中...")
                } else if let summary = healthManager.activitySummary {
                    RingsSummaryDetails(summary: summary)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.bottom, 40)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("健康")
        .task {
            await healthManager.requestAuthorization()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)

            Text("暂无今日活动数据")
                .font(.headline)

            Text("请确保已佩戴 Apple Watch 或 iPhone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }
}
