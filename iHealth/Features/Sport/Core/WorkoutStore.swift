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
    var authorizationStatus: HKAuthorizationStatus = .notDetermined
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
            authorizationStatus = healthStore.authorizationStatus(
                for: HKObjectType.workoutType()
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

    // MARK: - 跑步详情查询

    func loadRunDetail(for workout: Workout) async -> RunDetail? {
        guard let hkWorkout = await fetchHKWorkout(uuid: workout.id) else {
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

        let route = await fetchRoute(for: hkWorkout)
        let markers = computeKilometerMarkers(from: route)
        let sourceName = hkWorkout.sourceRevision.source.name

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
        hasLoadedSplits = true

        let runningRuns = workouts.filter {
            $0.type == .running && ($0.distance ?? 0) >= 1_000
        }
        print("📊 [PB] 待加载 splits 的跑步数量:", runningRuns.count)

        guard !runningRuns.isEmpty else { return }

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

        // Debug：打印每次跑步的 splits 情况
        for workout in runningRuns {
            let splits = results[workout.id] ?? []
            let dist = workout.distance.map { String(format: "%.2f", $0 / 1000) } ?? "?"
            let paces = splits.map { Int($0.duration.rounded()) }
            print("📊 [PB] \(dist)km → \(splits.count) splits: \(paces)")
        }

        let totalSplits = results.values.reduce(0) { $0 + $1.count }
        print("📊 [PB] 加载完成 splits 总数:", totalSplits)
    }

    func computePersonalBests() {
        let runningRuns = workouts.filter { $0.type == .running }
        personalBests = PBEngine.compute(
            workouts: runningRuns,
            splitsCache: splitsCache
        )
        print("📊 [PB] 计算结果:", personalBests.map {
            "\($0.label): \($0.time.map { String(format: "%.0f", $0) } ?? "nil")"
        })
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

        guard let hkWorkout = await fetchHKWorkoutStatic(
            uuid: workout.id,
            healthStore: healthStore
        ) else { return [] }

        let locations = await fetchRawRouteStatic(
            for: hkWorkout,
            healthStore: healthStore
        )
        guard locations.count >= 2 else { return [] }

        let filtered = filterLocationsStatic(locations)
        guard filtered.count >= 2 else { return [] }

        // ★ 关键：用官方距离校正 route 距离
        let officialDistance = workout.distance ?? 0
        return computeSplitsStatic(
            from: filtered,
            officialDistance: officialDistance > 0 ? officialDistance : nil
        )
    }

    private static func fetchRawRouteStatic(
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

    private static func fetchHKWorkoutStatic(
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

    /// 精度 + 速度过滤
    /// - 精度阈值放宽到 100m（原 50m 太严，会丢点导致距离低估）
    /// - 用 `lastKept` 与上一个"保留点"比较（原逻辑与上一个"原始点"比较，容易误杀）
    /// - 距离很小（< 3m）时无条件保留，避免误杀慢速时的正常点
    private static func filterLocationsStatic(
        _ locations: [CLLocation]
    ) -> [CLLocation] {
        var filtered: [CLLocation] = []
        var lastKept: CLLocation?
        let maxSpeed: Double = 12.0   // 43 km/h 上限（放宽，避免误杀下坡冲刺）

        for location in locations {
            // 精度过滤
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
            // 速度超限：丢弃当前点，lastKept 不动
        }

        return filtered
    }

    /// 从带时间戳的轨迹点计算每 1km 分段
    /// - Parameter officialDistance: HealthKit 记录的官方总距离（米）
    ///   用于校正 route 距离的低估：如果 route 距离比官方少 20%，每个 split 要按官方 1km 对应的 route 距离切分
    private static func computeSplitsStatic(
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

        // ★ 计算切分间距
        // route 距离可能低估，officialDistance 是"真实"距离
        // 例如 routeTotalDist = 9000, official = 10000 → 每个 1km 对应 route 上的 900m
        //   → 切分间距 = 1000 * (official / routeTotal) = 1111...（不对，等一下）
        //
        // 正确逻辑：
        // - 用户真实跑了 10km（official=10000m）
        // - route 只累计出 9000m
        // - 那么每个真实 1km 对应 route 的 9000/10000 = 0.9km = 900m
        // - 所以切分间距 = 1000 * (routeTotalDist / officialDistance)
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

    // MARK: - 私有辅助（Route / Marker）

    private func fetchHKWorkout(uuid: UUID) async -> HKWorkout? {
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

    private func fetchRoute(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
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

        let rawLocations: [CLLocation] = await withCheckedContinuation { continuation in
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

        let filtered = Self.filterLocationsStatic(rawLocations)
        return filtered.map { CoordinateConverter.wgs84ToGcj02($0.coordinate) }
    }

    private func computeKilometerMarkers(
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

    // MARK: - Preview / 测试注入

    static func preview(_ workouts: [Workout]) -> WorkoutStore {
        let store = WorkoutStore()
        store.workouts = workouts
        return store
    }
}

// MARK: - PB 引擎

enum PBEngine {
    static let targets: [(label: String, distance: Double)] = [
        ("1 km",  1_000),
        ("3 km",  3_000),
        ("5 km",  5_000),
        ("10 km", 10_000),
        ("半马",  21_097.5),
        ("全马",  42_195)
    ]

    static func compute(
        workouts: [Workout],
        splitsCache: [UUID: [KilometerSplit]]
    ) -> [PersonalBest] {
        targets.map { target in
            let kmCount = max(1, Int(target.distance / 1000))

            var best: (time: TimeInterval, date: Date)?

            for workout in workouts {
                guard let splits = splitsCache[workout.id],
                      splits.count >= kmCount else { continue }

                for i in 0...(splits.count - kmCount) {
                    var sum: TimeInterval = 0
                    for j in i..<(i + kmCount) {
                        sum += splits[j].duration
                    }
                    if best == nil || sum < best!.time {
                        best = (sum, splits[i].startDate)
                    }
                }
            }

            return PersonalBest(
                label: target.label,
                distance: target.distance,
                time: best?.time,
                date: best?.date
            )
        }
    }
}
