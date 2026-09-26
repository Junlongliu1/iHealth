//
//  ReadinessModels.swift
//  iHealth
//

import Foundation
import Observation

// MARK: - 每日原始数据

struct DailyMetrics: Identifiable, Hashable, Codable {
    var id: Date { date }
    var date: Date
    var hrv: Double
    var rhr: Double
    var sleepHours: Double
    var sleepEfficiency: Double
    var deepSleepHours: Double
    var remSleepHours: Double
    var lightSleepHours: Double
    var tss: Double
}

// MARK: - 快照

struct ReadinessSnapshot: Identifiable {
    var id: Date { date }
    var date: Date
    var ctl: Double
    var atl: Double
    var tsb: Double

    var hrvTrend: Double
    var hrvBaseline: Double
    var rhrBaseline: Double

    var tsbScore: Double
    var hrvScore: Double
    var rhrScore: Double
    var sleepScore: Double

    var recovery: Double
    var readiness: Double
}

// MARK: - 计算引擎

enum ReadinessCalculator {

    static let sleepTargetHours: Double = 8.0
    private static let coldStartCTL: Double = 40
    private static let coldStartATL: Double = 40

    private static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 100) -> Double {
        min(max(v, lo), hi)
    }

    // MARK: 负荷

    static func updateLoad(prevCTL: Double, prevATL: Double, tss: Double) -> (ctl: Double, atl: Double) {
        let ctl = prevCTL + (tss - prevCTL) / 42
        let atl = prevATL + (tss - prevATL) / 7
        return (ctl, atl)
    }

    static func tsbScore(tsb: Double) -> Double {
        clamp(60 + tsb * 1.5)
    }

    // MARK: HRV

    static func hrvScore(trend: Double, baseline: Double) -> Double {
        guard baseline > 0, trend > 0 else { return 70 }
        let ratio = trend / baseline
        return clamp(50 + 50 * tanh(3 * (ratio - 1)))
    }

    // MARK: RHR

    static func rhrScore(today: Double, baseline: Double) -> Double {
        guard baseline > 0, today > 0 else { return 75 }
        return clamp(75 - (today - baseline) * 8)
    }

    // MARK: 睡眠

    static func sleepScore(
        hours: Double,
        efficiency: Double,
        deep: Double,
        rem: Double,
        light: Double
    ) -> Double {
        guard hours > 0 else { return 0 }

        let durationScore = clamp(100 - abs(hours - sleepTargetHours) * 20)

        var qualityScore = durationScore
        let stageTotal = deep + rem + light
        if stageTotal > 0 {
            let unitValue = (deep * 1.0 + rem * 0.8 + light * 0.3) / stageTotal
            qualityScore = clamp(unitValue / 0.54 * 100)
        }

        let efficiencyScore = clamp((efficiency - 60) * (100.0 / 40.0))

        return clamp(durationScore * 0.4 + qualityScore * 0.4 + efficiencyScore * 0.2)
    }

    // MARK: 工具

    static func median(_ values: [Double]) -> Double {
        let filtered = values.filter { $0 > 0 }
        guard !filtered.isEmpty else { return 0 }
        let sorted = filtered.sorted()
        let n = sorted.count
        if n % 2 == 0 {
            return (sorted[n/2 - 1] + sorted[n/2]) / 2
        }
        return sorted[n/2]
    }

    static func mean(_ values: [Double]) -> Double {
        let filtered = values.filter { $0 > 0 }
        guard !filtered.isEmpty else { return 0 }
        return filtered.reduce(0, +) / Double(filtered.count)
    }

    // MARK: 快照序列

    static func snapshots(for history: [DailyMetrics]) -> [ReadinessSnapshot] {
        let sorted = history.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        var results: [ReadinessSnapshot] = []
        results.reserveCapacity(sorted.count)
        var ctl = coldStartCTL
        var atl = coldStartATL

        for i in 0..<sorted.count {
            let day = sorted[i]
            let updated = updateLoad(prevCTL: ctl, prevATL: atl, tss: day.tss)
            ctl = updated.ctl
            atl = updated.atl

            let hrvWindow7  = Array(sorted[max(0, i - 6)...i]).map { $0.hrv }
            let hrvWindow28 = Array(sorted[max(0, i - 27)...i]).map { $0.hrv }
            let hrvTrend    = mean(hrvWindow7)
            let hrvBaseline = median(hrvWindow28)

            let rhrWindow = Array(sorted[max(0, i - 13)...i]).map { $0.rhr }
            let rhrBaseline = median(rhrWindow)

            let tsb = ctl - atl
            let tsbS = tsbScore(tsb: tsb)
            let hrvS = hrvScore(trend: hrvTrend, baseline: hrvBaseline)
            let rhrS = rhrScore(today: day.rhr, baseline: rhrBaseline)
            let slpS = sleepScore(
                hours: day.sleepHours,
                efficiency: day.sleepEfficiency,
                deep: day.deepSleepHours,
                rem: day.remSleepHours,
                light: day.lightSleepHours
            )

            var recovery = clamp(hrvS * 0.40 + slpS * 0.35 + rhrS * 0.25)
            recovery = applyConsistencyBonus(recovery: recovery, hrvScore: hrvS, rhrScore: rhrS)

            let readiness = clamp(recovery * 0.70 + tsbS * 0.30)

            results.append(
                ReadinessSnapshot(
                    date: day.date,
                    ctl: ctl,
                    atl: atl,
                    tsb: tsb,
                    hrvTrend: hrvTrend,
                    hrvBaseline: hrvBaseline,
                    rhrBaseline: rhrBaseline,
                    tsbScore: tsbS,
                    hrvScore: hrvS,
                    rhrScore: rhrS,
                    sleepScore: slpS,
                    recovery: recovery,
                    readiness: readiness
                )
            )
        }
        return results
    }

    static func snapshot(for history: [DailyMetrics]) -> ReadinessSnapshot? {
        snapshots(for: history).last
    }

    // MARK: 一致性加成

    private static func applyConsistencyBonus(recovery: Double, hrvScore: Double, rhrScore: Double) -> Double {
        if hrvScore < 40 && rhrScore < 40 {
            return clamp(recovery * 0.90)
        }
        if hrvScore > 70 && rhrScore > 70 {
            return clamp(recovery * 1.05)
        }
        if hrvScore < 35 && rhrScore > 65 {
            return clamp(recovery * 0.95)
        }
        return recovery
    }
}

