//
//  SleepDetailView.swift
//  iHealth
//
//  睡眠详情页。
//  展示总睡眠时长、睡眠阶段图和各项阶段统计。
//

import SwiftUI
import HealthKit

struct SleepDetailView: View {
    @State private var healthManager = HealthManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if healthManager.sleepSamples.isEmpty {
                    ContentUnavailableView(
                        "暂无睡眠数据",
                        systemImage: "bed.double",
                        description: Text("请确保已佩戴 Apple Watch 入睡")
                    )
                    .padding(.top, 60)
                } else {
                    SleepSummaryView(samples: healthManager.sleepSamples)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal, DSLayout.horizontalPadding)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("睡眠")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if healthManager.sleepSamples.isEmpty {
                await healthManager.fetchTodaySleepData()
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if colorScheme == .dark {
            Color(red: 0.11, green: 0.11, blue: 0.12)
        } else {
            Color(.secondarySystemBackground)
        }
    }
}
