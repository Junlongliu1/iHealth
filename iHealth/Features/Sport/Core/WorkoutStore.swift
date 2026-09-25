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
            .flightsClimbed,                // 爬楼层数（替代 elevationAscended）
            .runningStrideLength,
            .runningPower,
            .runningVerticalOscillation
        ]
        for id in quantityIDs {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                set.insert(type)
            }
        }

        // 运动路线
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

        let query = HKSampleQuery(
            sampleType: HKWorkoutType.workoutType(),
            predicate: nil,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.errorMessage = "读取失败：\(error.localizedDescription)"
                }
                return
            }

            let hkWorkouts = (samples as? [HKWorkout]) ?? []
            let mapped = hkWorkouts.map { Workout(hkWorkout: $0) }

            DispatchQueue.main.async {
                self.workouts = mapped
            }
        }

        healthStore.execute(query)
    }

    // MARK: - 跑步详情查询

    func loadRunDetail(for workout: Workout) async -> RunDetail? {
        guard let hkWorkout = await fetchHKWorkout(uuid: workout.id) else {
            return nil
        }

        // 平均配速（秒/公里）
        var averagePace: TimeInterval?
        if let distance = workout.distance, distance > 0 {
            averagePace = hkWorkout.duration / (distance / 1000)
        }

        // 心率
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartRateType = HKQuantityType(.heartRate)
        let hrStats = hkWorkout.statistics(for: heartRateType)
        let avgHR = hrStats?.averageQuantity()?.doubleValue(for: bpm)
        let maxHR = hrStats?.maximumQuantity()?.doubleValue(for: bpm)

        // 步幅（米）
        let strideLength = hkWorkout.statistics(for: HKQuantityType(.runningStrideLength))?
            .averageQuantity()?.doubleValue(for: .meter())

        // 步频（步/分钟）= 总步数 / 分钟数
        var cadence: Double?
        if let steps = hkWorkout.statistics(for: HKQuantityType(.stepCount))?
            .sumQuantity()?.doubleValue(for: .count()),
           hkWorkout.duration > 0 {
            cadence = steps / (hkWorkout.duration / 60)
        }

        // 累计上升（米）：优先从 metadata 读取
        var elevation: Double?
        if let metadata = hkWorkout.metadata,
           let elevationQuantity = metadata[HKMetadataKeyElevationAscended] as? HKQuantity {
            elevation = elevationQuantity.doubleValue(for: .meter())
        }

        // 备选：爬楼层数换算（1 层 ≈ 3 米）
        if elevation == nil {
            if let flights = hkWorkout.statistics(for: HKQuantityType(.flightsClimbed))?
                .sumQuantity()?.doubleValue(for: .count()) {
                elevation = flights * 3.0
            }
        }

        // 消耗能量（千卡）
        let energy = hkWorkout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        // 平均功率（瓦特）
        let power = hkWorkout.statistics(for: HKQuantityType(.runningPower))?
            .averageQuantity()?.doubleValue(for: .watt())

        // 垂直振幅（厘米）
        let vertical = hkWorkout.statistics(for: HKQuantityType(.runningVerticalOscillation))?
            .averageQuantity()?.doubleValue(for: .meterUnit(with: .centi))

        // 运动路线
        let route = await fetchRoute(for: hkWorkout)

        // 公里标记
        let markers = computeKilometerMarkers(from: route)

        // 数据来源（Apple Watch / iPhone）
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

    // MARK: - 私有辅助

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
        // 1. 取路线样本
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

        // 2. 取具体坐标
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

        // 3. 基于速度过滤异常跳点（> 10 m/s 视为噪点）
        var filtered: [CLLocation] = []
        let maxSpeed: Double = 10.0
        for (index, location) in rawLocations.enumerated() {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy < 50 else { continue }   // 精度差直接丢
            if index == 0 {
                filtered.append(location)
                continue
            }
            guard let last = filtered.last else {
                filtered.append(location)
                continue
            }
            let distance = location.distance(from: last)
            let time = location.timestamp.timeIntervalSince(last.timestamp)
            guard time > 0 else { continue }
            if distance / time < maxSpeed {
                filtered.append(location)
            }
        }

        // 4. WGS-84 → GCJ-02（如果你是在中国大陆显示地图，需要这一步）
        return filtered.map { CoordinateConverter.wgs84ToGcj02($0.coordinate) }
    }
    
    /// 沿路线每 1 公里打一个标记点
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
