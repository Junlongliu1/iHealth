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
    /// 18:00 为界：日期 → 睡眠日窗口（前一日 18:00 ~ 当日 18:00）
    static func window(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: -6, to: dayStart)!
        let end   = calendar.date(byAdding: .hour, value: 18, to: dayStart)!
        return (start, end)
    }

    /// 某时刻属于哪一个睡眠日
    static func day(for date: Date) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        return hour >= 18
            ? calendar.date(byAdding: .day, value: 1, to: dayStart)!
            : dayStart
    }

    /// 合并 asleep* 段为连续时间区间（排除 awake / inBed）
    static func mergedIntervals(from samples: [HKCategorySample]) -> [ClosedRange<Date>] {
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
}

// MARK: - HealthManager

@MainActor
@Observable
final class HealthManager {
    static let shared = HealthManager()

    @ObservationIgnored private let healthStore = HKHealthStore()

    var activitySummary: HKActivitySummary?
    var sleepSamples: [HKCategorySample] = []
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
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]

        let optionalIdentifiers: [HKQuantityTypeIdentifier] = [
            .timeInDaylight,
            .basalEnergyBurned,
            .activeEnergyBurned,
            .restingHeartRate,
            .heartRateVariabilitySDNN
        ]
        for id in optionalIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                typesToRead.insert(type)
            }
        }

        for kind in VitalKind.allCases {
            if let type = HKQuantityType.quantityType(forIdentifier: kind.identifier) {
                typesToRead.insert(type)
            }
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            authorizationStatus = .sharingAuthorized

            async let summaryTask = fetchTodayActivitySummary()
            async let sleepTask = fetchTodaySleepData()
            _ = await (summaryTask, sleepTask)
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
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: summaries ?? []) }
                }
                healthStore.execute(query)
            }
            activitySummary = summaries.first
        } catch {
            AppLogError("查询活动摘要失败: \(error)")
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
            return allSamples.filter { $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue }
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

    // MARK: - 生命体征原始样本

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

    // MARK: - 步数（累计）

    func fetchStepCount(from startDate: Date, to endDate: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )

        do {
            let statistics = try await descriptor.result(for: healthStore)
            return statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        } catch {
            AppLogError("查询步数失败: \(error)")
            return 0
        }
    }

    func fetchStepSamples(from startDate: Date, to endDate: Date) async -> [VitalSample] {
        await fetchVitalSamples(
            identifier: .stepCount,
            unit: .count(),
            from: startDate,
            to: endDate
        )
    }
}

// MARK: - 通用查询引擎

extension HealthManager {

    /// 计算一天内按小时聚合的时间窗口。
    /// - 今天：0 点到当前小时
    /// - 历史某天：完整 0–23
    struct HourlyWindow {
        let start: Date
        let end: Date
        let maxHour: Int
    }

    func hourlyWindow(for day: Date) -> HourlyWindow {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let now = Date()
        if calendar.isDateInToday(day) {
            return HourlyWindow(start: start, end: now,
                                maxHour: calendar.component(.hour, from: now))
        } else {
            return HourlyWindow(
                start: start,
                end: calendar.date(byAdding: .day, value: 1, to: start)!,
                maxHour: 23
            )
        }
    }

