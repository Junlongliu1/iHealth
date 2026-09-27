//
//  RunSplitsEngine.swift
//  iHealth
//
//  分段计算的唯一入口：数据拉取 + 分段计算 + 指标聚合，全部集中在此文件。
//  数据源完全自包含：路由、活动段、样本都在内部获取，不依赖外部传入。
//  顶部卡片（WorkoutStore.loadRunDetail）的聚合算法与此文件完全独立。
//

import Foundation
import HealthKit
import CoreLocation

// MARK: - 对外入口：拉取 → 计算 → 附加指标

/// 从 HealthKit 拉取一次跑步的全部原始数据，并计算出公里分段。
/// 数据源完全自包含：路由、活动段、样本都在内部获取，不依赖外部传入。
enum RunSplitsLoader {

    // MARK: 主入口

    /// 对外主入口：拉取 + 计算 + 附加指标
    static func load(
        hkWorkout: HKWorkout,
        officialDistance: Double?,
        healthStore: HKHealthStore
    ) async -> [KilometerSplit] {

        // 分段自己的数据源
        let activeSegments = extractActiveSegments(from: hkWorkout)
        let rawLocations = await fetchRoute(for: hkWorkout, healthStore: healthStore)
        let filteredLocations = filterLocations(rawLocations)

        // 并行拉取原始样本
        async let speedRaw = RawSampleFetcher.samples(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningSpeed),
            unit: HKUnit.meter().unitDivided(by: .second()),
            healthStore: healthStore
        )
        async let distanceRaw = RawSampleFetcher.distance(
            for: hkWorkout, healthStore: healthStore
        )
        async let hrRaw = RawSampleFetcher.samples(
            for: hkWorkout,
            quantityType: HKQuantityType(.heartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            healthStore: healthStore
        )
        async let strideRaw = RawSampleFetcher.samples(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningStrideLength),
            unit: .meter(),
            healthStore: healthStore
        )
        async let powerRaw = RawSampleFetcher.samples(
            for: hkWorkout,
            quantityType: HKQuantityType(.runningPower),
            unit: .watt(),
            healthStore: healthStore
        )
        async let stepRaw = RawSampleFetcher.steps(
            for: hkWorkout, healthStore: healthStore
        )

        // 1) 计算原始分段
        let lapEvents = hkWorkout.workoutEvents?
            .filter { $0.type == .lap }
            .map(\.dateInterval) ?? []

        let rawSplits = SplitsCalculator.compute(
            officialDistance: officialDistance,
            workoutStartDate: hkWorkout.startDate,
            workoutEndDate: hkWorkout.endDate,
            lapEvents: lapEvents,
            locations: filteredLocations,
            activeSegments: activeSegments,
            speedSamples: await speedRaw,
            distanceSamples: await distanceRaw
        )

        // 2) 起点对齐修正（-3s）
        let adjusted = SplitsCalculator.adjustFirstSplit(rawSplits, offset: -3)

        // 3) 附加每段指标
        return SplitsCalculator.attachDetails(
            splits: adjusted,
            activeSegments: activeSegments,
            heartRate: await hrRaw,
            strideLength: await strideRaw,
            stepCount: await stepRaw,
            power: await powerRaw
        )
    }

    // MARK: - 分段私有：活动段解析

    /// 提取并合并 HKWorkout 中的活动段。
    /// 优先用 `.segment` 事件；缺失时从 `.pause` / `.resume` 拼出活动段。
    private static func extractActiveSegments(from hkWorkout: HKWorkout) -> [DateInterval] {
        guard let events = hkWorkout.workoutEvents, !events.isEmpty else { return [] }

        // 1) 优先：segment 事件
        let segments = events
            .filter { $0.type == .segment }
            .map { $0.dateInterval }

        if !segments.isEmpty {
            return merge(segments)
        }

        // 2) 回退：从 pause / resume 拼活动段
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

        return merge(active)
    }

    /// 合并重叠的区间
    private static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
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

    // MARK: - 分段私有：路由拉取与过滤

    /// 拉取 workout 的原始路线点
    private static func fetchRoute(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> [CLLocation] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { c in
            let predicate = HKQuery.predicateForObjects(from: hkWorkout)
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                c.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            healthStore.execute(query)
        }

        guard let route = routes.first else { return [] }

        return await withCheckedContinuation { c in
            var locations: [CLLocation] = []
            var resumed = false
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, _ in
                if let batch { locations.append(contentsOf: batch) }
                if done, !resumed {
                    resumed = true
                    c.resume(returning: locations)
                }
            }
            healthStore.execute(query)
        }
    }

    /// 分段口径的精度 + 速度过滤
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
}

