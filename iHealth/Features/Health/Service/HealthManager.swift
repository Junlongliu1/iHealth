//
//  HealthManager.swift
//  iHealth
//
//  HealthKit 数据管理器（单例）。
//  负责请求活动摘要、睡眠、生命体征数据的读取权限，
//  查询今日相关数据供健康页面展示。
//

import HealthKit
import Observation

@MainActor
@Observable
final class HealthManager {
    static let shared = HealthManager()

    @ObservationIgnored private let healthStore = HKHealthStore()

    var activitySummary: HKActivitySummary?
    var sleepSamples: [HKCategorySample] = []
    var vitals: VitalsData?
    var isLoading = false
    var authorizationStatus: HKAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: - 生命体征数据结构

    struct VitalsData {
        var heartRate: Double?          // 心率（次/分）
        var respiratoryRate: Double?    // 呼吸频率（次/分）
        var wristTemperature: Double?   // 手腕温度（°C）
        var bloodOxygen: Double?        // 血氧（%）
    }

    // MARK: - 授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            AppLogWarn("HealthKit 在此设备上不可用")
            return
        }

        var typesToRead: Set<HKObjectType> = [
            HKObjectType.activitySummaryType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        let vitalsIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .oxygenSaturation
        ]
        for id in vitalsIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                typesToRead.insert(type)
            }
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            authorizationStatus = .sharingAuthorized

            async let summaryTask = fetchTodayActivitySummary()
            async let sleepTask = fetchTodaySleepData()
            async let vitalsTask = fetchTodayVitals()
            _ = await (summaryTask, sleepTask, vitalsTask)
        } catch {
            AppLogError("HealthKit 授权失败: \(error)")
            authorizationStatus = .sharingDenied
        }
    }

    // MARK: - 活动摘要

    func fetchTodayActivitySummary() async {
        isLoading = true
        defer { isLoading = false }

        var today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        today.calendar = Calendar.current

        let predicate = HKQuery.predicateForActivitySummary(with: today)

        do {
            let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { cont in
                let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: summaries ?? [])
                    }
                }
                healthStore.execute(query)
            }
            activitySummary = summaries.first
        } catch {
            AppLogError("查询活动摘要失败: \(error)")
            activitySummary = nil
        }
    }

    // MARK: - 睡眠数据

    /// 今日睡眠数据（供健康首页使用）
    func fetchTodaySleepData() async {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        sleepSamples = await fetchSleepSamples(from: startDate, to: endDate)
    }

    /// 通用查询：获取指定时间范围内的睡眠样本（已排除“在床上”）
    func fetchSleepSamples(from startDate: Date, to endDate: Date) async -> [HKCategorySample] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let allSamples = try await descriptor.result(for: healthStore)
            return allSamples.filter { sample in
                sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue
            }
        } catch {
            AppLogError("查询睡眠数据失败: \(error)")
            return []
        }
    }

    // MARK: - 生命体征

    func fetchTodayVitals() async {
        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .hour, value: -16, to: endDate) else {
            vitals = VitalsData()
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        let perMinute = HKUnit.count().unitDivided(by: .minute())

        async let hr = fetchAverage(.heartRate, predicate: predicate, unit: perMinute)
        async let rr = fetchAverage(.respiratoryRate, predicate: predicate, unit: perMinute)
        async let temp = fetchAverage(.appleSleepingWristTemperature, predicate: predicate, unit: .degreeCelsius())
        async let ox = fetchAverage(.oxygenSaturation, predicate: predicate, unit: .percent())

        vitals = VitalsData(
            heartRate: await hr,
            respiratoryRate: await rr,
            wristTemperature: await temp,
            bloodOxygen: await ox
        )
    }

    private func fetchAverage(
        _ identifier: HKQuantityTypeIdentifier,
        predicate: NSPredicate,
        unit: HKUnit
    ) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )

        guard let stats = try? await descriptor.result(for: healthStore),
              let quantity = stats.averageQuantity() else {
            return nil
        }

        var value = quantity.doubleValue(for: unit)

        if identifier == .oxygenSaturation && value <= 1.0 {
            value *= 100
        }

        return value
    }
}
