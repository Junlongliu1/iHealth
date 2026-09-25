//
//  VitalsCalculator.swift
//  iHealth
//
//  用睡眠样本计算四项生命体征平均值。
//  同时对外提供样本序列，供详情页画图使用，保证口径统一。
//

import Foundation
import HealthKit
import Observation

/// 一个睡眠日的完整生命体征数据
struct DayVitals {
    var samples: [VitalKind: [VitalSample]]
    var averages: HealthManager.VitalsData

    static let empty = DayVitals(samples: [:], averages: HealthManager.VitalsData())
}

@MainActor
@Observable
final class VitalsCalculator {
    static let shared = VitalsCalculator()

    private let healthManager = HealthManager.shared

    @ObservationIgnored private var cache: [Date: DayVitals] = [:]

    private init() {}

    /// 首页用：今天这一睡眠日的四项指标平均值
    func computeToday() async -> HealthManager.VitalsData {
        let day = Calendar.current.startOfDay(for: Date())
        return await dayData(for: day).averages
    }

    /// 详情页 / 首页共用：某睡眠日的完整数据（样本 + 平均值）
    func dayData(for day: Date) async -> DayVitals {
        let key = Calendar.current.startOfDay(for: day)
        if let cached = cache[key] { return cached }

        let (sleepDayStart, sleepDayEnd) = SleepDay.window(for: day)
        let calendar = Calendar.current
        let queryStart = calendar.date(byAdding: .hour, value: -2, to: sleepDayStart)!
        let queryEnd = calendar.date(byAdding: .hour, value: 2, to: sleepDayEnd)!

        // 1. 睡眠区间
        let sleepRaw = await healthManager.fetchSleepSamples(from: queryStart, to: queryEnd)
        let intervals = SleepDay.mergedIntervals(from: sleepRaw)

        // 2. 四项指标按各自规则过滤
        var samples: [VitalKind: [VitalSample]] = [:]
        for kind in VitalKind.allCases {
            let raw = await healthManager.fetchVitalSamples(
                identifier: kind.identifier,
                unit: kind.unitHK,
                from: queryStart,
                to: queryEnd,
                percentFix: kind.needsPercentFix
            )

            if kind.isSleepOnly {
                samples[kind] = raw.filter {
                    $0.date >= sleepDayStart && $0.date < sleepDayEnd
                }
            } else {
                samples[kind] = raw.filter { sample in
                    intervals.contains { $0.contains(sample.date) }
                }
            }
        }

        // 3. 平均值
        let averages = HealthManager.VitalsData(
            heartRate: samples[.heartRate]?.averageValue,
            respiratoryRate: samples[.respiratoryRate]?.averageValue,
            wristTemperature: samples[.wristTemperature]?.averageValue,
            bloodOxygen: samples[.bloodOxygen]?.averageValue
        )

        let result = DayVitals(samples: samples, averages: averages)
        cache[key] = result
        return result
    }

    /// 清空缓存（下拉刷新时使用）
    func invalidate() {
        cache.removeAll()
    }
}