// MARK: - Store

@MainActor
@Observable
final class BodyMetricsStore {
    static let shared = BodyMetricsStore()

    private(set) var history: [DailyMetrics] = []
    /// 缓存的快照序列，避免每次访问都重算。
    private(set) var allSnapshots: [ReadinessSnapshot] = []

    var isLoading = false
    var isSyncing = false
    var loadError: String?

    private let healthKit = HealthKitManager.shared
    private let cache = MetricsCache.shared

    private let fullWindowDays = 60
    private let overlapDays = 7
    private let minSyncInterval: TimeInterval = 300

    private var lastSyncAttempt: Date?

    private init() {
        setHistory(cache.loadMetrics())
    }

    var todaySnapshot: ReadinessSnapshot? {
        allSnapshots.last
    }

    private func setHistory(_ newValue: [DailyMetrics]) {
        history = newValue
        allSnapshots = ReadinessCalculator.snapshots(for: newValue)
    }

    // MARK: - 加载

    func load() async {
        if let last = lastSyncAttempt,
           Date().timeIntervalSince(last) < minSyncInterval,
           !history.isEmpty {
            return
        }
        lastSyncAttempt = Date()

        isLoading = history.isEmpty
        loadError = nil

        await healthKit.requestAuthorization()
        if let error = healthKit.authorizationError {
            if history.isEmpty {
                loadError = error
            }
            isLoading = false
            return
        }

        await sync()
        isLoading = false
    }

    func refresh() async {
        lastSyncAttempt = Date()
        await sync()
    }

    func clearCache() {
        cache.clear()
        setHistory([])
    }

    // MARK: - 同步

    private func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliest = calendar.date(byAdding: .day, value: -fullWindowDays, to: today) ?? today

        let startDate: Date
        if let lastSync = cache.loadLastSync(),
           let overlapStart = calendar.date(byAdding: .day, value: -overlapDays, to: lastSync) {
            startDate = max(overlapStart, earliest)
        } else {
            startDate = earliest
        }

        let fetched = await healthKit.fetchDailyMetrics(from: startDate, to: Date())

        let hasAny = fetched.contains {
            $0.hrv > 0 || $0.rhr > 0 || $0.sleepHours > 0 || $0.tss > 0
        }

        if !hasAny && history.isEmpty {
            loadError = "未能读取到健康数据，请到「健康」App → 头像 → 隐私 → App 中确认本应用已授权。"
            return
        }

        var map: [Date: DailyMetrics] = [:]
        for m in history { map[m.date] = m }
        for m in fetched {
            if let existing = map[m.date] {
                map[m.date] = mergeDaily(old: existing, new: m)
            } else {
                map[m.date] = m
            }
        }

        let merged = map.values
            .filter { $0.date >= earliest }
            .sorted { $0.date < $1.date }

        setHistory(merged)
        cache.saveMetrics(merged)
        cache.saveLastSync(Date())
    }

    private func mergeDaily(old: DailyMetrics, new: DailyMetrics) -> DailyMetrics {
        DailyMetrics(
            date: old.date,
            hrv:              new.hrv > 0              ? new.hrv              : old.hrv,
            rhr:              new.rhr > 0              ? new.rhr              : old.rhr,
            sleepHours:       new.sleepHours > 0       ? new.sleepHours       : old.sleepHours,
            sleepEfficiency:  new.sleepEfficiency > 0  ? new.sleepEfficiency  : old.sleepEfficiency,
            deepSleepHours:   new.deepSleepHours > 0   ? new.deepSleepHours   : old.deepSleepHours,
            remSleepHours:    new.remSleepHours > 0    ? new.remSleepHours    : old.remSleepHours,
            lightSleepHours:  new.lightSleepHours > 0  ? new.lightSleepHours  : old.lightSleepHours,
            tss:              new.tss > 0              ? new.tss              : old.tss
        )
    }
}
