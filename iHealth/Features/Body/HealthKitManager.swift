//
//  HealthKitManager.swift
//  iHealth
//

import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthKitManager {

    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    var isAuthorized = false
    var authorizationError: String?

    private init() {}

    // MARK: - 授权

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let rhr = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(rhr)
        }
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "此设备不支持 HealthKit"
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            authorizationError = nil
        } catch {
            isAuthorized = false
            authorizationError = "授权失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 数据聚合

extension HealthKitManager {

    /// 便捷方法：拉取最近 N 天
    func fetchDailyMetrics(days: Int = 60) async -> [DailyMetrics] {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            return []
        }
        return await fetchDailyMetrics(from: startDate, to: endDate)
    }

    /// 按日期区间拉取每日指标
    func fetchDailyMetrics(from startDate: Date, to endDate: Date) async -> [DailyMetrics] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay   = calendar.startOfDay(for: endDate)

        // 计算天数（含首尾）
        guard let days = calendar.dateComponents([.day], from: startDay, to: endDay).day, days >= 0 else {
            return []
        }

        async let hrvMap   = fetchHRVDaily(startDate: startDay, endDate: endDate)
        async let rhrMap   = fetchRHRDaily(startDate: startDay, endDate: endDate)
        async let sleepMap = fetchSleepDaily(startDate: startDay, endDate: endDate)
        async let tssMap   = fetchTSSDaily(startDate: startDay, endDate: endDate)

        let hrv   = await hrvMap
        let rhr   = await rhrMap
        let sleep = await sleepMap
        let tss   = await tssMap

        var result: [DailyMetrics] = []
        for i in 0...days {
            guard let date = calendar.date(byAdding: .day, value: i, to: startDay) else { continue }
            let key = calendar.startOfDay(for: date)
            let s = sleep[key]

            result.append(
                DailyMetrics(
                    date: key,
                    hrv: hrv[key] ?? 0,
                    rhr: rhr[key] ?? 0,
                    sleepHours: s?.asleepHours ?? 0,
                    sleepEfficiency: s?.efficiency ?? 0,
                    deepSleepHours: s?.deep ?? 0,
                    remSleepHours: s?.rem ?? 0,
                    lightSleepHours: s?.light ?? 0,
                    tss: tss[key] ?? 0
                )
            )
        }
        return result
    }
}

// MARK: - HRV

extension HealthKitManager {

    private func fetchHRVDaily(startDate: Date, endDate: Date) async -> [Date: Double] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return [:]
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [:])
                    return
                }
                let calendar = Calendar.current
                var dailyMap: [Date: [Double]] = [:]
                for sample in samples {
                    let day = calendar.startOfDay(for: sample.startDate)
                    let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    dailyMap[day, default: []].append(value)
                }
                let result = dailyMap.mapValues { values in
                    values.reduce(0, +) / Double(values.count)
                }
                continuation.resume(returning: result)
            }
            self.healthStore.execute(query)
        }
    }
}

// MARK: - 静息心率

extension HealthKitManager {

    private func fetchRHRDaily(startDate: Date, endDate: Date) async -> [Date: Double] {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return [:]
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: rhrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [:])
                    return
                }
                let calendar = Calendar.current
                var dailyMap: [Date: [Double]] = [:]
                for sample in samples {
                    let day = calendar.startOfDay(for: sample.startDate)
                    let value = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                    dailyMap[day, default: []].append(value)
                }
                let result = dailyMap.mapValues { values in
                    values.reduce(0, +) / Double(values.count)
                }
                continuation.resume(returning: result)
            }
            self.healthStore.execute(query)
        }
    }
}

// MARK: - 睡眠（含阶段）

extension HealthKitManager {

    struct SleepAggregate {
        var asleepHours: Double
        var inBedHours: Double
        var deep: Double
        var rem: Double
        var light: Double
        var efficiency: Double
    }

    private func fetchSleepDaily(startDate: Date, endDate: Date) async -> [Date: SleepAggregate] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return [:]
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                let calendar = Calendar.current
                var inBedMap: [Date: Double] = [:]
                var deepMap: [Date: Double]   = [:]
                var remMap: [Date: Double]    = [:]
                var lightMap: [Date: Double]  = [:]

