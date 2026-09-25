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
            todayVitals = await computeSleepVitals()
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

                    Text(formatTotal(summary.total))
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
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
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
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
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

    // MARK: - 格式化
    private func formatTotal(_ t: TimeInterval) -> String {
        guard t > 0 else { return "0分" }
        let totalMinutes = Int(t / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)小时\(m)分" : "\(m)分"
    }

    // MARK: - 睡眠期间生命体征（与详情页口径一致）

    /// 计算睡眠期间四项指标的平均值
    /// - 心率 / 呼吸 / 血氧：过滤到「真正睡着」的时间区间
    /// - 手腕温度：只保留睡眠日窗口内的样本（它本来只在睡眠时采集）
    private func computeSleepVitals() async -> HealthManager.VitalsData {
        let sleepSamples = healthManager.sleepSamples
        guard !sleepSamples.isEmpty else {
            return HealthManager.VitalsData()
        }

        // 1. 合并 asleep* 段为连续区间
        let intervals = mergedSleepIntervals(from: sleepSamples)
        guard let firstInterval = intervals.first,
              let lastInterval = intervals.last else {
            return HealthManager.VitalsData()
        }

        // 2. 查询窗口：最早入睡前 2h ~ 最晚醒来后 2h
        let calendar = Calendar.current
        let queryStart = calendar.date(byAdding: .hour, value: -2, to: firstInterval.lowerBound)!
        let queryEnd = calendar.date(byAdding: .hour, value: 2, to: lastInterval.upperBound)!

        // 3. 并发拉取四类样本
        async let hrSamples = healthManager.fetchVitalSamples(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: queryStart, to: queryEnd
        )
        async let rrSamples = healthManager.fetchVitalSamples(
            identifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: queryStart, to: queryEnd
        )
        async let tempSamples = healthManager.fetchVitalSamples(
            identifier: .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            from: queryStart, to: queryEnd
        )
        async let oxSamples = healthManager.fetchVitalSamples(
            identifier: .oxygenSaturation,
            unit: .percent(),
            from: queryStart, to: queryEnd,
            percentFix: true
        )

        let (hr, rr, temp, ox) = await (hrSamples, rrSamples, tempSamples, oxSamples)

        // 4. 过滤 + 求平均
        //    手腕温度直接使用（本来就只在睡眠期间采集）
        return HealthManager.VitalsData(
            heartRate: averageInSleep(hr, intervals: intervals),
            respiratoryRate: averageInSleep(rr, intervals: intervals),
            wristTemperature: average(temp),
            bloodOxygen: averageInSleep(ox, intervals: intervals)
        )
    }

    /// 求平均值
    private func average(_ samples: [VitalSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sum = samples.reduce(0) { $0 + $1.value }
        return sum / Double(samples.count)
    }

    /// 先按睡眠区间过滤，再求平均
    private func averageInSleep(_ samples: [VitalSample], intervals: [ClosedRange<Date>]) -> Double? {
        let filtered = samples.filter { sample in
            intervals.contains { $0.contains(sample.date) }
        }
        return average(filtered)
    }

    /// 把 asleep* 段合并成连续时间区间，排除 awake / inBed
    private func mergedSleepIntervals(from samples: [HKCategorySample]) -> [ClosedRange<Date>] {
        let asleep = samples
            .filter { s in
                guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return false }
                return v != .awake && v != .inBed
            }
            .sorted { $0.startDate < $1.startDate }

        var intervals: [ClosedRange<Date>] = []
        for s in asleep {
            if let last = intervals.last, s.startDate <= last.upperBound {
                let newUpper = max(last.upperBound, s.endDate)
                intervals[intervals.count - 1] = last.lowerBound...newUpper
            } else {
                intervals.append(s.startDate...s.endDate)
            }
        }
        return intervals
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