// MARK: - 纯函数计算引擎

/// 公里分段的计算引擎（纯函数）
enum SplitsCalculator {

    // MARK: - 主入口

    /// 计算公里分段。优先使用 lap events，否则回退到距离曲线切分。
    static func compute(
        officialDistance: Double?,
        workoutStartDate: Date,
        workoutEndDate: Date,
        lapEvents: [DateInterval] = [],
        locations: [CLLocation] = [],
        activeSegments: [DateInterval] = [],
        speedSamples: [MetricPoint] = [],
        distanceSamples: [MetricPoint] = []
    ) -> [KilometerSplit] {
        let official = officialDistance ?? 0

        // 1) lap events 路径
        if let lap = lapSplits(
            from: lapEvents,
            officialDistance: official,
            workoutDuration: workoutEndDate.timeIntervalSince(workoutStartDate)
        ) {
            return lap
        }

        // 2) 距离曲线路径
        return curveSplits(
            from: locations,
            officialDistance: official > 0 ? official : nil,
            workoutStartDate: workoutStartDate,
            workoutEndDate: workoutEndDate,
            activeSegments: activeSegments,
            speedSamples: speedSamples,
            distanceSamples: distanceSamples
        )
    }

    // MARK: - Lap events 路径

    /// 从 lap events 提取分段（不可用时返回 nil）
    static func lapSplits(
        from lapEvents: [DateInterval],
        officialDistance: Double,
        workoutDuration: TimeInterval
    ) -> [KilometerSplit]? {
        let laps = lapEvents.sorted { $0.start < $1.start }
        guard laps.count >= 2 else { return nil }

        // lap 总时长不能远小于 workout 时长（否则不是完整的按公里 lap）
        let lapTotal = laps.reduce(0.0) { $0 + $1.duration }
        guard lapTotal > workoutDuration * 0.6 else { return nil }

        // lap 数量要和距离吻合（±1 容忍尾段）
        let expectedKm = Int(officialDistance / 1000)
        guard abs(laps.count - expectedKm) <= 1 else { return nil }

        return laps.enumerated().map { idx, lap in
            KilometerSplit(
                index: idx + 1,
                distance: 1000,
                duration: lap.duration,
                startDate: lap.start
            )
        }
    }

    // MARK: - 距离曲线路径

    /// 从轨迹 / 距离样本 / 速度样本计算每公里分段
    static func curveSplits(
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
        let endDate   = workoutEndDate

        var curve: [(date: Date, cumDist: Double)] = []

        // ---------- 1a. distanceWalkingRunning 原始样本（首选） ----------
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
            if let official = officialDistance,
               let total = curve.last?.cumDist, total > 100 {
                let scale = official / total
                curve = curve.map { ($0.date, $0.cumDist * scale) }
            }
        }

