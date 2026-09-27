//
//  PBEngine.swift
//  iHealth
//

import Foundation

/// 个人最好成绩计算引擎（纯函数）
enum PBEngine {

    static let targets: [(label: String, distance: Double)] = [
        ("1 km",  1_000),
        ("3 km",  3_000),
        ("5 km",  5_000),
        ("10 km", 10_000),
        ("半马",  21_097.5),
        ("全马",  42_195)
    ]

    /// 单个 split 的标准距离（1 公里）
    private static let km: Double = 1_000

    /// 距离容差（米）：吸收 GPS / 浮点误差
    private static let eps: Double = 0.5

    // MARK: - 入口

    static func compute(
        workouts: [Workout],
        splitsCache: [UUID: [KilometerSplit]]
    ) -> [PersonalBest] {
        targets.map { target in
            var bestTime: TimeInterval = .infinity
            var bestDate: Date? = nil

            for workout in workouts {
                guard let splits = splitsCache[workout.id], !splits.isEmpty,
                      let totalDist = workout.distance,
                      totalDist + eps >= target.distance
                else { continue }

                for start in 0..<splits.count {
                    guard let t = windowTime(
                        splits: splits,
                        start: start,
                        target: target.distance,
                        totalDist: totalDist
                    ) else { continue }

                    if t < bestTime {
                        bestTime = t
                        bestDate = splits[start].startDate
                    }
                }
            }

            return PersonalBest(
                label: target.label,
                distance: target.distance,
                time: bestDate == nil ? nil : bestTime,
                date: bestDate
            )
        }
    }

    // MARK: - 单个窗口

    /// 从 split[start] 的起点开始累加，恰好覆盖 target 米。
    /// 覆盖不足 → 返回 nil，避免短窗口冒充长距离。
    private static func windowTime(
        splits: [KilometerSplit],
        start: Int,
        target: Double,
        totalDist: Double
    ) -> TimeInterval? {
        let n = splits.count
        var covered: Double = 0
        var time: TimeInterval = 0

        for i in start..<n {
            let segDist: Double = (i == n - 1)
                ? max(0, min(totalDist - Double(n - 1) * km, km))
                : km
            guard segDist > eps else { continue }

            let remaining = target - covered

            if segDist <= remaining + eps {
                // 整段吃下
                covered += segDist
                time += splits[i].duration
                if covered >= target - eps {
                    return time
                }
            } else {
                // 只需要这一段的 remaining 米，按比例折算
                time += splits[i].duration * (remaining / segDist)
                return time
            }
        }

        // 走完所有 split 仍覆盖不足 → 这次跑步不能贡献该目标的 PB
        return nil
    }
}
