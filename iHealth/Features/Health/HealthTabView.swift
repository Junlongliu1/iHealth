//
//  HealthTabView.swift
//  iHealth
//
//  健康标签页主视图。
//  展示健身圆环卡片（圆环 + 数据面板），处理加载状态，
//  并在页面出现时向 HealthManager 请求 HealthKit 授权。
//

import SwiftUI
import HealthKit

struct HealthTabView: View {
    @State private var healthManager = HealthManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if healthManager.isLoading {
                    ProgressView("加载中...")
                        .padding(.top, 40)
                } else {
                    ringsCard
                        .padding(.top, 24)
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

    // MARK: - 活动圆环卡片
    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活动圆环")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            HStack(spacing: 48) {
                // 官方圆环视图
                ActivityRingsView(summary: healthManager.activitySummary)
                    .frame(width: 110, height: 110)

                // 数据面板
                if let summary = healthManager.activitySummary {
                    RingsSummaryDetails(summary: summary)
                } else {
                    Text("暂无数据")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity) // 内容整体在卡片内居中
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 卡片背景（深浅色自适应）
    @ViewBuilder
    private var cardBackground: some View {
        if colorScheme == .dark {
            Color(red: 0.11, green: 0.11, blue: 0.12)
        } else {
            Color(.secondarySystemBackground)
        }
    }
}
