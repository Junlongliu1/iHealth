//  ReadinessModels.swift
//  iHealth
//
//  职责：健康数据模型 + 计算引擎 + 全局 Store。
//
//  · DailyMetrics        —— 每天一条原始数据（HRV / RHR / 睡眠 / TSS），
//                           是缓存的持久化单元。
//  · ReadinessSnapshot   —— 由 DailyMetrics 计算出的当日快照，
//                           包含 CTL / ATL / TSB / 各项评分 / 准备度，
//                           是所有卡片和详情页的数据源。
//  · ReadinessCalculator —— 纯函数计算引擎（无副作用、无状态）：
//                           CTL / ATL 递推、各分项 0–100 映射、
//                           一致性加成、快照序列生成。
//  · BodyMetricsStore    —— @Observable 全局数据源，
//                           负责 load / refresh / sync / 缓存合并。
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

    private static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 100) -> Double {
        min(max(v, lo), hi)
    }

    // MARK: 负荷

    static func updateLoad(prevCTL: Double, prevATL: Double, tss: Double) -> (ctl: Double, atl: Double) {
        let ctl = prevCTL + (tss - prevCTL) / 42
        let atl = prevATL + (tss - prevATL) / 7
        return (ctl, atl)
    }

    // MARK: TSB 分（钟形曲线，峰值在 +10）

    /// TSB = +10 时 100 分，两侧衰减；负侧衰减更快。
    /// 这修正了原线性映射"越新鲜越好"的误导——TSB ≥ +20 通常意味着训练不足。
    static func tsbScore(tsb: Double) -> Double {
        let peak: Double = 10
        if tsb >= peak {
            return clamp(100 - (tsb - peak) * 0.8)
        }
        let m = peak - tsb  // > 0
        switch m {
        case ..<10:      return clamp(100 - m * 1.5)              // TSB 10 → 0 分区间
        case 10..<20:    return clamp(85 - (m - 10) * 2.0)        // TSB 0 → -10
        case 20..<30:    return clamp(65 - (m - 20) * 2.5)        // TSB -10 → -20
        case 30..<40:    return clamp(40 - (m - 30) * 3.0)        // TSB -20 → -30
        default:         return clamp(max(0, 10 - (m - 40) * 1.0))// TSB -30 以下
        }
    }

    // MARK: HRV（对数变换）

    /// HRV 呈对数正态分布。使用 ln(trend) − ln(baseline) 的 z 值映射更稳健，
    /// 避免"基线高的人对小幅下降过度敏感、基线低的人对同比例下降无感"。
    static func hrvScore(
        trend: Double,
        baseline: Double,
        baselineSD: Double? = nil
    ) -> Double {
        guard baseline > 0, trend > 0 else { return 50 }   // 无数据时返回中性，不虚高
        let logRatio = log(trend) - log(baseline)
        let sd = baselineSD ?? 0.15                        // ln(HRV) 的日常 SD 经验值
        let z = logRatio / sd
        return clamp(50 + 50 * tanh(z * 0.5))
    }

    /// ln 域的标准差，用于 HRV 打分。样本不足时返回 nil。
    static func logSD(_ values: [Double]) -> Double? {
        let filtered = values.filter { $0 > 0 }
        guard filtered.count >= 5 else { return nil }
        let logs = filtered.map { log($0) }
        let meanLog = logs.reduce(0, +) / Double(logs.count)
        let variance = logs.map { pow($0 - meanLog, 2) }.reduce(0, +) / Double(logs.count - 1)
        let sd = sqrt(variance)
        // 限制在生理合理范围，防止小样本导致的极端 z
        return min(max(sd, 0.05), 0.30)
    }

    // MARK: RHR（非对称分段）

    /// 中性区 ±3 bpm 得 75 分；降低时缓慢加分，升高时加速扣分。
    /// 生理上 RHR 升高比降低更值得警惕。
    static func rhrScore(today: Double, baseline: Double) -> Double {
        guard baseline > 0, today > 0 else { return 50 }
        let delta = today - baseline
        switch delta {
        case ..<(-6):     return 100
        case -6..<(-3):   return 100 - (delta + 6) * (25.0 / 3.0)   // -6 → 100, -3 → 75
        case -3...3:      return 75
        case 3..<6:       return 75 - (delta - 3) * (25.0 / 3.0)    // 3 → 75, 6 → 50
        default:          return max(0, 50 - (delta - 6) * 8)       // 6 → 50, 10 → 18
        }
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

        // 时长分：非对称 V 型（睡少扣得快，睡多扣得慢）
        let delta = hours - sleepTargetHours
        let durationScore: Double
        if delta >= 0 {
            durationScore = clamp(100 - delta * 12)   // 睡多：12 分/小时
        } else {
            durationScore = clamp(100 + delta * 20)   // 睡少：20 分/小时
        }

        // 质量分：深睡 1.0 / REM 0.9 / 浅睡 0.3
        // 典型构成 18% / 22% / 60% → 0.552 为满分基准
        var qualityScore = durationScore
        let stageTotal = deep + rem + light
        if stageTotal > 0 {
            let unitValue = (deep * 1.0 + rem * 0.9 + light * 0.3) / stageTotal
            qualityScore = clamp(unitValue / 0.552 * 100)
        }

        // 效率分：85% 为中性(60 分)，95% 满分
        let efficiencyScore = clamp(60 + (efficiency - 85) * 4)

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

        // 冷启动：用前 7 天 TSS 均值作为初始 CTL/ATL，下限 10
        let warmupCount = min(7, sorted.count)
        let warmupTSS = sorted.prefix(warmupCount).map(\.tss).reduce(0, +) / Double(warmupCount)
        let coldStart = max(warmupTSS, 10)
        var ctl = coldStart
        var atl = coldStart

        for i in 0..<sorted.count {
            let day = sorted[i]
            let updated = updateLoad(prevCTL: ctl, prevATL: atl, tss: day.tss)
            ctl = updated.ctl
            atl = updated.atl

            let hrvWindow7  = Array(sorted[max(0, i - 6)...i]).map { $0.hrv }
            let hrvWindow28 = Array(sorted[max(0, i - 27)...i]).map { $0.hrv }
            let hrvTrend    = mean(hrvWindow7)
            let hrvBaseline = median(hrvWindow28)
            let hrvSD       = logSD(hrvWindow28)

            let rhrWindow = Array(sorted[max(0, i - 13)...i]).map { $0.rhr }
            let rhrBaseline = median(rhrWindow)

            let tsb = ctl - atl
            let tsbS = tsbScore(tsb: tsb)
            let hrvS = hrvScore(trend: hrvTrend, baseline: hrvBaseline, baselineSD: hrvSD)
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

    // MARK: 一致性加成（连续函数版）

    /// 用连续 sigmoid 代替硬阈值，避免用户看到"39 分不扣、40 分扣"的跳变。
    private static func applyConsistencyBonus(
        recovery: Double,
        hrvScore: Double,
        rhrScore: Double
    ) -> Double {
        let minScore = min(hrvScore, rhrScore)
        let maxScore = max(hrvScore, rhrScore)

        // 双低惩罚：min 越低惩罚越强，最多 −10%
        let lowFactor = 1.0 - max(0, 40 - minScore) / 40 * 0.10

        // 双高奖励：min 越高奖励越强，最多 +5%
        let highFactor = 1.0 + max(0, minScore - 70) / 30 * 0.05

        // 解离惩罚：HRV 和 RHR 差异过大（>40）时轻微扣分，最多 −5%
        let divergence = maxScore - minScore
        let divergenceFactor = 1.0 - max(0, divergence - 40) / 60 * 0.05

        return clamp(recovery * lowFactor * highFactor * divergenceFactor)
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
