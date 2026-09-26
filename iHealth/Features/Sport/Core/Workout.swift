//
//  Workout.swift
//  iHealth
//

import SwiftUI
import HealthKit
import CoreLocation

// MARK: - 运动类型

enum WorkoutType: String, CaseIterable, Identifiable, Codable {
    case running        = "跑步"
    case walking        = "步行"
    case cycling        = "骑行"
    case swimming       = "游泳"
    case hiking         = "徒步"
    case mountaineering = "登山"
    case badminton      = "羽毛球"
    case strength       = "力量训练"
    case yoga           = "瑜伽"
    case other          = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .running:        return "figure.run"
        case .walking:        return "figure.walk"
        case .cycling:        return "figure.outdoor.cycle"
        case .swimming:       return "figure.pool.swim"
        case .hiking:         return "figure.hiking"
        case .mountaineering: return "figure.climbing"
        case .badminton:      return "figure.badminton"
        case .strength:       return "dumbbell.fill"
        case .yoga:           return "figure.yoga"
        case .other:          return "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .running:        return .orange
        case .walking:        return .green
        case .cycling:        return .blue
        case .swimming:       return .cyan
        case .hiking:         return .brown
        case .mountaineering: return .indigo
        case .badminton:      return .yellow
        case .strength:       return .purple
        case .yoga:           return .pink
        case .other:          return .gray
        }
    }

    /// 是否属于有距离数据的运动
    var hasDistance: Bool {
        [.running, .walking, .cycling, .swimming, .hiking, .mountaineering].contains(self)
    }
}

// MARK: - WorkoutType ↔ HKWorkoutActivityType 映射

extension WorkoutType {
    init(hkActivityType: HKWorkoutActivityType) {
        switch hkActivityType {
        case .running:
            self = .running
        case .walking:
            self = .walking
        case .cycling:
            self = .cycling
        case .swimming:
            self = .swimming
        case .hiking:
            self = .hiking
        case .climbing,
             .stairs,
             .stairClimbing:
            self = .mountaineering
        case .badminton,
             .tennis,
             .tableTennis,
             .squash,
             .racquetball,
             .pickleball:
            self = .badminton
        case .traditionalStrengthTraining,
             .functionalStrengthTraining,
             .coreTraining:
            self = .strength
        case .yoga,
             .flexibility,
             .mindAndBody,
             .pilates,
             .taiChi:
            self = .yoga
        default:
            self = .other
        }
    }
}

// MARK: - 运动记录

struct Workout: Identifiable, Hashable {
    let id: UUID
    let type: WorkoutType
    let startDate: Date
    /// 时长（秒）
    let duration: TimeInterval
    /// 距离（米），可选
    let distance: Double?
    /// 消耗（千卡），可选
    let calories: Double?
    let note: String?

    init(
        id: UUID = UUID(),
        type: WorkoutType,
        startDate: Date,
        duration: TimeInterval,
        distance: Double? = nil,
        calories: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.calories = calories
        self.note = note
    }

    var endDate: Date { startDate.addingTimeInterval(duration) }

    /// 例如 "32 分钟" / "1 小时 12 分"
    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分" : "\(hours) 小时"
        }
        if minutes > 0 { return "\(minutes) 分钟" }
        return "\(total) 秒"
    }

    /// 例如 "5.20 公里" / "800 米"
    var formattedDistance: String? {
        guard let distance else { return nil }
        if distance >= 1000 {
            return String(format: "%.2f 公里", distance / 1000)
        }
        return "\(Int(distance)) 米"
    }

    var formattedCalories: String? {
        guard let calories else { return nil }
        return "\(Int(calories)) 千卡"
    }
}

// MARK: - HKWorkout → Workout（iOS 18 使用 statistics(for:) 读取）

