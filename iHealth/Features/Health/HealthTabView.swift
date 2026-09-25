//
//  HealthTabView.swift
//  iHealth
//
//  健康标签页主视图。
//  仅适配 iOS 26+。
//

import SwiftUI
import HealthKit

struct HealthTabView: View {
    @State private var healthManager = HealthManager.shared
    @State private var todayVitals: HealthManager.VitalsData?
    @State private var todayHourlySteps: [HourlySteps] = []

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

                        NavigationLink {
                            StepsDetailView()
                        } label: {
                            StepsCard(hourly: todayHourlySteps)
                        }
                        .buttonStyle(.plain)
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

            async let vitals = VitalsCalculator.shared.computeToday()
            async let steps = healthManager.fetchTodayHourlySteps()

            todayVitals = await vitals
            todayHourlySteps = await steps
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
        .cardStyle(radius: 14)
        .padding(.top, 24)
    }

    // MARK: - 睡眠卡片

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

                    Text(summary.total.hourMinuteText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    SleepChartView(samples: healthManager.sleepSamples, showsAxes: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .cardStyle(radius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 生命体征卡片（可点击进入详情）

    private var vitalsCard: some View {
        let sleepDuration = healthManager.sleepSamples.isEmpty
            ? nil
            : SleepSummary(samples: healthManager.sleepSamples).total

        return NavigationLink {
            VitalsDetailView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(
                    icon: "heart.text.square.fill",
                    iconColor: .pink,
                    title: "生命体征",
                    trailing: "夜间",
                    showsChevron: true
                )

                VitalsDotChart(
                    vitals: todayVitals,
                    sleepDuration: sleepDuration
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .cardStyle(radius: 14)
        }
        .buttonStyle(.plain)
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
}
