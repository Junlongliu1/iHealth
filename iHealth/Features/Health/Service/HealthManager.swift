//
//  HealthManager.swift
//  iHealth
//
//  HealthKit 数据管理器（单例）。
//  与苹果健康保持一致的睡眠查询：按「睡眠日」18:00–18:00 归属。
//  isLoading 只在首次加载时使用，切 tab 回来时静默刷新。
//

import HealthKit
import Observation

// MARK: - 睡眠日工具（与苹果健康口径一致）

enum SleepDay {
    /// 一天对应的「睡眠日」窗口：[前一天 18:00, 当天 18:00]
    static func window(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: -6, to: dayStart)!
        let end   = calendar.date(byAdding: .hour, value: 18, to: dayStart)!
        return (start, end)
    }

    /// 给定一个时刻，返回它所属「睡眠日」的当天 0 点
    /// 18:00 之后算作次日，18:00 之前算作当日
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

    /// 是否已经完成过一次完整加载（授权 + 三类数据）
    private var hasLoadedOnce = false

    private init() {}

    // MARK: - 生命体征数据结构

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

        // 只有首次进入才显示全屏 loading；切 tab 回来时静默刷新
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
            // 只在值真的发生变化时才更新，避免不必要的重绘
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

    /// 今日（按「睡眠日」口径）的睡眠数据
    func fetchTodaySleepData() async {
        let (start, end) = SleepDay.window(for: Date())
        let raw = await fetchSleepSamples(from: start, to: end)
        let fetched = raw.filter { $0.startDate >= start && $0.startDate < end }

        // 只在内容不同时才赋值，避免触发无谓的视图重建
        if !sameSamples(sleepSamples, fetched) {
            sleepSamples = fetched
        }
    }

    /// 通用查询：取指定时间范围内所有睡眠样本（保留 asleep* 与 awake，排除 inBed）
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

    /// 判断两组睡眠样本是否等价（数量 + 起止时间 + 阶段）
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
}
