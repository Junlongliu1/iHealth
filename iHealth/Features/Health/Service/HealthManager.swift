//
//  HealthManager.swift
//  iHealth
//
//  HealthKit 数据管理器（单例）。
//

import HealthKit
import Observation

// MARK: - 生命体征样本

struct VitalSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - 睡眠日工具

enum SleepDay {
    static func window(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: -6, to: dayStart)!
        let end   = calendar.date(byAdding: .hour, value: 18, to: dayStart)!
        return (start, end)
    }

    static func day(for date: Date) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        return hour >= 18
            ? calendar.date(byAdding: .day, value: 1, to: dayStart)!
            : dayStart
    }
}

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

    private var hasLoadedOnce = false

    private init() {}

    struct VitalsData {
        var heartRate: Double?
        var respiratoryRate: Double?
        var wristTemperature: Double?
        var bloodOxygen: Double?
    }

    // MARK: - 授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            AppLogWarn("HealthKit 在此设备上不可用")
            return
        }

        let isFirstLoad = !hasLoadedOnce
        if isFirstLoad { isLoading = true }

        defer {
            if isFirstLoad {
                isLoading = false
                hasLoadedOnce = true
            }
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
            if activitySummary?.activeEnergyBurned != summaries.first?.activeEnergyBurned
                || activitySummary?.appleExerciseTime != summaries.first?.appleExerciseTime
                || activitySummary?.appleStandHours != summaries.first?.appleStandHours {
                activitySummary = summaries.first
            }
        } catch {
            AppLogError("查询活动摘要失败: \(error)")
            if activitySummary == nil { activitySummary = nil }
        }
    }

    // MARK: - 睡眠数据

    func fetchTodaySleepData() async {
        let (start, end) = SleepDay.window(for: Date())
        let raw = await fetchSleepSamples(from: start, to: end)
        let fetched = raw.filter { $0.startDate >= start && $0.startDate < end }
        if !sameSamples(sleepSamples, fetched) {
            sleepSamples = fetched
        }
    }

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

    private func sameSamples(_ a: [HKCategorySample], _ b: [HKCategorySample]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            if x.startDate != y.startDate || x.endDate != y.endDate || x.value != y.value {
                return false
            }
        }
        return true
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

    /// 通用查询：取指定时间范围内某类指标的原始样本
    func fetchVitalSamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date,
        percentFix: Bool = false
    ) async -> [VitalSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            return samples.map { s in
                var value = s.quantity.doubleValue(for: unit)
                if percentFix && value <= 1.0 { value *= 100 }
                return VitalSample(date: s.startDate, value: value)
            }
        } catch {
            AppLogError("查询生命体征样本失败: \(error)")
            return []
        }
    }

    /// ★ 建立个人基线用：取过去 N 天，按「睡眠日」聚合出每天的平均值
    func fetchDailyAverages(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int,
        percentFix: Bool = false
    ) async -> [Double] {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }

        let samples = await fetchVitalSamples(
            identifier: identifier,
            unit: unit,
            from: start,
            to: end,
            percentFix: percentFix
        )

        var byDay: [Date: [Double]] = [:]
        for s in samples {
            let day = SleepDay.day(for: s.date)
            byDay[day, default: []].append(s.value)
        }

        return byDay.values.map { values in
            values.reduce(0, +) / Double(values.count)
        }
    }
}