    /// 按小时分桶的通用查询。
    /// - `transform`：对每个原始值做额外处理（例如血氧 0–1 → 0–100）
    func fetchHourlyBuckets(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        for day: Date,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> (values: [Int: Double], window: HourlyWindow) {
        let window = hourlyWindow(for: day)
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return ([:], window)
        }
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: window.start,
            intervalComponents: DateComponents(hour: 1)
        )
        let calendar = Calendar.current
        do {
            let collection = try await descriptor.result(for: healthStore)
            var byHour: [Int: Double] = [:]
            collection.enumerateStatistics(from: window.start, to: window.end) { stats, _ in
                let hour = calendar.component(.hour, from: stats.startDate)
                let q = options.contains(.cumulativeSum)
                    ? stats.sumQuantity()
                    : stats.averageQuantity()
                if let q { byHour[hour] = transform(q.doubleValue(for: unit)) }
            }
            return (byHour, window)
        } catch {
            AppLogError("查询每小时统计失败: \(error)")
            return ([:], window)
        }
    }

    /// 按天分桶的通用查询。
    func fetchDailyBuckets(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        from startDate: Date,
        to endDate: Date,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> [Date: Double] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: endDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: healthStore)
            var byDay: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: endDate) { stats, _ in
                let day = calendar.startOfDay(for: stats.startDate)
                let q = options.contains(.cumulativeSum)
                    ? stats.sumQuantity()
                    : stats.averageQuantity()
                if let q { byDay[day] = transform(q.doubleValue(for: unit)) }
            }
            return byDay
        } catch {
            AppLogError("查询每日统计失败: \(error)")
            return [:]
        }
    }

    /// 把 `[Date: Double]` 展开为按天连续序列，缺失天通过 `build` 决定如何填充。
    func expandDailySeries<Item: Identifiable>(
        _ byDay: [Date: Double],
        from startDate: Date,
        to endDate: Date,
        build: (Date, Double?) -> Item
    ) -> [Item] {
        let calendar = Calendar.current
        var result: [Item] = []
        var current = calendar.startOfDay(for: startDate)
        while current < endDate {
            result.append(build(current, byDay[current]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }
}

// MARK: - 各指标 API（薄包装）

extension HealthManager {

    // MARK: 步数

    func fetchHourlySteps(for day: Date) async -> [HourlySteps] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .stepCount, unit: .count(),
            options: .cumulativeSum, for: day
        )
        return (0...window.maxHour).map { HourlySteps(hour: $0, steps: byHour[$0] ?? 0) }
    }

    func fetchTodayHourlySteps() async -> [HourlySteps] {
        await fetchHourlySteps(for: Date())
    }

    func fetchDailySteps(from startDate: Date, to endDate: Date) async -> [DailySteps] {
        let byDay = await fetchDailyBuckets(
            identifier: .stepCount, unit: .count(),
            options: .cumulativeSum, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailySteps(date: $0, steps: $1 ?? 0)
        }
    }

    // MARK: 日照

    func fetchHourlyDaylight(for day: Date) async -> [HourlyDaylight] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .timeInDaylight, unit: .minute(),
            options: .cumulativeSum, for: day
        )
        return (0...window.maxHour).map { HourlyDaylight(hour: $0, minutes: byHour[$0] ?? 0) }
    }

    func fetchTodayHourlyDaylight() async -> [HourlyDaylight] {
        await fetchHourlyDaylight(for: Date())
    }

    func fetchDailyDaylight(from startDate: Date, to endDate: Date) async -> [DailyDaylight] {
        let byDay = await fetchDailyBuckets(
            identifier: .timeInDaylight, unit: .minute(),
            options: .cumulativeSum, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyDaylight(date: $0, minutes: $1 ?? 0)
        }
    }

    // MARK: 基础代谢

    func fetchHourlyBasalEnergy(for day: Date) async -> [HourlyBasalEnergy] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .basalEnergyBurned, unit: .kilocalorie(),
            options: .cumulativeSum, for: day
        )
        return (0...window.maxHour).map { HourlyBasalEnergy(hour: $0, kilocalories: byHour[$0] ?? 0) }
    }

    func fetchTodayHourlyBasalEnergy() async -> [HourlyBasalEnergy] {
        await fetchHourlyBasalEnergy(for: Date())
    }

    func fetchDailyBasalEnergy(from startDate: Date, to endDate: Date) async -> [DailyBasalEnergy] {
        let byDay = await fetchDailyBuckets(
            identifier: .basalEnergyBurned, unit: .kilocalorie(),
            options: .cumulativeSum, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyBasalEnergy(date: $0, kilocalories: $1 ?? 0)
        }
    }

    // MARK: 活动消耗

    func fetchHourlyActiveEnergy(for day: Date) async -> [HourlyActiveEnergy] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .activeEnergyBurned, unit: .kilocalorie(),
            options: .cumulativeSum, for: day
        )
        return (0...window.maxHour).map { HourlyActiveEnergy(hour: $0, kilocalories: byHour[$0] ?? 0) }
    }

    func fetchTodayHourlyActiveEnergy() async -> [HourlyActiveEnergy] {
        await fetchHourlyActiveEnergy(for: Date())
    }

    func fetchDailyActiveEnergy(from startDate: Date, to endDate: Date) async -> [DailyActiveEnergy] {
        let byDay = await fetchDailyBuckets(
            identifier: .activeEnergyBurned, unit: .kilocalorie(),
            options: .cumulativeSum, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyActiveEnergy(date: $0, kilocalories: $1 ?? 0)
        }
    }

    // MARK: 心率

    private var bpmUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    func fetchHourlyHeartRate(for day: Date) async -> [HourlyHeartRate] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .heartRate, unit: bpmUnit,
            options: .discreteAverage, for: day
        )
        return (0...window.maxHour).map { HourlyHeartRate(hour: $0, bpm: byHour[$0]) }
    }

    func fetchTodayHourlyHeartRate() async -> [HourlyHeartRate] {
        await fetchHourlyHeartRate(for: Date())
    }

    func fetchDailyHeartRate(from startDate: Date, to endDate: Date) async -> [DailyHeartRate] {
        let byDay = await fetchDailyBuckets(
            identifier: .heartRate, unit: bpmUnit,
            options: .discreteAverage, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyHeartRate(date: $0, bpm: $1)
        }
    }

    // MARK: 血氧

    private static let percentTransform: (Double) -> Double = { v in v <= 1.0 ? v * 100 : v }

    func fetchHourlyBloodOxygen(for day: Date) async -> [HourlyBloodOxygen] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .oxygenSaturation, unit: .percent(),
            options: .discreteAverage, for: day,
            transform: Self.percentTransform
        )
        return (0...window.maxHour).map { HourlyBloodOxygen(hour: $0, percent: byHour[$0]) }
    }

    func fetchTodayHourlyBloodOxygen() async -> [HourlyBloodOxygen] {
        await fetchHourlyBloodOxygen(for: Date())
    }

    func fetchDailyBloodOxygen(from startDate: Date, to endDate: Date) async -> [DailyBloodOxygen] {
        let byDay = await fetchDailyBuckets(
            identifier: .oxygenSaturation, unit: .percent(),
            options: .discreteAverage, from: startDate, to: endDate,
            transform: Self.percentTransform
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyBloodOxygen(date: $0, percent: $1)
        }
    }

    // MARK: 静息心率

    func fetchHourlyRestingHeartRate(for day: Date) async -> [HourlyRestingHeartRate] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .restingHeartRate, unit: bpmUnit,
            options: .discreteAverage, for: day
        )
        return (0...window.maxHour).map { HourlyRestingHeartRate(hour: $0, bpm: byHour[$0]) }
    }

    func fetchTodayHourlyRestingHeartRate() async -> [HourlyRestingHeartRate] {
        await fetchHourlyRestingHeartRate(for: Date())
    }

    func fetchDailyRestingHeartRate(from startDate: Date, to endDate: Date) async -> [DailyRestingHeartRate] {
        let byDay = await fetchDailyBuckets(
            identifier: .restingHeartRate, unit: bpmUnit,
            options: .discreteAverage, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyRestingHeartRate(date: $0, bpm: $1)
        }
    }

    // MARK: 心率变异性

    private var hrvUnit: HKUnit { HKUnit.secondUnit(with: .milli) }

    func fetchHourlyHeartRateVariability(for day: Date) async -> [HourlyHeartRateVariability] {
        let (byHour, window) = await fetchHourlyBuckets(
            identifier: .heartRateVariabilitySDNN, unit: hrvUnit,
            options: .discreteAverage, for: day
        )
        return (0...window.maxHour).map { HourlyHeartRateVariability(hour: $0, milliseconds: byHour[$0]) }
    }

    func fetchTodayHourlyHeartRateVariability() async -> [HourlyHeartRateVariability] {
        await fetchHourlyHeartRateVariability(for: Date())
    }

    func fetchDailyHeartRateVariability(from startDate: Date, to endDate: Date) async -> [DailyHeartRateVariability] {
        let byDay = await fetchDailyBuckets(
            identifier: .heartRateVariabilitySDNN, unit: hrvUnit,
            options: .discreteAverage, from: startDate, to: endDate
        )
        return expandDailySeries(byDay, from: startDate, to: endDate) {
            DailyHeartRateVariability(date: $0, milliseconds: $1)
        }
    }
}
