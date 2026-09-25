//
//  VitalsCalculator.swift
//  iHealth
//
//  用睡眠样本计算四项生命体征平均值。
//  和 VitalsDetailView 口径一致。
//

import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class VitalsCalculator {
    static let shared = VitalsCalculator()

    private let healthManager = HealthManager.shared

    /// 缓存：日期 → VitalsData
    @ObservationIgnored private var cache: [Date: HealthManager.VitalsData] = [:]

    private init() {}

    /// 计算「今天」这一睡眠日的四项指标平均值
    func computeToday() async -> HealthManager.VitalsData {
        let day = Calendar.current.startOfDay(for: Date())
        return await compute(for: day)
    }

    func compute(for day: Date) async -> HealthManager.VitalsData {
        let key = Calendar.current.startOfDay(for: day)
        if let cached = cache[key] { return cached }

        let (sleepDayStart, sleepDayEnd) = SleepDay.window(for: day)
        let calendar = Calendar.current
        let queryStart = calendar.date(byAdding: .hour, value: -2, to: sleepDayStart)!
        let queryEnd = calendar.date(byAdding: .hour, value: 2, to: sleepDayEnd)!

        // 1. 拿睡眠区间
        let sleepRaw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)
        let intervals = mergedSleepIntervals(from: sleepRaw)

        // 2. 拿四项指标，按各自规则过滤后求平均
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

        let result = HealthManager.VitalsData(
            heartRate: average(inSleep: hr, intervals: intervals),
            respiratoryRate: average(inSleep: rr, intervals: intervals),
            wristTemperature: average(
                temp.filter { $0.date >= sleepDayStart && $0.date < sleepDayEnd }
            ),
            bloodOxygen: average(inSleep: ox, intervals: intervals)
        )

        cache[key] = result
        return result
    }

    /// 求平均值（传入的样本已经过滤过）
    private func average(_ samples: [VitalSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let sum = samples.reduce(0) { $0 + $1.value }
        return sum / Double(samples.count)
    }

    /// 按睡眠区间过滤后求平均
    private func average(inSleep samples: [VitalSample], intervals: [ClosedRange<Date>]) -> Double? {
        let filtered = samples.filter { sample in
            intervals.contains { $0.contains(sample.date) }
        }
        return average(filtered)
    }

    /// 合并 asleep* 段为连续时间区间
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

    /// 清空缓存（比如用户下拉刷新时）
    func invalidate() {
        cache.removeAll()
    }
}
