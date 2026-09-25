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

        // 日照时间（Time in Daylight）
        if let daylightType = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) {
            typesToRead.insert(daylightType)
        }

        // 基础代谢（Basal Energy Burned）
        if let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) {
            typesToRead.insert(basalType)
        }

        // 活动消耗（Active Energy Burned）
        if let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            typesToRead.insert(activeType)
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

    // MARK: - 步数

    /// 查询指定时间范围内的累计步数
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

    /// 指定日期按小时分组的步数。
    /// - 今天：从 0 点到当前小时
    /// - 历史某天：0–23 完整返回，缺失小时补 0
    func fetchHourlySteps(for day: Date) async -> [HourlySteps] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let now = Date()
        let isToday = calendar.isDateInToday(day)

        let end: Date
        let maxHour: Int
        if isToday {
            end = now
            maxHour = calendar.component(.hour, from: now)
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: start)!
            maxHour = 23
        }

        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byHour: [Int: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                let hour = calendar.component(.hour, from: statistics.startDate)
                byHour[hour] = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            }

            return (0...maxHour).map { hour in
                HourlySteps(hour: hour, steps: byHour[hour] ?? 0)
            }
        } catch {
            AppLogError("查询每小时步数失败: \(error)")
            return []
        }
    }

    /// 今日每小时步数（0 点至当前小时）
    func fetchTodayHourlySteps() async -> [HourlySteps] {
        await fetchHourlySteps(for: Date())
    }

    /// 指定日期区间按天分组的步数，返回从 start 到 end 前一天的完整序列。
    func fetchDailySteps(from startDate: Date, to endDate: Date) async -> [DailySteps] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)

        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: endDate)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byDay: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: endDate) { statistics, _ in
                let day = calendar.startOfDay(for: statistics.startDate)
                byDay[day] = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            }

            var days: [DailySteps] = []
            var current = start
            while current < endDate {
                days.append(DailySteps(date: current, steps: byDay[current] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            return days
        } catch {
            AppLogError("查询每日步数失败: \(error)")
            return []
        }
    }

    /// 某一小时内的原始步数样本（用于小时详情页）
    func fetchStepSamples(from startDate: Date, to endDate: Date) async -> [VitalSample] {
        await fetchVitalSamples(
            identifier: .stepCount,
            unit: .count(),
            from: startDate,
            to: endDate
        )
    }

    // MARK: - 日照

    /// 指定日期按小时分组的日照时长（分钟）。
    /// - 今天：从 0 点到当前小时
    /// - 历史某天：0–23 完整返回，缺失小时补 0
    func fetchHourlyDaylight(for day: Date) async -> [HourlyDaylight] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let now = Date()
        let isToday = calendar.isDateInToday(day)

        let end: Date
        let maxHour: Int
        if isToday {
            end = now
            maxHour = calendar.component(.hour, from: now)
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: start)!
            maxHour = 23
        }

        guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byHour: [Int: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                let hour = calendar.component(.hour, from: statistics.startDate)
                byHour[hour] = statistics.sumQuantity()?.doubleValue(for: .minute()) ?? 0
            }

            return (0...maxHour).map { hour in
                HourlyDaylight(hour: hour, minutes: byHour[hour] ?? 0)
            }
        } catch {
            AppLogError("查询每小时日照失败: \(error)")
            return []
        }
    }

    /// 今日每小时日照（0 点至当前小时）
    func fetchTodayHourlyDaylight() async -> [HourlyDaylight] {
        await fetchHourlyDaylight(for: Date())
    }

    /// 指定日期区间按天分组的日照时长（分钟）
    func fetchDailyDaylight(from startDate: Date, to endDate: Date) async -> [DailyDaylight] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)

        guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: endDate)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byDay: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: endDate) { statistics, _ in
                let day = calendar.startOfDay(for: statistics.startDate)
                byDay[day] = statistics.sumQuantity()?.doubleValue(for: .minute()) ?? 0
            }

            var days: [DailyDaylight] = []
            var current = start
            while current < endDate {
                days.append(DailyDaylight(date: current, minutes: byDay[current] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            return days
        } catch {
            AppLogError("查询每日日照失败: \(error)")
            return []
        }
    }
    
    // MARK: - 基础代谢

    /// 指定日期按小时分组的基础代谢（大卡）。
    /// - 今天：从 0 点到当前小时
    /// - 历史某天：0–23 完整返回，缺失小时补 0
    func fetchHourlyBasalEnergy(for day: Date) async -> [HourlyBasalEnergy] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let now = Date()
        let isToday = calendar.isDateInToday(day)

        let end: Date
        let maxHour: Int
        if isToday {
            end = now
            maxHour = calendar.component(.hour, from: now)
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: start)!
            maxHour = 23
        }

        guard let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byHour: [Int: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                let hour = calendar.component(.hour, from: statistics.startDate)
                byHour[hour] = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }

            return (0...maxHour).map { hour in
                HourlyBasalEnergy(hour: hour, kilocalories: byHour[hour] ?? 0)
            }
        } catch {
            AppLogError("查询每小时基础代谢失败: \(error)")
            return []
        }
    }

    /// 今日每小时基础代谢（0 点至当前小时）
    func fetchTodayHourlyBasalEnergy() async -> [HourlyBasalEnergy] {
        await fetchHourlyBasalEnergy(for: Date())
    }

    /// 指定日期区间按天分组的基础代谢（大卡）
    func fetchDailyBasalEnergy(from startDate: Date, to endDate: Date) async -> [DailyBasalEnergy] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)

        guard let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: endDate)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byDay: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: endDate) { statistics, _ in
                let day = calendar.startOfDay(for: statistics.startDate)
                byDay[day] = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }

            var days: [DailyBasalEnergy] = []
            var current = start
            while current < endDate {
                days.append(DailyBasalEnergy(date: current, kilocalories: byDay[current] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            return days
        } catch {
            AppLogError("查询每日基础代谢失败: \(error)")
            return []
        }
    }
    
    // MARK: - 活动消耗

    /// 指定日期按小时分组的活动消耗（大卡）。
    /// - 今天：从 0 点到当前小时
    /// - 历史某天：0–23 完整返回，缺失小时补 0
    func fetchHourlyActiveEnergy(for day: Date) async -> [HourlyActiveEnergy] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let now = Date()
        let isToday = calendar.isDateInToday(day)

        let end: Date
        let maxHour: Int
        if isToday {
            end = now
            maxHour = calendar.component(.hour, from: now)
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: start)!
            maxHour = 23
        }

        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byHour: [Int: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                let hour = calendar.component(.hour, from: statistics.startDate)
                byHour[hour] = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }

            return (0...maxHour).map { hour in
                HourlyActiveEnergy(hour: hour, kilocalories: byHour[hour] ?? 0)
            }
        } catch {
            AppLogError("查询每小时活动消耗失败: \(error)")
            return []
        }
    }

    /// 今日每小时活动消耗（0 点至当前小时）
    func fetchTodayHourlyActiveEnergy() async -> [HourlyActiveEnergy] {
        await fetchHourlyActiveEnergy(for: Date())
    }

    /// 指定日期区间按天分组的活动消耗（大卡）
    func fetchDailyActiveEnergy(from startDate: Date, to endDate: Date) async -> [DailyActiveEnergy] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)

        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: endDate)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)

            var byDay: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: endDate) { statistics, _ in
                let day = calendar.startOfDay(for: statistics.startDate)
                byDay[day] = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }

            var days: [DailyActiveEnergy] = []
            var current = start
            while current < endDate {
                days.append(DailyActiveEnergy(date: current, kilocalories: byDay[current] ?? 0))
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            return days
        } catch {
            AppLogError("查询每日活动消耗失败: \(error)")
            return []
        }
    }
}
