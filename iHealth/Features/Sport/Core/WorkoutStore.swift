//
//  WorkoutStore.swift
//  iHealth
//

import Foundation
import Observation
import HealthKit
import CoreLocation

@Observable
final class WorkoutStore {

    // MARK: - 共享 HealthKit Store

    /// 全 App 共享的唯一 HKHealthStore 实例（见 HealthStoreShared.swift）
    private let healthStore = HKHealthStore.shared

    // MARK: - 状态

    var workouts: [Workout] = []
    var isLoading = false
    var errorMessage: String?

    var splitsCache: [UUID: [KilometerSplit]] = [:]
    var personalBests: [PersonalBest] = []
    private var hasLoadedSplits = false

    // MARK: - 授权读取类型（静态构建，只跑一次）

    private static let typesToRead: Set<HKObjectType> = {
        var set: Set<HKObjectType> = [HKObjectType.workoutType()]

        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .stepCount,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .activeEnergyBurned,
            .flightsClimbed,
            .runningStrideLength,
            .runningPower,
            .runningVerticalOscillation,
            .runningGroundContactTime,
            .runningSpeed,
            .vo2Max
        ]
        for id in quantityIDs {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                set.insert(type)
            }
        }

        set.insert(HKSeriesType.workoutRoute())

        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            set.insert(dob)
        }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            set.insert(sex)
        }

        return set
    }()

    // MARK: - 请求授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "此设备不支持 HealthKit"
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: Self.typesToRead
            )
        } catch {
            errorMessage = "授权失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 查询运动记录列表

    func loadWorkouts() async {
        isLoading = true
        defer { isLoading = false }

        let store = healthStore   // 提前取出，避免闭包捕获 self
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        let (samples, error): ([HKWorkout], Error?) =
            await withCheckedContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKWorkoutType.workoutType(),
                    predicate: nil,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    continuation.resume(returning: ((samples as? [HKWorkout]) ?? [], error))
                }
                store.execute(query)
            }

        if let error {
            errorMessage = "读取失败：\(error.localizedDescription)"
            return
        }

        workouts = samples.map { Workout(hkWorkout: $0) }
    }

    // MARK: - 跑步详情查询

    static func loadRunDetail(
        for workout: Workout,
        healthStore: HKHealthStore = .shared   // ★ 共享实例，避免每次调用都 new
    ) async -> RunDetail? {
        guard let hkWorkout = await fetchHKWorkout(
            uuid: workout.id,
            healthStore: healthStore
        ) else { return nil }

        // 顶部自己的活动段（不借用分段的实现）
        let activeSegments = extractActiveSegments(from: hkWorkout)

        // MARK: 平均配速：直接用顶部显示的时长和距离计算，保证三者自洽
        var averagePace: TimeInterval?

        if let distance = workout.distance, distance > 100, workout.duration > 0 {
            averagePace = workout.duration / (distance / 1000)
        }

        // 兜底：无距离统计时用 metadata
        if averagePace == nil,
           let speedQuantity = hkWorkout.metadata?[HKMetadataKeyAverageSpeed] as? HKQuantity {
            let speedMS = speedQuantity.doubleValue(
                for: .meter().unitDivided(by: .second())
            )
            if speedMS > 0.1 {
                averagePace = 1000.0 / speedMS
            }
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrStats = hkWorkout.statistics(for: HKQuantityType(.heartRate))
        let avgHR = hrStats?.averageQuantity()?.doubleValue(for: bpm)
        let maxHR = hrStats?.maximumQuantity()?.doubleValue(for: bpm)

        let strideLength = hkWorkout.statistics(for: HKQuantityType(.runningStrideLength))?
            .averageQuantity()?.doubleValue(for: .meter())

        var cadence: Double?
        do {
            let stepValues = await fetchRawSamples(
                for: hkWorkout,
                quantityType: HKQuantityType(.stepCount),
                unit: .count(),
                activeSegments: activeSegments,
                healthStore: healthStore
            )
            let denom = hkWorkout.duration
            if !stepValues.isEmpty, denom > 0 {
                let steps = stepValues.reduce(0, +)
                cadence = steps / (denom / 60)
            }
        }

        var elevation: Double?
        if let metadata = hkWorkout.metadata,
           let elevationQuantity = metadata[HKMetadataKeyElevationAscended] as? HKQuantity {
            elevation = elevationQuantity.doubleValue(for: .meter())
        }
        if elevation == nil {
            if let flights = hkWorkout.statistics(for: HKQuantityType(.flightsClimbed))?
                .sumQuantity()?.doubleValue(for: .count()) {
                elevation = flights * 3.0
            }
        }

        let energy = hkWorkout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        // 功率：同源 + 活动段过滤后的原始样本平均
        let power: Double? = await {
            if let v = await fetchRawAverage(
                for: hkWorkout,
                quantityType: HKQuantityType(.runningPower),
                unit: .watt(),
                activeSegments: activeSegments,
                healthStore: healthStore
            ) {
                return v
            }
            return hkWorkout.statistics(for: HKQuantityType(.runningPower))?
                .averageQuantity()?.doubleValue(for: .watt())
        }()

        let vertical = hkWorkout.statistics(for: HKQuantityType(.runningVerticalOscillation))?
            .averageQuantity()?.doubleValue(for: .meterUnit(with: .centi))

        // 顶部自己的路线（拉取 + 过滤 + 坐标转换）
        let rawLocations = await fetchRawRoute(for: hkWorkout, healthStore: healthStore)
        let filtered = filterLocations(rawLocations)
        let route = filtered.map { CoordinateConverter.wgs84ToGcj02($0.coordinate) }
        let markers = computeKilometerMarkers(from: route)
        let sourceName = hkWorkout.sourceRevision.source.name

        // 时间序列（图表用）
        async let heartRateSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.heartRate),
            unit: bpm,
            healthStore: healthStore,
            options: .discreteAverage
        )
        async let speedSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningSpeed),
            unit: HKUnit.meter().unitDivided(by: .second()),
            healthStore: healthStore,
            options: .discreteAverage,
            transform: { $0 > 0.5 ? 1000.0 / $0 : 0 }
        )
        async let strideSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningStrideLength),
            unit: .meter(),
            healthStore: healthStore,
            options: .discreteAverage
        )
        async let cadenceSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.stepCount),
            unit: .count(),
            healthStore: healthStore,
            options: .cumulativeSum
        )
        async let gctSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningGroundContactTime),
            unit: .secondUnit(with: .milli),
            healthStore: healthStore,
            options: .discreteAverage
        )
        async let voSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningVerticalOscillation),
            unit: .meterUnit(with: .centi),
            healthStore: healthStore,
            options: .discreteAverage
        )
        async let powerSeries = Self.fetchSeries(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningPower),
            unit: .watt(),
            healthStore: healthStore,
            options: .discreteAverage
        )

        let elevationSeries: [MetricPoint] = {
            var points: [MetricPoint] = []
            var lastKept: Date = .distantPast
            for loc in filtered where loc.verticalAccuracy >= 0 {
                if loc.timestamp.timeIntervalSince(lastKept) >= 30 {
                    points.append(MetricPoint(date: loc.timestamp, value: loc.altitude))
                    lastKept = loc.timestamp
                }
            }
            return points
        }()

        let series = RunSeries(
            heartRate: await heartRateSeries,
            pace: await speedSeries,
            strideLength: await strideSeries,
            cadence: await cadenceSeries,
            groundContactTime: await gctSeries,
            verticalOscillation: await voSeries,
            power: await powerSeries,
            elevation: elevationSeries
        )

        // 公里分段：完全独立的数据源，内部自己拉路由和活动段
        let splits = await RunSplitsLoader.load(
            hkWorkout: hkWorkout,
            officialDistance: workout.distance,
            healthStore: healthStore
        )

        let vo2 = await fetchVO2Max(for: hkWorkout, healthStore: healthStore)

        return RunDetail(
            startDate: workout.startDate,
            duration: workout.duration,
            distance: workout.distance,
            averagePace: averagePace,
            averageHeartRate: avgHR,
            maxHeartRate: maxHR,
            averageStrideLength: strideLength,
            averageCadence: cadence,
            elevationAscended: elevation,
            activeEnergy: energy,
            averagePower: power,
            verticalOscillation: vertical,
            route: route,
            sourceName: sourceName,
            kilometerMarkers: markers,
            series: series,
            vo2Max: vo2,
            splits: splits
        )
    }

    // MARK: - PB splits 加载

    func loadAllRunSplits() async {
        guard !hasLoadedSplits else { return }

        let runningRuns = workouts.filter {
            $0.type == .running && ($0.distance ?? 0) >= 1_000
        }

        guard !runningRuns.isEmpty else {
            hasLoadedSplits = true
            return
        }

        let store = healthStore

        let results = await withTaskGroup(
            of: (UUID, [KilometerSplit]).self,
            returning: [UUID: [KilometerSplit]].self
        ) { group in
            for workout in runningRuns {
                group.addTask {
                    let splits = await WorkoutStore.loadSplits(for: workout, healthStore: store)
                    return (workout.id, splits)
                }
            }
            var dict: [UUID: [KilometerSplit]] = [:]
            for await (id, splits) in group {
                dict[id] = splits
            }
            return dict
        }

        splitsCache = results
        hasLoadedSplits = true
    }

    func computePersonalBests() {
        let runningRuns = workouts.filter { $0.type == .running }
        personalBests = PBEngine.compute(workouts: runningRuns, splitsCache: splitsCache)
    }

    func resetSplits() {
        hasLoadedSplits = false
        splitsCache = [:]
        personalBests = []
    }

    // MARK: - 私有：单次 splits（PB 用）

    private static func loadSplits(
        for workout: Workout,
        healthStore: HKHealthStore
    ) async -> [KilometerSplit] {
        guard workout.type == .running else { return [] }

        guard let hkWorkout = await fetchHKWorkout(uuid: workout.id, healthStore: healthStore) else {
            return []
        }

        return await RunSplitsLoader.load(
            hkWorkout: hkWorkout,
            officialDistance: workout.distance,
            healthStore: healthStore
        )
    }

    // MARK: - 顶部私有：活动段解析（与分段完全独立）

    /// 顶部卡片专用的活动段解析。
    private static func extractActiveSegments(from hkWorkout: HKWorkout) -> [DateInterval] {
        guard let events = hkWorkout.workoutEvents, !events.isEmpty else { return [] }

        let segments = events
            .filter { $0.type == .segment }
            .map { $0.dateInterval }

        if !segments.isEmpty {
            return mergeIntervals(segments)
        }

        let pauses = events
            .filter { $0.type == .pause }
            .map { $0.dateInterval.start }
            .sorted()

        guard !pauses.isEmpty else { return [] }

        let resumes = events
            .filter { $0.type == .resume }
            .map { $0.dateInterval.start }
            .sorted()

        var active: [DateInterval] = []
        var cursor = hkWorkout.startDate
        var resumeIdx = 0

        for pauseStart in pauses {
            if cursor < pauseStart {
                active.append(DateInterval(start: cursor, end: pauseStart))
            }
            while resumeIdx < resumes.count, resumes[resumeIdx] <= pauseStart {
                resumeIdx += 1
            }
            if resumeIdx < resumes.count {
                cursor = resumes[resumeIdx]
                resumeIdx += 1
            } else {
                cursor = hkWorkout.endDate
                break
            }
        }

        if cursor < hkWorkout.endDate {
            active.append(DateInterval(start: cursor, end: hkWorkout.endDate))
        }

        return mergeIntervals(active)
    }

    private static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]
        for i in 1..<sorted.count {
            let last = merged[merged.count - 1]
            if sorted[i].start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, sorted[i].end)
                )
            } else {
                merged.append(sorted[i])
            }
        }
        return merged
    }

    // MARK: - 顶部私有：路线

    /// 精度 + 速度过滤
    private static func filterLocations(_ locations: [CLLocation]) -> [CLLocation] {
        var filtered: [CLLocation] = []
        var lastKept: CLLocation?
        let maxSpeed: Double = 12.0

        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 100 else { continue }

            guard let last = lastKept else {
                filtered.append(location)
                lastKept = location
                continue
            }

            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0 else { continue }

            let distance = location.distance(from: last)
            if distance < 3 {
                filtered.append(location)
                lastKept = location
                continue
            }

            let speed = distance / dt
            if speed <= maxSpeed {
                filtered.append(location)
                lastKept = location
            }
        }

        return filtered
    }

    // MARK: - 顶部私有：HealthKit fetch

    private static func fetchHKWorkout(
        uuid: UUID,
        healthStore: HKHealthStore
    ) async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }

    private static func fetchRawRoute(
        for workout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> [CLLocation] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            healthStore.execute(query)
        }

        guard let route = routes.first else { return [] }

        return await withCheckedContinuation { continuation in
            var locations: [CLLocation] = []
            var resumed = false
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, _ in
                if let batch { locations.append(contentsOf: batch) }
                if done, !resumed {
                    resumed = true
                    continuation.resume(returning: locations)
                }
            }
            healthStore.execute(query)
        }
    }

    private static func fetchSeries(
        for hkWorkout: HKWorkout,
        quantityType: HKQuantityType,
        unit: HKUnit,
        healthStore: HKHealthStore,
        options: HKStatisticsOptions,
        interval: TimeInterval = 60,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> [MetricPoint] {
        let predicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: hkWorkout.startDate,
                intervalComponents: DateComponents(second: Int(interval))
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: [])
                    return
                }

                var points: [MetricPoint] = []
                results.enumerateStatistics(from: hkWorkout.startDate,
                                            to: hkWorkout.endDate) { stats, _ in
                    let quantity: HKQuantity?
                    if options.contains(.discreteAverage) {
                        quantity = stats.averageQuantity()
                    } else if options.contains(.cumulativeSum) {
                        quantity = stats.sumQuantity()
                    } else {
                        quantity = nil
                    }

                    guard let quantity else { return }
                    let raw = quantity.doubleValue(for: unit)
                    let value = transform(raw)
                    guard value.isFinite, value > 0 else { return }

                    points.append(MetricPoint(date: stats.startDate, value: value))
                }

                continuation.resume(returning: points)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - 顶部私有：同源 + 活动段的原始样本

    /// 拉取同源 + 活动段内的原始样本值数组
    private static func fetchRawSamples(
        for hkWorkout: HKWorkout,
        quantityType: HKQuantityType,
        unit: HKUnit,
        activeSegments: [DateInterval],
        healthStore: HKHealthStore
    ) async -> [Double] {
        let timePredicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )
        let sourcePredicate = HKQuery.predicateForObjects(
            from: hkWorkout.sourceRevision.source
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate, sourcePredicate
        ])

        let samples: [HKQuantitySample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                ]
            ) { _, samples, _ in
                c.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }

        let hasSegments = !activeSegments.isEmpty

        return samples.compactMap { s in
            if hasSegments,
               !activeSegments.contains(where: { $0.contains(s.startDate) }) {
                return nil
            }
            let v = s.quantity.doubleValue(for: unit)
            return (v.isFinite && v > 0) ? v : nil
        }
    }

    /// 拉取同源 + 活动段内的原始样本，返回简单算术平均
    private static func fetchRawAverage(
        for hkWorkout: HKWorkout,
        quantityType: HKQuantityType,
        unit: HKUnit,
        activeSegments: [DateInterval],
        healthStore: HKHealthStore
    ) async -> Double? {
        let values = await fetchRawSamples(
            for: hkWorkout,
            quantityType: quantityType,
            unit: unit,
            activeSegments: activeSegments,
            healthStore: healthStore
        )
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - 顶部私有：用户资料 & VO2Max

    private static func fetchUserProfile(
        healthStore: HKHealthStore
    ) -> (age: Int, sex: HKBiologicalSex)? {
        guard let dob = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: dob) else {
            return nil
        }
        let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        guard age > 0 else { return nil }

        guard let sexObject = try? healthStore.biologicalSex() else { return nil }
        let sex = sexObject.biologicalSex
        guard sex == .male || sex == .female else { return nil }

        return (age, sex)
    }

    private static func fetchVO2Max(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> VO2MaxInfo? {
        let type = HKQuantityType(.vo2Max)
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        let currentPredicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.endDate.addingTimeInterval(-3600),
            end: hkWorkout.endDate.addingTimeInterval(3600),
            options: []
        )

        let currentSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: currentPredicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard let current = currentSamples.first else { return nil }
        let value = current.quantity.doubleValue(for: unit)

        let prevPredicate = HKQuery.predicateForSamples(
            withStart: nil,
            end: current.startDate.addingTimeInterval(-1),
            options: .strictEndDate
        )

        let prevSamples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: prevPredicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let previous = prevSamples.first?.quantity.doubleValue(for: unit)
        let delta = previous.map { value - $0 }

        var classification: VO2MaxClassification?
        var age: Int?
        var sex: HKBiologicalSex?
        var thresholds: VO2MaxThresholds?

        if let profile = fetchUserProfile(healthStore: healthStore) {
            age = profile.age
            sex = profile.sex
            classification = VO2MaxClassification.classify(value: value, age: profile.age, sex: profile.sex)
            thresholds = VO2MaxClassification.thresholdsFor(age: profile.age, sex: profile.sex)
        }

        return VO2MaxInfo(
            value: value,
            delta: delta,
            classification: classification,
            age: age,
            sex: sex,
            thresholds: thresholds,
            previousValue: previous
        )
    }

    // MARK: - 顶部私有：Marker

    private static func computeKilometerMarkers(
        from route: [CLLocationCoordinate2D]
    ) -> [KilometerMarker] {
        guard route.count >= 2 else { return [] }

        var markers: [KilometerMarker] = []
        var accumulated: Double = 0
        var nextTarget: Double = 1000
        var index: Int = 1

        for i in 1..<route.count {
            let prev = CLLocation(latitude: route[i - 1].latitude, longitude: route[i - 1].longitude)
            let curr = CLLocation(latitude: route[i].latitude, longitude: route[i].longitude)
            let segment = curr.distance(from: prev)

            while segment > 0, accumulated + segment >= nextTarget, nextTarget <= 500_000 {
                let remaining = nextTarget - accumulated
                let ratio = remaining / segment
                let lat = route[i - 1].latitude + (route[i].latitude - route[i - 1].latitude) * ratio
                let lon = route[i - 1].longitude + (route[i].longitude - route[i - 1].longitude) * ratio

                markers.append(KilometerMarker(
                    id: index,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                ))
                index += 1
                nextTarget += 1000
            }
            accumulated += segment
        }

        return markers
    }
}

// MARK: - Preview / 测试注入

#if DEBUG
extension WorkoutStore {
    static func preview(_ workouts: [Workout]) -> WorkoutStore {
        let store = WorkoutStore()
        store.workouts = workouts
        return store
    }
}
#endif
