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
            .runningVerticalOscillation
        ]
        for id in quantityIDs {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                set.insert(type)
            }
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
        
        print("📏 [RunDetail] id=\(workout.id)")
        print("     workout.distance(米)=\(workout.distance ?? -1)")
        print("     route 点数=\(route.count)")
        print("     route 累计距离(米)=\(routeTotalDistance(of: filtered))")

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
            kilometerMarkers: markers
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

        // ★ 关键：用官方距离校正 route 距离
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

            // 距离极小时直接保留（避免慢速点被误杀）
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

        // 校正切分间距：route 距离可能低估
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
