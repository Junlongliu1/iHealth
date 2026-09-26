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

    var splitsCache: [UUID: [KilometerSplit]] = [:]
    var personalBests: [PersonalBest] = []
    private var hasLoadedSplits = false

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

        set.insert(HKSeriesType.workoutRoute())

        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            set.insert(dob)
        }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            set.insert(sex)
        }

        return set
    }

    // MARK: - 请求授权

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "此设备不支持 HealthKit"
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
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

        self.workouts = hkWorkouts.map { Workout(hkWorkout: $0) }
    }

    // MARK: - 跑步详情查询

    static func loadRunDetail(
        for workout: Workout,
        healthStore: HKHealthStore = HKHealthStore()
    ) async -> RunDetail? {
        guard let hkWorkout = await fetchHKWorkout(
            uuid: workout.id,
            healthStore: healthStore
        ) else { return nil }

        let activeSegments = extractActiveSegments(from: hkWorkout)

        // MARK: 平均配速
        var averagePace: TimeInterval?

        if let speedQuantity = hkWorkout.metadata?[HKMetadataKeyAverageSpeed] as? HKQuantity {
            let speedMS = speedQuantity.doubleValue(
                for: .meter().unitDivided(by: .second())
            )
            if speedMS > 0.1 {
                averagePace = 1000.0 / speedMS
            }
        }

        if averagePace == nil,
           let distance = workout.distance, distance > 0 {
            let activeTime: TimeInterval
            if activeSegments.isEmpty {
                activeTime = hkWorkout.duration
            } else {
                activeTime = activeSegments.reduce(0.0) { $0 + $1.duration }
            }
            averagePace = activeTime / (distance / 1000)
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrStats = hkWorkout.statistics(for: HKQuantityType(.heartRate))
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

        let rawLocations = await fetchRawRoute(for: hkWorkout, healthStore: healthStore)
        let filtered = filterLocations(rawLocations)
        let route = filtered.map { CoordinateConverter.wgs84ToGcj02($0.coordinate) }
        let markers = computeKilometerMarkers(from: route)
        let sourceName = hkWorkout.sourceRevision.source.name

        // 时间序列（图表用）
        async let heartRateSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.heartRate), unit: bpm, healthStore: healthStore, options: .discreteAverage)
        async let speedSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.runningSpeed), unit: HKUnit.meter().unitDivided(by: .second()), healthStore: healthStore, options: .discreteAverage, transform: { $0 > 0.5 ? 1000.0 / $0 : 0 })
        async let strideSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.runningStrideLength), unit: .meter(), healthStore: healthStore, options: .discreteAverage)
        async let cadenceSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.stepCount), unit: .count(), healthStore: healthStore, options: .cumulativeSum)
        async let gctSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.runningGroundContactTime), unit: .secondUnit(with: .milli), healthStore: healthStore, options: .discreteAverage)
        async let voSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.runningVerticalOscillation), unit: .meterUnit(with: .centi), healthStore: healthStore, options: .discreteAverage)
        async let powerSeries = Self.fetchSeries(for: hkWorkout, quantityType: HKQuantityType(.runningPower), unit: .watt(), healthStore: healthStore, options: .discreteAverage)

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

        // splits 原始样本
        async let hrRaw = Self.fetchRawSamples(for: hkWorkout, quantityType: HKQuantityType(.heartRate), unit: bpm, healthStore: healthStore)
        async let strideRaw = Self.fetchRawSamples(for: hkWorkout, quantityType: HKQuantityType(.runningStrideLength), unit: .meter(), healthStore: healthStore)
        async let powerRaw = Self.fetchRawSamples(for: hkWorkout, quantityType: HKQuantityType(.runningPower), unit: .watt(), healthStore: healthStore)
        async let speedRaw = Self.fetchRawSamples(for: hkWorkout, quantityType: HKQuantityType(.runningSpeed), unit: HKUnit.meter().unitDivided(by: .second()), healthStore: healthStore)
        async let distanceRaw = Self.fetchRawDistanceSamples(for: hkWorkout, healthStore: healthStore)
        async let cadenceRaw = Self.fetchRawStepSamples(for: hkWorkout, healthStore: healthStore)

        let officialDist = workout.distance ?? 0
        let rawSplits: [KilometerSplit]

        if let lapSplits = extractLapSplits(from: hkWorkout, officialDistance: officialDist) {
            rawSplits = lapSplits
        } else {
            rawSplits = computeSplits(
                from: filtered,
                officialDistance: officialDist > 0 ? officialDist : nil,
                workoutStartDate: hkWorkout.startDate,
                workoutEndDate: hkWorkout.endDate,
                activeSegments: activeSegments,
                speedSamples: await speedRaw,
                distanceSamples: await distanceRaw
            )
        }

        // 第 1 段起点对齐修正：-3s
        var adjustedSplits = rawSplits
        if let first = adjustedSplits.first, first.index == 1 {
            adjustedSplits[0] = KilometerSplit(
                index: first.index,
                distance: first.distance,
                duration: max(0, first.duration - 3),
                startDate: first.startDate
            )
        }

        let splits = attachSplitDetails(
            splits: adjustedSplits,
            activeSegments: activeSegments,
            heartRate: await hrRaw,
            strideLength: await strideRaw,
            stepCount: await cadenceRaw,
            power: await powerRaw
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

        guard let hkWorkout = await fetchHKWorkout(uuid: workout.id, healthStore: healthStore) else { return [] }

        let officialDistance = workout.distance ?? 0
        if let lapSplits = extractLapSplits(from: hkWorkout, officialDistance: officialDistance),
           lapSplits.count >= 2 {
            return lapSplits
        }

        let locations = await fetchRawRoute(for: hkWorkout, healthStore: healthStore)
        guard locations.count >= 2 else { return [] }
        let filtered = filterLocations(locations)
        guard filtered.count >= 2 else { return [] }

        let activeSegments = extractActiveSegments(from: hkWorkout)
        let speedSamples = await fetchRawSamples(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningSpeed),
            unit: HKUnit.meter().unitDivided(by: .second()),
            healthStore: healthStore
        )
        let distanceSamples = await fetchRawDistanceSamples(
            for: hkWorkout,
            healthStore: healthStore
        )

        return computeSplits(
            from: filtered,
            officialDistance: officialDistance > 0 ? officialDistance : nil,
            workoutStartDate: hkWorkout.startDate,
            workoutEndDate: hkWorkout.endDate,
            activeSegments: activeSegments,
            speedSamples: speedSamples,
            distanceSamples: distanceSamples
        )
    }

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

    /// 提取活动段
    private static func extractActiveSegments(
        from hkWorkout: HKWorkout
    ) -> [DateInterval] {
        guard let events = hkWorkout.workoutEvents else { return [] }

        let segments = events
            .filter { $0.type == .segment }
            .map { $0.dateInterval }
            .sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for seg in segments {
            if let last = merged.last, seg.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, seg.end)
                )
            } else {
                merged.append(seg)
            }
        }

        return merged
    }

    /// 从轨迹 / 距离样本 / 速度样本计算每公里分段
    private static func computeSplits(
        from locations: [CLLocation],
        officialDistance: Double?,
        workoutStartDate: Date,
        workoutEndDate: Date,
        activeSegments: [DateInterval] = [],
        speedSamples: [MetricPoint] = [],
        distanceSamples: [MetricPoint] = []
    ) -> [KilometerSplit] {
        guard locations.count >= 2 else { return [] }

        let startDate = workoutStartDate
        let endDate = workoutEndDate

        var curve: [(date: Date, cumDist: Double)] = []

        // 1a. distanceWalkingRunning 原始样本（首选）
        if distanceSamples.count >= 30 {
            curve = [(startDate, 0)]
            var cum: Double = 0
            for sample in distanceSamples {
                cum += sample.value
                curve.append((sample.date, cum))
            }
            if let lastDate = curve.last?.date, lastDate < endDate {
                curve.append((endDate, cum))
            }

            if let official = officialDistance, let total = curve.last?.cumDist, total > 100 {
                let scale = official / total
                curve = curve.map { ($0.date, $0.cumDist * scale) }
            }
        }

        // 1b. runningSpeed 积分（次选）
        if curve.count < 30, speedSamples.count >= 10 {
            curve = [(startDate, 0)]
            var cum: Double = 0
            for i in 1..<speedSamples.count {
                let prev = speedSamples[i - 1]
                let curr = speedSamples[i]
                let dt = curr.date.timeIntervalSince(prev.date)
                guard dt > 0, dt < 10 else {
                    curve.append((curr.date, cum))
                    continue
                }
                cum += (prev.value + curr.value) / 2 * dt
                curve.append((curr.date, cum))
            }
            if let lastDate = curve.last?.date, lastDate < endDate {
                curve.append((endDate, cum))
            }

            if let official = officialDistance, let total = curve.last?.cumDist, total > 100 {
                let scale = official / total
                curve = curve.map { ($0.date, $0.cumDist * scale) }
            }
        }

        // 1c. GPS 累加（兜底）
        if curve.count < 30 {
            curve = [(startDate, 0)]
            var cum: Double = 0
            for i in 1..<locations.count {
                cum += locations[i].distance(from: locations[i - 1])
                curve.append((locations[i].timestamp, cum))
            }
            if let lastDate = curve.last?.date, lastDate < endDate {
                curve.append((endDate, cum))
            }

            if let official = officialDistance, let total = curve.last?.cumDist, total > 100 {
                let scale = official / total
                curve = curve.map { ($0.date, $0.cumDist * scale) }
            }
        }

        let totalDist = curve.last?.cumDist ?? 0
        guard totalDist >= 500 else { return [] }

        func dateAtDistance(_ target: Double) -> Date? {
            guard let last = curve.last, last.cumDist >= target else { return nil }

            var lo = 0
            var hi = curve.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if curve[mid].cumDist < target {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }

            guard lo > 0 else { return curve[0].date }

            let d0 = curve[lo - 1].cumDist
            let d1 = curve[lo].cumDist
            let t0 = curve[lo - 1].date
            let t1 = curve[lo].date
            let ratio = (d1 - d0) > 0 ? (target - d0) / (d1 - d0) : 0
            return t0.addingTimeInterval(t1.timeIntervalSince(t0) * ratio)
        }

        let hasSegments = !activeSegments.isEmpty
        func activeDuration(from a: Date, to b: Date) -> TimeInterval {
            guard b > a else { return 0 }
            if !hasSegments {
                return b.timeIntervalSince(a)
            }
            var total: TimeInterval = 0
            for seg in activeSegments {
                let s = max(a, seg.start)
                let e = min(b, seg.end)
                if e > s {
                    total += e.timeIntervalSince(s)
                }
            }
            return total
        }

        let officialTotal = officialDistance ?? totalDist
        let fullKmCount = Int(officialTotal / 1000)
        let tailMeters = officialTotal - Double(fullKmCount) * 1000
        let hasTail = tailMeters >= 100

        var splits: [KilometerSplit] = []
        var prevDate = startDate

        for km in 1...max(fullKmCount, 1) {
            guard km <= fullKmCount else { break }

            let targetDist = Double(km) * 1000
            guard let cutDate = dateAtDistance(targetDist) else { break }

            let dur = activeDuration(from: prevDate, to: cutDate)
            splits.append(KilometerSplit(
                index: km,
                distance: 1000,
                duration: dur,
                startDate: prevDate
            ))
            prevDate = cutDate
        }

        if hasTail {
            let dur = activeDuration(from: prevDate, to: endDate)
            if dur > 0 {
                splits.append(KilometerSplit(
                    index: fullKmCount + 1,
                    distance: tailMeters,
                    duration: dur,
                    startDate: prevDate
                ))
            }
        }

        return splits
    }

    /// lap events
    private static func extractLapSplits(
        from hkWorkout: HKWorkout,
        officialDistance: Double
    ) -> [KilometerSplit]? {
        guard let events = hkWorkout.workoutEvents else { return nil }

        let laps = events
            .filter { $0.type == .lap }
            .sorted { $0.dateInterval.start < $1.dateInterval.start }

        guard laps.count >= 2 else { return nil }

        let lapTotal = laps.reduce(0.0) { $0 + $1.dateInterval.duration }
        guard lapTotal > hkWorkout.duration * 0.6 else { return nil }

        let expectedKm = Int(officialDistance / 1000)
        guard abs(laps.count - expectedKm) <= 1 else { return nil }

        return laps.enumerated().map { idx, lap in
            KilometerSplit(
                index: idx + 1,
                distance: 1000,
                duration: lap.dateInterval.duration,
                startDate: lap.dateInterval.start
            )
        }
    }

    /// 聚合每公里的平均指标
    private static func attachSplitDetails(
        splits: [KilometerSplit],
        activeSegments: [DateInterval],
        heartRate: [MetricPoint],
        strideLength: [MetricPoint],
        stepCount: [MetricPoint],
        power: [MetricPoint]
    ) -> [KilometerSplit] {
        splits.enumerated().map { (i, split) in
            var s = split
            let start = split.startDate

            // 墙钟结束时间：下一段的 startDate；尾段用 start + duration
            let wallClockEnd: Date = {
                if i + 1 < splits.count {
                    return splits[i + 1].startDate
                }
                return start.addingTimeInterval(split.duration)
            }()

            s.averageHeartRate = mean(
                samples(heartRate, from: start, to: wallClockEnd,
                        activeSegments: activeSegments)
            )
            s.averageStrideLength = mean(
                samples(strideLength, from: start, to: wallClockEnd,
                        activeSegments: activeSegments)
            )
            s.averagePower = mean(
                samples(power, from: start, to: wallClockEnd,
                        activeSegments: activeSegments)
            )

            // 步频：按时间比例加权分摊边界样本
            let steps = weightedSum(
                stepCount,
                from: start,
                to: wallClockEnd,
                activeSegments: activeSegments
            )
            let activeMinutes = split.duration / 60
            s.averageCadence = activeMinutes > 0.01
                ? steps / activeMinutes
                : nil

            return s
        }
    }

    /// 过滤出 [start, end) 内、且落在活动段中的样本
    private static func samples(
        _ points: [MetricPoint],
        from start: Date,
        to end: Date,
        activeSegments: [DateInterval]
    ) -> [MetricPoint] {
        let hasSegments = !activeSegments.isEmpty
        return points.filter { pt in
            guard pt.date >= start, pt.date < end else { return false }
            if !hasSegments { return true }
            return activeSegments.contains { $0.contains(pt.date) }
        }
    }

    /// 算术平均；空集返回 nil
    private static func mean(_ points: [MetricPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    /// 求和
    private static func sumValues(_ points: [MetricPoint]) -> Double {
        points.map(\.value).reduce(0, +)
    }

    /// 按时间比例加权的步数求和
    private static func weightedSum(
        _ points: [MetricPoint],
        from start: Date,
        to end: Date,
        activeSegments: [DateInterval]
    ) -> Double {
        let hasSegments = !activeSegments.isEmpty

        let windowSegments: [DateInterval]
        if hasSegments {
            windowSegments = activeSegments.compactMap { seg in
                let s = max(start, seg.start)
                let e = min(end, seg.end)
                return e > s ? DateInterval(start: s, end: e) : nil
            }
        } else {
            windowSegments = [DateInterval(start: start, end: end)]
        }

        let totalWindowDuration = windowSegments.reduce(0.0) { $0 + $1.duration }
        guard totalWindowDuration > 0 else { return 0 }

        var total: Double = 0
        for pt in points {
            let sampleDuration: TimeInterval = 3.0
            let sampleStart = pt.date
            let sampleEnd = pt.date.addingTimeInterval(sampleDuration)

            var overlap: TimeInterval = 0
            for ws in windowSegments {
                let s = max(sampleStart, ws.start)
                let e = min(sampleEnd, ws.end)
                if e > s { overlap += e.timeIntervalSince(s) }
            }

            guard overlap > 0 else { continue }

            let ratio = overlap / sampleDuration
            total += pt.value * ratio
        }

        return total
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

    private static func fetchRawSamples(
        for hkWorkout: HKWorkout,
        quantityType: HKQuantityType,
        unit: HKUnit,
        healthStore: HKHealthStore,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> [MetricPoint] {
        let predicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                     ascending: true)
                ]
            ) { _, samples, _ in
                let points: [MetricPoint] = (samples as? [HKQuantitySample])?
                    .compactMap { sample in
                        let raw = sample.quantity.doubleValue(for: unit)
                        let value = transform(raw)
                        guard value.isFinite, value > 0 else { return nil }
                        return MetricPoint(date: sample.startDate, value: value)
                    } ?? []
                continuation.resume(returning: points)
            }
            healthStore.execute(query)
        }
    }

    /// 拉取 distanceWalkingRunning 原始段落样本（同源过滤 + 用 endDate）
    private static func fetchRawDistanceSamples(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> [MetricPoint] {
        let type = HKQuantityType(.distanceWalkingRunning)

        let timePredicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )
        let source = hkWorkout.sourceRevision.source
        let sourcePredicate = HKQuery.predicateForObjects(from: source)

        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate, sourcePredicate
        ])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: combined,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                     ascending: true)
                ]
            ) { _, samples, _ in
                let points: [MetricPoint] = (samples as? [HKQuantitySample])?
                    .compactMap { sample in
                        let meters = sample.quantity.doubleValue(for: .meter())
                        guard meters.isFinite, meters > 0 else { return nil }
                        return MetricPoint(date: sample.endDate, value: meters)
                    } ?? []

                continuation.resume(returning: points)
            }
            healthStore.execute(query)
        }
    }

    /// 拉取 stepCount 原始样本（同源过滤）
    private static func fetchRawStepSamples(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> [MetricPoint] {
        let type = HKQuantityType(.stepCount)

        let timePredicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )
        let source = hkWorkout.sourceRevision.source
        let sourcePredicate = HKQuery.predicateForObjects(from: source)

        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate, sourcePredicate
        ])

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: combined,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                     ascending: true)
                ]
            ) { _, samples, _ in
                let points: [MetricPoint] = (samples as? [HKQuantitySample])?
                    .compactMap { sample in
                        let count = sample.quantity.doubleValue(for: .count())
                        guard count.isFinite, count > 0 else { return nil }
                        return MetricPoint(date: sample.startDate, value: count)
                    } ?? []

                continuation.resume(returning: points)
            }
            healthStore.execute(query)
        }
    }

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
