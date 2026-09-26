//
//  SplitsCalculator.swift
//  iHealth
//

import Foundation
import CoreLocation

/// 公里分段的计算引擎（纯函数）
enum SplitsCalculator {

    // MARK: - 主入口

    /// 计算公里分段。优先使用 lap events，否则回退到距离曲线切分。
    /// - Parameters:
    ///   - officialDistance: 官方总距离（来自 workout.distance），用于校准
    ///   - workoutStartDate / workoutEndDate: 整体时间范围
    ///   - lapEvents: HKWorkout 中 type == .lap 的事件区间
    ///   - locations: 已过滤的轨迹点（按时间升序）
    ///   - activeSegments: HKWorkout 的活动段（用于剔除暂停时间）
    ///   - speedSamples: 速度样本（米/秒）
    ///   - distanceSamples: 距离增量样本（米，使用 endDate 归位）
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
    /// - Note: 使用"墙钟时间"作为区间（下一段的 startDate 作为本段 end），
    ///         再通过 activeSegments 剔除暂停时间，使样本统计更准确。
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
