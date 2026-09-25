//
//  HealthTabView.swift
//  iHealth
//
//  健康标签页主视图。
//  展示活动圆环卡片（全宽）和睡眠、生命体征两个正方形卡片。
//  仅适配 iOS 26+。
//

import SwiftUI
import HealthKit

struct HealthTabView: View {
    @State private var healthManager = HealthManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if healthManager.isLoading {
                    ProgressView("加载中...")
                        .padding(.top, 40)
                } else {
                    ringsCard

                    LazyVGrid(columns: columns, spacing: 14) {
                        sleepCard
                        vitalsCard
                    }
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

    // MARK: - 活动圆环卡片（全宽）
    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("活动圆环")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)

            HStack(spacing: 48) {
                ActivityRingsView(summary: healthManager.activitySummary)
                    .frame(width: 110, height: 110)

                if let summary = healthManager.activitySummary {
                    RingsSummaryDetails(summary: summary)
                } else {
                    Text("暂无数据")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
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
        .padding(.top, 24)
    }

    // MARK: - 睡眠卡片（正方形：总时长 + 阶段图）
    private var sleepCard: some View {
        NavigationLink {
            SleepDetailView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "bed.double.fill",
                    iconColor: .indigo,
                    title: "睡眠",
                    showsChevron: true
                )

                if healthManager.sleepSamples.isEmpty {
                    Spacer(minLength: 0)
                    Text("暂无数据")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                } else {
                    let summary = SleepSummary(samples: healthManager.sleepSamples)

                    Text(formatTotal(summary.total))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    SleepChartView(samples: healthManager.sleepSamples, showsAxes: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 生命体征卡片（点状图）
    private var vitalsCard: some View {
        let sleepDuration = healthManager.sleepSamples.isEmpty
            ? nil
            : SleepSummary(samples: healthManager.sleepSamples).total

        return VStack(alignment: .leading, spacing: 10) {
            cardHeader(
                icon: "heart.text.square.fill",
                iconColor: .pink,
                title: "生命体征",
                trailing: "夜间"
            )

            VitalsDotChart(
                vitals: healthManager.vitals,
                sleepDuration: sleepDuration
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 通用卡片标题
    private func cardHeader(
        icon: String,
        iconColor: Color,
        title: String,
        trailing: String? = nil,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 格式化
    private func formatTotal(_ t: TimeInterval) -> String {
        guard t > 0 else { return "0分" }
        let totalMinutes = Int(t / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)小时\(m)分" : "\(m)分"
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
