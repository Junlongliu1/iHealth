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
    private let healthStore = HKHealthStore()

    var workouts: [Workout] = []
    var isLoading = false
    var errorMessage: String?

    /// 每公里分段缓存（按 Workout.id）
    var splitsCache: [UUID: [KilometerSplit]] = [:]
    /// 个人最好成绩
    var personalBests: [PersonalBest] = []
    /// 是否已经加载过分段
    private var hasLoadedSplits = false

    // 只读取，不写入
    private var typesToRead: Set<HKObjectType> {
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

        // 用户特征（用于 VO2 Max 分级）
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            set.insert(dob)
        }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            set.insert(sex)
        }
        
        set.insert(HKSeriesType.workoutRoute())
        return set
    }

    // MARK: - 请求授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "此设备不支持 HealthKit"
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: typesToRead
            )
        } catch {
            errorMessage = "授权失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 查询运动记录列表

    func loadWorkouts() async {
        isLoading = true
        defer { isLoading = false }

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        let hkWorkouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    Task { @MainActor [weak self] in
                        self?.errorMessage = "读取失败：\(error.localizedDescription)"
                    }
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        let mapped = hkWorkouts.map { Workout(hkWorkout: $0) }
        self.workouts = mapped
    }

    // MARK: - 跑步详情查询（静态，供 RunDetailView 直接调用）

    static func loadRunDetail(
        for workout: Workout,
        healthStore: HKHealthStore = HKHealthStore()
    ) async -> RunDetail? {
        guard let hkWorkout = await fetchHKWorkout(
            uuid: workout.id,
            healthStore: healthStore
        ) else {
            return nil
        }

        var averagePace: TimeInterval?
        if let distance = workout.distance, distance > 0 {
            averagePace = hkWorkout.duration / (distance / 1000)
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartRateType = HKQuantityType(.heartRate)
        let hrStats = hkWorkout.statistics(for: heartRateType)
        let avgHR = hrStats?.averageQuantity()?.doubleValue(for: bpm)
        let maxHR = hrStats?.maximumQuantity()?.doubleValue(for: bpm)

        let strideLength = hkWorkout.statistics(for: HKQuantityType(.runningStrideLength))?
            .averageQuantity()?.doubleValue(for: .meter())

        var cadence: Double?
        if let steps = hkWorkout.statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?.doubleValue(for: .count()),
           hkWorkout.duration > 0 {
            cadence = steps / (hkWorkout.duration / 60)
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

        let power = hkWorkout.statistics(for: HKQuantityType(.runningPower))?
            .averageQuantity()?.doubleValue(for: .watt())

        let vertical = hkWorkout.statistics(for: HKQuantityType(.runningVerticalOscillation))?
            .averageQuantity()?.doubleValue(for: .meterUnit(with: .centi))

        // 取原始 WGS-84 轨迹 → 过滤 → 转 GCJ-02
        let rawLocations = await fetchRawRoute(
            for: hkWorkout,
            healthStore: healthStore
        )
        let filtered = filterLocations(rawLocations)
        let route = filtered.map { CoordinateConverter.wgs84ToGcj02($0.coordinate) }
        let markers = computeKilometerMarkers(from: route)
        let sourceName = hkWorkout.sourceRevision.source.name

        // ★ 并行拉取 8 条时间序列
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
            transform: { $0 > 0.5 ? 1000.0 / $0 : 0 }   // 米/秒 → 秒/公里
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

        // 海拔：从过滤后的 GPS 点取高度，每 30 秒一个点
        let elevationSeries: [MetricPoint] = {
            var points: [MetricPoint] = []
            var lastKept: Date = .distantPast
            for loc in filtered where loc.verticalAccuracy >= 0 {
                if loc.timestamp.timeIntervalSince(lastKept) >= 30 {
                    points.append(MetricPoint(date: loc.timestamp,
                                              value: loc.altitude))
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

        // ★ 每公里分段详情
        let officialDist = workout.distance ?? 0
        let rawSplits = computeSplits(
            from: filtered,
            officialDistance: officialDist > 0 ? officialDist : nil
        )
        let splits = attachSplitDetails(splits: rawSplits, series: series)

        // ★ VO2 Max
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

    // MARK: - 每公里分段加载（PB 用）

    func loadAllRunSplits() async {
        guard !hasLoadedSplits else { return }

        let runningRuns = workouts.filter {
            $0.type == .running && ($0.distance ?? 0) >= 1_000
        }

        #if DEBUG
        print("📊 [PB] 待加载 splits 的跑步数量:", runningRuns.count)
        #endif

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
                    let splits = await WorkoutStore.loadSplits(
                        for: workout,
                        healthStore: store
                    )
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

        #if DEBUG
        for workout in runningRuns {
            let splits = results[workout.id] ?? []
            let dist = workout.distance.map { String(format: "%.2f", $0 / 1000) } ?? "?"
            let paces = splits.map { Int($0.duration.rounded()) }
            print("📊 [PB] \(dist)km → \(splits.count) splits: \(paces)")
        }

        let totalSplits = results.values.reduce(0) { $0 + $1.count }
        print("📊 [PB] 加载完成 splits 总数:", totalSplits)
        #endif
    }

    func computePersonalBests() {
        let runningRuns = workouts.filter { $0.type == .running }
        personalBests = PBEngine.compute(
            workouts: runningRuns,
            splitsCache: splitsCache
        )

        #if DEBUG
        print("📊 [PB] 计算结果:", personalBests.map {
            "\($0.label): \($0.time.map { String(format: "%.0f", $0) } ?? "nil")"
        })
        #endif
    }

    func resetSplits() {
        hasLoadedSplits = false
        splitsCache = [:]
        personalBests = []
    }

    // MARK: - 私有：加载单次跑步的 splits

    private static func loadSplits(
        for workout: Workout,
        healthStore: HKHealthStore
    ) async -> [KilometerSplit] {
        guard workout.type == .running else { return [] }

        guard let hkWorkout = await fetchHKWorkout(
            uuid: workout.id,
            healthStore: healthStore
        ) else { return [] }

        let locations = await fetchRawRoute(
            for: hkWorkout,
            healthStore: healthStore
        )
        guard locations.count >= 2 else { return [] }

        let filtered = filterLocations(locations)
        guard filtered.count >= 2 else { return [] }

        let officialDistance = workout.distance ?? 0
        return computeSplits(
            from: filtered,
            officialDistance: officialDistance > 0 ? officialDistance : nil
        )
    }

    /// 精度 + 速度过滤
    private static func filterLocations(
        _ locations: [CLLocation]
    ) -> [CLLocation] {
        var filtered: [CLLocation] = []
        var lastKept: CLLocation?
        let maxSpeed: Double = 12.0   // 43 km/h 上限

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

    /// 从带时间戳的轨迹点计算每 1km 分段
    private static func computeSplits(
        from locations: [CLLocation],
        officialDistance: Double?
    ) -> [KilometerSplit] {
        guard locations.count >= 2 else { return [] }

        let startTime = locations[0].timestamp

        var cumDist: [Double] = [0]
        var cumTime: [TimeInterval] = [0]

        for i in 1..<locations.count {
            let prev = locations[i - 1]
            let curr = locations[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            let segment = curr.distance(from: prev)
            cumDist.append(cumDist.last! + segment)
            cumTime.append(cumTime.last! + dt)
        }

        let routeTotalDist = cumDist.last ?? 0
        guard routeTotalDist >= 500 else { return [] }

        let segmentMeters: Double
        if let official = officialDistance, official > 0 {
            segmentMeters = 1000.0 * (routeTotalDist / official)
        } else {
            segmentMeters = 1000.0
        }

        var splits: [KilometerSplit] = []
        var kmIndex = 1
        var splitStartDist: Double = 0
        var splitStartTime: TimeInterval = 0

        while splitStartDist + segmentMeters <= routeTotalDist {
            let targetDist = splitStartDist + segmentMeters

            var idx = 1
            while idx < cumDist.count && cumDist[idx] < targetDist {
                idx += 1
            }
            guard idx < cumDist.count else { break }

            let d0 = cumDist[idx - 1], d1 = cumDist[idx]
            let t0 = cumTime[idx - 1], t1 = cumTime[idx]
            let ratio = (d1 - d0) > 0 ? (targetDist - d0) / (d1 - d0) : 0
            let targetTime = t0 + (t1 - t0) * ratio

            splits.append(KilometerSplit(
                index: kmIndex,
                distance: 1000,
                duration: targetTime - splitStartTime,
                startDate: startTime.addingTimeInterval(splitStartTime)
            ))

            kmIndex += 1
            splitStartDist = targetDist
            splitStartTime = targetTime
        }

        return splits
    }

    /// 按每公里的时间窗口，从时间序列里聚合出心率 / 步幅 / 步频 / 功率
    private static func attachSplitDetails(
        splits: [KilometerSplit],
        series: RunSeries
    ) -> [KilometerSplit] {
        splits.map { split in
            var s = split
            let start = split.startDate
            let end = start.addingTimeInterval(split.duration)

            s.averageHeartRate = average(series.heartRate, from: start, to: end)
            s.averageStrideLength = average(series.strideLength, from: start, to: end)
            s.averageCadence = average(series.cadence, from: start, to: end)
            s.averagePower = average(series.power, from: start, to: end)

            return s
        }
    }

    private static func average(
        _ points: [MetricPoint],
        from start: Date,
        to end: Date
    ) -> Double? {
        let inRange = points.filter { $0.date >= start && $0.date < end }
        guard !inRange.isEmpty else { return nil }
        return inRange.map(\.value).reduce(0, +) / Double(inRange.count)
    }

    // MARK: - 私有辅助（HealthKit fetch）

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

    /// 返回原始 WGS-84 轨迹，不做过滤、不做坐标转换
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

    /// 用 HKStatisticsCollectionQuery 拉取某指标的时间序列（默认 60 秒一聚合）
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
                results.enumerateStatistics(
                    from: hkWorkout.startDate,
                    to: hkWorkout.endDate
                ) { stats, _ in
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
    
    /// 读取用户年龄和生物性别；任一缺失则返回 nil
    private static func fetchUserProfile(
        healthStore: HKHealthStore
    ) -> (age: Int, sex: HKBiologicalSex)? {
        // 出生日期
        guard let dob = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: dob) else {
            return nil
        }

        let age = Calendar.current.dateComponents(
            [.year], from: birthDate, to: Date()
        ).year ?? 0

        guard age > 0 else { return nil }

        // 生物性别
        guard let sexObject = try? healthStore.biologicalSex() else {
            return nil
        }
        let sex = sexObject.biologicalSex
        guard sex == .male || sex == .female else { return nil }

        return (age, sex)
    }
    

    /// 查询某次跑步相关的 VO2 Max，并按年龄/性别计算苹果健康分级
    private static func fetchVO2Max(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> VO2MaxInfo? {
        let type = HKQuantityType(.vo2Max)
        let unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        // ① 当前：workout 结束时间 ±1 小时内最新一条
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
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                     ascending: false)
                ]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard let current = currentSamples.first else { return nil }
        let value = current.quantity.doubleValue(for: unit)

        // ② 上一次：早于 current.startDate 的最新一条
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
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                     ascending: false)
                ]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let previous = prevSamples.first?.quantity.doubleValue(for: unit)
        let delta = previous.map { value - $0 }

        // ③ 按年龄/性别分类
        var classification: VO2MaxClassification?
        var age: Int?
        var sex: HKBiologicalSex?
        var thresholds: VO2MaxThresholds?

        if let profile = fetchUserProfile(healthStore: healthStore) {
            age = profile.age
            sex = profile.sex
            classification = VO2MaxClassification.classify(
                value: value,
                age: profile.age,
                sex: profile.sex
            )
            thresholds = VO2MaxClassification.thresholdsFor(
                age: profile.age,
                sex: profile.sex
            )
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

    // MARK: - 私有辅助（Marker）

    private static func computeKilometerMarkers(
        from route: [CLLocationCoordinate2D]
    ) -> [KilometerMarker] {
        guard route.count >= 2 else { return [] }

        var markers: [KilometerMarker] = []
        var accumulated: Double = 0
        var nextTarget: Double = 1000
        var index: Int = 1

        for i in 1..<route.count {
            let prev = CLLocation(latitude: route[i - 1].latitude,
                                  longitude: route[i - 1].longitude)
            let curr = CLLocation(latitude: route[i].latitude,
                                  longitude: route[i].longitude)
            let segment = curr.distance(from: prev)

            while segment > 0,
                  accumulated + segment >= nextTarget,
                  nextTarget <= 500_000 {

                let remaining = nextTarget - accumulated
                let ratio = remaining / segment
                let lat = route[i - 1].latitude
                        + (route[i].latitude - route[i - 1].latitude) * ratio
                let lon = route[i - 1].longitude
                        + (route[i].longitude - route[i - 1].longitude) * ratio

                markers.append(KilometerMarker(
                    id: index,
                    coordinate: CLLocationCoordinate2D(latitude: lat,
                                                       longitude: lon)
                ))
                index += 1
                nextTarget += 1000
            }
            accumulated += segment
        }

        return markers
    }

    #if DEBUG
    /// 仅用于调试：累加轨迹点之间的球面距离
    private static func routeTotalDistance(of locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<locations.count {
            total += locations[i].distance(from: locations[i - 1])
        }
        return total
    }
    #endif
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