extension Workout {
    init(hkWorkout: HKWorkout) {
        self.id = hkWorkout.uuid
        self.type = WorkoutType(hkActivityType: hkWorkout.workoutActivityType)
        self.startDate = hkWorkout.startDate
        self.duration = hkWorkout.duration

        // 距离（米）：按运动类型选择正确的 quantity type
        let distanceType: HKQuantityType? = {
            switch hkWorkout.workoutActivityType {
            case .cycling:
                return HKQuantityType(.distanceCycling)
            case .swimming:
                return HKQuantityType(.distanceSwimming)
            default:
                return HKQuantityType(.distanceWalkingRunning)
            }
        }()

        if let distanceType,
           let quantity = hkWorkout.statistics(for: distanceType)?.sumQuantity() {
            self.distance = quantity.doubleValue(for: .meter())
        } else {
            self.distance = nil
        }

        // 消耗（千卡）：优先使用 activeEnergyBurned
        if let quantity = hkWorkout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity() {
            self.calories = quantity.doubleValue(for: .kilocalorie())
        } else {
            self.calories = nil
        }

        self.note = hkWorkout.metadata?["HKWorkoutBrandName"] as? String
    }
}

struct KilometerMarker: Identifiable, Hashable {
    let id: Int                               // 第几公里
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: KilometerMarker, rhs: KilometerMarker) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - 跑步详情数据

struct RunDetail {
    var startDate: Date
    var duration: TimeInterval
    var distance: Double?              // 米

    var averagePace: TimeInterval?     // 秒 / 公里
    var averageHeartRate: Double?      // bpm
    var maxHeartRate: Double?          // bpm
    var averageStrideLength: Double?   // 米
    var averageCadence: Double?        // 步 / 分钟
    var elevationAscended: Double?     // 米
    var activeEnergy: Double?          // 千卡
    var averagePower: Double?          // 瓦特
    var verticalOscillation: Double?   // 厘米

    var route: [CLLocationCoordinate2D]
    var sourceName: String? = nil      // "Apple Watch" / "iPhone"
    var kilometerMarkers: [KilometerMarker] = []
}

// MARK: - 公里分段（PB 用）

/// 一次跑步的每 1 公里分段
struct KilometerSplit: Identifiable, Hashable {
    var id: Int { index }
    /// 第几公里（1-based）
    let index: Int
    /// 该段距离（米），标准为 1000
    let distance: Double
    /// 该段用时（秒）
    let duration: TimeInterval
    /// 该段起始时间
    let startDate: Date
}

// MARK: - 个人最好成绩

struct PersonalBest: Identifiable, Hashable {
    var id: String { label }
    /// 显示名："1 km" / "半马"
    let label: String
    /// 目标距离（米）
    let distance: Double
    /// 用时（秒），nil 表示没有满足条件的跑步
    var time: TimeInterval?
    /// 达成日期
    var date: Date?
}

// MARK: - SwiftUI Preview 用示例数据（仅开发期使用）

#if DEBUG
extension Workout {
    static let preview: [Workout] = {
        let cal = Calendar.current
        let now = Date()

        func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        return [
            Workout(type: .running,  startDate: date(daysAgo: 0, hour: 7, minute: 30),
                    duration: 32 * 60, distance: 5_200, calories: 340),
            Workout(type: .walking,  startDate: date(daysAgo: 0, hour: 12, minute: 45),
                    duration: 18 * 60, distance: 1_400, calories: 70),
            Workout(type: .badminton, startDate: date(daysAgo: 0, hour: 19),
                    duration: 60 * 60, distance: nil, calories: 420),
            Workout(type: .strength, startDate: date(daysAgo: 0, hour: 21),
                    duration: 45 * 60, distance: nil, calories: 260),
            Workout(type: .cycling,  startDate: date(daysAgo: 1, hour: 8),
                    duration: 68 * 60, distance: 24_300, calories: 520),
            Workout(type: .yoga,     startDate: date(daysAgo: 1, hour: 21),
                    duration: 30 * 60, distance: nil, calories: 110),
            Workout(type: .running,  startDate: date(daysAgo: 2, hour: 6, minute: 50),
                    duration: 51 * 60, distance: 8_600, calories: 560),
            Workout(type: .swimming, startDate: date(daysAgo: 3, hour: 20),
                    duration: 40 * 60, distance: 1_200, calories: 380),
            Workout(type: .hiking,   startDate: date(daysAgo: 5, hour: 9),
                    duration: 3 * 3600 + 20 * 60, distance: 12_800, calories: 890),
            Workout(type: .mountaineering, startDate: date(daysAgo: 7, hour: 6),
                    duration: 5 * 3600 + 30 * 60, distance: 9_400, calories: 1_650)
        ]
    }()
}
#endif
