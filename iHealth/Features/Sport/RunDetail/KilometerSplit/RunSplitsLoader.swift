//
//  RunSplitsLoader.swift
//  iHealth
//

import Foundation
import HealthKit
import CoreLocation

/// 从 HealthKit 拉取一次跑步的全部原始数据，并计算出公里分段
enum RunSplitsLoader {

    // MARK: - 主入口

    /// 对外主入口：拉取 + 计算 + 附加指标
    static func load(
        hkWorkout: HKWorkout,
        officialDistance: Double?,
        filteredLocations: [CLLocation],
        healthStore: HKHealthStore
    ) async -> [KilometerSplit] {

        let activeSegments = extractActiveSegments(from: hkWorkout)

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

    // MARK: - 活动段

    /// 提取并合并 HKWorkout 中的 segment 事件
    static func extractActiveSegments(from hkWorkout: HKWorkout) -> [DateInterval] {
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
}

// MARK: - 原始样本抓取

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