                for sample in samples {
                    let day = calendar.startOfDay(for: sample.endDate)
                    let duration = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                    guard duration > 0,
                          let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }

                    switch value {
                    case .inBed:
                        inBedMap[day, default: 0] += duration
                    case .asleepDeep:
                        deepMap[day, default: 0] += duration
                    case .asleepREM:
                        remMap[day, default: 0] += duration
                    case .asleepCore, .asleepUnspecified:
                        lightMap[day, default: 0] += duration
                    default:
                        break
                    }
                }

                var result: [Date: SleepAggregate] = [:]
                let allDays = Set(deepMap.keys).union(remMap.keys).union(lightMap.keys)
                for day in allDays {
                    let deep  = deepMap[day] ?? 0
                    let rem   = remMap[day] ?? 0
                    let light = lightMap[day] ?? 0
                    let asleep = deep + rem + light
                    let inBed = max(inBedMap[day] ?? asleep, asleep)
                    let efficiency = inBed > 0 ? min((asleep / inBed) * 100, 100) : 0
                    result[day] = SleepAggregate(
                        asleepHours: asleep,
                        inBedHours: inBed,
                        deep: deep,
                        rem: rem,
                        light: light,
                        efficiency: efficiency
                    )
                }
                continuation.resume(returning: result)
            }
            self.healthStore.execute(query)
        }
    }
}

// MARK: - 运动 TSS（TRIMP 心率区间加权）

extension HealthKitManager {

    private func fetchTSSDaily(startDate: Date, endDate: Date) async -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            self.healthStore.execute(query)
        }

        let calendar = Calendar.current
        var dailyTSS: [Date: Double] = [:]

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            let tss = await estimateTSS(for: workout)
            dailyTSS[day, default: 0] += tss
        }
        return dailyTSS
    }

    // MARK: 单次训练的 TSS

    private func estimateTSS(for workout: HKWorkout) async -> Double {
        let sport = SportType.from(workout: workout)
        let hours = workout.duration / 3600.0
        guard hours > 0 else { return 0 }

        let profile = AthleteProfileStore.shared
        let maxHR = profile.maxHR
        let thresholdHR = profile.thresholdHR(for: sport)

        // 拿到训练期间的心率样本
        let samples = await heartRateSamples(for: workout)

        // TRIMP 归一化参考值
        // 阈值心率所在区间权重 × 60 分钟
        let thresholdFraction = thresholdHR / maxHR
        let referenceZoneWeight = zoneWeight(for: thresholdFraction)
        let referenceTRIMP = 60.0 * referenceZoneWeight

        var baseTSS: Double = 0

        if !samples.isEmpty {
            // 用 TRIMP 计算强度
            // 样本在训练中近似均匀分布，用训练总时长 / 样本数 作为每个样本的时长
            let perSampleMinutes = (workout.duration / 60.0) / Double(samples.count)
            var trimp: Double = 0
            for sample in samples {
                let hr = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                guard hr > 0 else { continue }
                let fraction = hr / maxHR
                let w = zoneWeight(for: fraction)
                trimp += perSampleMinutes * w
            }
            baseTSS = trimp / referenceTRIMP * 100
        } else {
            // 无心率样本，回退到固定强度粗估
            baseTSS = hours * 50
        }

        var tss = baseTSS * sport.tssWeight

        // 登山/徒步：额外海拔加成（每 300m +10 TSS）
        if sport == .hiking || sport == .mountaineering {
            if let elevation = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
                let meters = elevation.doubleValue(for: .meter())
                tss += (meters / 300.0) * 10.0
            }
        }

        return max(tss, 0)
    }

    /// 心率区间权重（Edward's TRIMP 简化版）
    private func zoneWeight(for hrFraction: Double) -> Double {
        switch hrFraction {
        case ..<0.50:       return 0.5
        case 0.50..<0.60:   return 1.0
        case 0.60..<0.70:   return 2.0
        case 0.70..<0.80:   return 3.0
        case 0.80..<0.90:   return 4.0
        case 0.90...:       return 5.0
        default:            return 0.5
        }
    }

    /// 拉取某次训练期间的全部心率样本
    private func heartRateSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(query)
        }
    }
}