        // ---------- 1b. runningSpeed 积分（次选） ----------
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
            if let official = officialDistance,
               let total = curve.last?.cumDist, total > 100 {
                let scale = official / total
                curve = curve.map { ($0.date, $0.cumDist * scale) }
            }
        }

        // ---------- 1c. GPS 累加（兜底） ----------
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
            if let official = officialDistance,
               let total = curve.last?.cumDist, total > 100 {
                let scale = official / total
                curve = curve.map { ($0.date, $0.cumDist * scale) }
            }
        }

        let totalDist = curve.last?.cumDist ?? 0
        guard totalDist >= 500 else { return [] }

        // ---------- 曲线 → 时间（二分） ----------
        func dateAtDistance(_ target: Double) -> Date? {
            guard let last = curve.last, last.cumDist >= target else { return nil }

            var lo = 0, hi = curve.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if curve[mid].cumDist < target { lo = mid + 1 } else { hi = mid }
            }
            guard lo > 0 else { return curve[0].date }

            let d0 = curve[lo - 1].cumDist, d1 = curve[lo].cumDist
            let t0 = curve[lo - 1].date,   t1 = curve[lo].date
            let ratio = (d1 - d0) > 0 ? (target - d0) / (d1 - d0) : 0
            return t0.addingTimeInterval(t1.timeIntervalSince(t0) * ratio)
        }

        // ---------- 活动时长（剔除暂停） ----------
        let hasSegments = !activeSegments.isEmpty
        func activeDuration(from a: Date, to b: Date) -> TimeInterval {
            guard b > a else { return 0 }
            if !hasSegments { return b.timeIntervalSince(a) }
            var total: TimeInterval = 0
            for seg in activeSegments {
                let s = max(a, seg.start)
                let e = min(b, seg.end)
                if e > s { total += e.timeIntervalSince(s) }
            }
            return total
        }

        // ---------- 生成分段 ----------
        let officialTotal = officialDistance ?? totalDist
        let fullKmCount   = Int(officialTotal / 1000)
        let tailMeters    = officialTotal - Double(fullKmCount) * 1000
        let hasTail       = tailMeters >= 100

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

    // MARK: - 附加每段聚合指标

    /// 为分段附加心率 / 步幅 / 步频 / 功率等聚合指标
    static func attachDetails(
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

    // MARK: - 辅助：过滤 / 统计

    /// 过滤出 [start, end) 内、且落在活动段中的样本
    static func samples(
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
    static func mean(_ points: [MetricPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    /// 按时间比例加权的求和（用于步数分摊）
    /// - Note: 假设每个样本代表的时长为 3 秒
    static func weightedSum(
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
            let sampleEnd   = pt.date.addingTimeInterval(sampleDuration)

            var overlap: TimeInterval = 0
            for ws in windowSegments {
                let s = max(sampleStart, ws.start)
                let e = min(sampleEnd,   ws.end)
                if e > s { overlap += e.timeIntervalSince(s) }
            }
            guard overlap > 0 else { continue }

            let ratio = overlap / sampleDuration
            total += pt.value * ratio
        }
        return total
    }

    // MARK: - 修正

    /// 起点对齐修正：第 1 段起点通常略早于 GPS 启动，-3s 让统计更贴近实际。
    static func adjustFirstSplit(
        _ splits: [KilometerSplit],
        offset: TimeInterval = -3
    ) -> [KilometerSplit] {
        guard let first = splits.first, first.index == 1 else { return splits }
        var copy = splits
        copy[0] = KilometerSplit(
            index: first.index,
            distance: first.distance,
            duration: max(0, first.duration + offset),
            startDate: first.startDate
        )
        return copy
    }
}

// MARK: - 原始样本抓取（仅供分段路径使用）

private enum RawSampleFetcher {

    /// 通用离散样本（心率 / 步幅 / 功率 / 速度）
    static func samples(
        for hkWorkout: HKWorkout,
        quantityType: HKQuantityType,
        unit: HKUnit,
        healthStore: HKHealthStore
    ) async -> [MetricPoint] {
        let predicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                ]
            ) { _, samples, _ in
                let pts: [MetricPoint] = (samples as? [HKQuantitySample])?
                    .compactMap {
                        let v = $0.quantity.doubleValue(for: unit)
                        guard v.isFinite, v > 0 else { return nil }
                        return MetricPoint(date: $0.startDate, value: v)
                    } ?? []
                continuation.resume(returning: pts)
            }
            healthStore.execute(q)
        }
    }

    /// distanceWalkingRunning：同源过滤 + 用 endDate 归位
    static func distance(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> [MetricPoint] {
        let type = HKQuantityType(.distanceWalkingRunning)
        let timePredicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )
        let sourcePredicate = HKQuery.predicateForObjects(from: hkWorkout.sourceRevision.source)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate, sourcePredicate
        ])

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: combined,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
                ]
            ) { _, samples, _ in
                let pts: [MetricPoint] = (samples as? [HKQuantitySample])?
                    .compactMap {
                        let m = $0.quantity.doubleValue(for: .meter())
                        guard m.isFinite, m > 0 else { return nil }
                        return MetricPoint(date: $0.endDate, value: m)
                    } ?? []
                continuation.resume(returning: pts)
            }
            healthStore.execute(q)
        }
    }

    /// stepCount：同源过滤
    static func steps(
        for hkWorkout: HKWorkout,
        healthStore: HKHealthStore
    ) async -> [MetricPoint] {
        let type = HKQuantityType(.stepCount)
        let timePredicate = HKQuery.predicateForSamples(
            withStart: hkWorkout.startDate,
            end: hkWorkout.endDate,
            options: .strictStartDate
        )
        let sourcePredicate = HKQuery.predicateForObjects(from: hkWorkout.sourceRevision.source)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate, sourcePredicate
        ])

        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: combined,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                ]
            ) { _, samples, _ in
                let pts: [MetricPoint] = (samples as? [HKQuantitySample])?
                    .compactMap {
                        let c = $0.quantity.doubleValue(for: .count())
                        guard c.isFinite, c > 0 else { return nil }
                        return MetricPoint(date: $0.startDate, value: c)
                    } ?? []
                continuation.resume(returning: pts)
            }
            healthStore.execute(q)
        }
    }
}
