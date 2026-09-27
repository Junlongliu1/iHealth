//
//  RunningShoeStore.swift
//  iHealth
//

import Foundation
import Observation

@MainActor
@Observable
final class RunningShoeStore {
    static let shared = RunningShoeStore()

    var shoes: [RunningShoe] {
        didSet { saveShoes() }
    }

    /// 默认跑鞋（用于列表置顶 / 快速关联）
    var defaultShoeID: UUID? {
        didSet { saveDefault() }
    }

    /// workoutID → shoeID 的关联表
    var workoutShoeMap: [UUID: UUID] {
        didSet { saveAssignments() }
    }

    private init() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Keys.shoes),
           let decoded = try? JSONDecoder().decode([RunningShoe].self, from: data) {
            self.shoes = decoded
        } else {
            self.shoes = []
        }

        if let str = defaults.string(forKey: Keys.defaultShoe),
           let uuid = UUID(uuidString: str) {
            self.defaultShoeID = uuid
        } else {
            self.defaultShoeID = nil
        }

        if let data = defaults.data(forKey: Keys.assignments),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var map: [UUID: UUID] = [:]
            for (k, v) in decoded {
                if let wk = UUID(uuidString: k), let sk = UUID(uuidString: v) {
                    map[wk] = sk
                }
            }
            self.workoutShoeMap = map
        } else {
            self.workoutShoeMap = [:]
        }
    }

    // MARK: - 查询

    func shoe(id: UUID?) -> RunningShoe? {
        guard let id else { return nil }
        return shoes.first { $0.id == id }
    }

    func shoe(for workout: Workout) -> RunningShoe? {
        shoe(id: workoutShoeMap[workout.id])
    }

    func isDefault(_ shoe: RunningShoe) -> Bool {
        defaultShoeID == shoe.id
    }

    // MARK: - 关联

    func assign(_ shoeID: UUID?, to workout: Workout) {
        if let shoeID {
            workoutShoeMap[workout.id] = shoeID
        } else {
            workoutShoeMap.removeValue(forKey: workout.id)
        }
    }

    // MARK: - 增删改

    func add(_ shoe: RunningShoe) {
        shoes.append(shoe)
        if defaultShoeID == nil {
            defaultShoeID = shoe.id
        }
    }

    func update(_ shoe: RunningShoe) {
        guard let idx = shoes.firstIndex(where: { $0.id == shoe.id }) else { return }
        shoes[idx] = shoe
    }

    func delete(_ shoe: RunningShoe) {
        shoes.removeAll { $0.id == shoe.id }
        workoutShoeMap = workoutShoeMap.filter { $0.value != shoe.id }
        if defaultShoeID == shoe.id {
            defaultShoeID = shoes.first { !$0.isRetired }?.id ?? shoes.first?.id
        }
    }

    // MARK: - 统计

    /// 仅「已记录跑步」累计里程（米），不含初始里程
    func recordedDistance(for shoe: RunningShoe, workouts: [Workout]) -> Double {
        workouts
            .filter { workoutShoeMap[$0.id] == shoe.id }
            .compactMap(\.distance)
            .reduce(0, +)
    }

    /// 累计跑量（米）：初始里程 + 已记录跑步里程
    func totalDistance(for shoe: RunningShoe, workouts: [Workout]) -> Double {
        shoe.initialDistanceMeters + recordedDistance(for: shoe, workouts: workouts)
    }

    func runCount(for shoe: RunningShoe, workouts: [Workout]) -> Int {
        workouts.filter { workoutShoeMap[$0.id] == shoe.id }.count
    }

    /// 磨损进度，0...1.5（超过 1 表示已过寿命）
    func wearProgress(for shoe: RunningShoe, workouts: [Workout]) -> Double {
        guard shoe.maxDistanceMeters > 0 else { return 0 }
        let used = totalDistance(for: shoe, workouts: workouts)
        return min(max(used / shoe.maxDistanceMeters, 0), 1.5)
    }

    // MARK: - 持久化

    private func saveShoes() {
        if let data = try? JSONEncoder().encode(shoes) {
            UserDefaults.standard.set(data, forKey: Keys.shoes)
        }
    }

    private func saveDefault() {
        if let id = defaultShoeID {
            UserDefaults.standard.set(id.uuidString, forKey: Keys.defaultShoe)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.defaultShoe)
        }
    }

    private func saveAssignments() {
        var dict: [String: String] = [:]
        for (wk, sk) in workoutShoeMap {
            dict[wk.uuidString] = sk.uuidString
        }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Keys.assignments)
        }
    }

    private enum Keys {
        static let shoes       = "shoe.list"
        static let defaultShoe = "shoe.default"
        static let assignments = "shoe.assignments"
    }
}
