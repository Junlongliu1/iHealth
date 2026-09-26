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
