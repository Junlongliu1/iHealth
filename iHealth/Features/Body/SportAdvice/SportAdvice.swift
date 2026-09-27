//  SportAdvice.swift
//  iHealth
//
//  职责：运动建议生成引擎（纯函数，无状态）。
//
//  · baseLevel(for:)              —— 由 readiness 判定基础强度等级，
//                                    TSB 仅在极端值时一票否决
//  · adjustedLevel(_:for:)        —— 按运动类型调整
//                                    （羽毛球/登山降档，骑行升档）
//  · trendAdjusted(_:recent:)     —— 连续低准备度时降档
//  · advice(for:snapshot:...)     —— 组合输出建议文案
//
//  输出纯数据，渲染交给 SportAdviceCard。

import SwiftUI

// MARK: - 强度等级

enum SportAdviceLevel {
    case rest       // 休息
    case easy       // 轻松
    case moderate   // 中等
    case hard       // 高强度
}

// MARK: - 建议模型

struct SportAdvice {
    let tag: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

// MARK: - 建议引擎

enum SportAdviceEngine {

    // MARK: 公开入口

    static func advice(
        for sport: SportType,
        snapshot s: ReadinessSnapshot,
        recentSnapshots: [ReadinessSnapshot] = []
    ) -> SportAdvice {
        // 1. 基础等级：以 readiness 为主，TSB 仅极端值否决
        let base = baseLevel(for: s)

        // 2. 按运动类型调整（高冲击降档 / 低冲击升档）
        let adjusted = adjustedLevel(base, for: sport)

        // 3. 连续疲劳降档
        let final = trendAdjusted(adjusted, recentSnapshots: recentSnapshots)

        return advice(for: sport, level: final, snapshot: s)
    }

    // MARK: - 等级判定

    /// 基础强度等级：准备度为主判据，TSB 只在极端值时否决。
    /// readiness 本身已经包含 TSB 的加权贡献，所以这里不再用 TSB 硬门槛，
    /// 避免 TSB 被重复计算导致误判。
    private static func baseLevel(for s: ReadinessSnapshot) -> SportAdviceLevel {
        // 极端疲劳：无条件休息
        if s.tsb < -35 { return .rest }

        switch s.readiness {
        case 85...:
            // 准备度极高，但 TSB 明显偏负时降为 moderate（避免带疲劳硬上强度）
            return s.tsb < -15 ? .moderate : .hard
        case 70..<85:
            return .moderate
        case 50..<70:
            return .easy
        case 30..<50:
            // 低准备度但 TSB 很正（可能停训多天），允许轻松活动
            return s.tsb > 10 ? .easy : .rest
        default:
            return .rest
        }
    }

    /// 按运动类型调整：
    /// · 羽毛球、登山：神经/关节冲击大，恢复成本高 → 降一档
    /// · 骑行：低冲击，恢复成本低 → 升一档
    /// · 其余（跑步 / 徒步 / 步行 / 其他）：保持
    private static func adjustedLevel(
        _ base: SportAdviceLevel,
        for sport: SportType
    ) -> SportAdviceLevel {
        switch sport {
        case .badminton, .mountaineering:
            return downshift(base)
        case .cycling:
            return upshift(base)
        default:
            return base
        }
    }

    /// 连续疲劳检测：近 3 天中有 ≥ 3 天 readiness < 60 时降一档。
    /// 单日偏低可能是偶然（睡差一晚），连续偏低才代表累积疲劳。
    private static func trendAdjusted(
        _ level: SportAdviceLevel,
        recentSnapshots: [ReadinessSnapshot]
    ) -> SportAdviceLevel {
        let recent = recentSnapshots.suffix(3)
        guard recent.count >= 3 else { return level }

        let lowDays = recent.filter { $0.readiness < 60 }.count
        return lowDays >= 3 ? downshift(level) : level
    }

    // MARK: - 等级升降

    private static func downshift(_ l: SportAdviceLevel) -> SportAdviceLevel {
        switch l {
        case .hard:     return .moderate
        case .moderate: return .easy
        case .easy:     return .rest
        case .rest:     return .rest
        }
    }

    private static func upshift(_ l: SportAdviceLevel) -> SportAdviceLevel {
        switch l {
        case .rest:     return .easy
        case .easy:     return .moderate
        case .moderate: return .hard
        case .hard:     return .hard
        }
    }

    // MARK: - 分发

    private static func advice(
        for sport: SportType,
        level: SportAdviceLevel,
        snapshot s: ReadinessSnapshot
    ) -> SportAdvice {
        let readiness = Int(s.readiness.rounded())
        let tsb = String(format: "%+.0f", s.tsb)

        switch sport {
        case .running:        return runningAdvice(level: level, readiness: readiness, tsb: tsb)
        case .walking:        return walkingAdvice(level: level, readiness: readiness, tsb: tsb)
        case .badminton:      return badmintonAdvice(level: level, readiness: readiness, tsb: tsb)
        case .hiking:         return hikingAdvice(level: level, readiness: readiness, tsb: tsb)
        case .mountaineering: return mountaineeringAdvice(level: level, readiness: readiness, tsb: tsb)
        case .cycling:        return cyclingAdvice(level: level, readiness: readiness, tsb: tsb)
        case .other:          return genericAdvice(level: level, readiness: readiness, tsb: tsb)
        }
    }

    // MARK: - 跑步

    private static func runningAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议跑步",
                detail: "准备度 \(readiness)，TSB \(tsb)。身体需要恢复，建议完全休息或只做散步拉伸。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松跑 30–45 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。以轻松配速跑 30–45 分钟，心率控制在有氧区间。",
                icon: "figure.run",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "节奏跑或有氧跑",
                detail: "准备度 \(readiness)，TSB \(tsb)。可跑 30–50 分钟节奏跑，配速接近阈值。",
                icon: "figure.run",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "间歇跑或节奏跑",
                detail: "准备度 \(readiness)，TSB \(tsb)。可安排 4–6 组 800m–1km 间歇，或 20–30 分钟阈值跑。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 步行

    private static func walkingAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "轻松散步",
                detail: "准备度 \(readiness)，TSB \(tsb)。可慢走 15–20 分钟，避免长时间或快走。",
                icon: "figure.walk",
                color: .orange
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "日常步行 30–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。保持正常步速，心率控制在低有氧区间。",
                icon: "figure.walk",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "快走 40–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。可加速到微喘但能对话的程度，保持 40–60 分钟。",
                icon: "figure.walk",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "坡度快走或长距离步行",
                detail: "准备度 \(readiness)，TSB \(tsb)。可安排 60 分钟以上的快走，加入坡度或间歇加速段。",
                icon: "figure.walk",
                color: .green
            )
        }
    }

    // MARK: - 羽毛球

    private static func badmintonAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议高强度对抗",
                detail: "准备度 \(readiness)，TSB \(tsb)。可做轻松挥拍或技术练习，避免比赛。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松对打 30–45 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。以技术练习和轻松对打为主，避免全力扣杀。",
                icon: "figure.badminton",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "常规对抗 45–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。可进行常规双打或强度适中的单打，注意补水。",
                icon: "figure.badminton",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "高强度比赛或训练",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合正式比赛或高强度单打，赛前充分热身。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 徒步

    private static func hikingAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议徒步",
                detail: "准备度 \(readiness)，TSB \(tsb)。身体需要恢复，建议改做轻松散步。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "短途平缓徒步",
                detail: "准备度 \(readiness)，TSB \(tsb)。可走 1–2 小时平缓路线，爬升控制在 200m 内。",
                icon: "figure.hiking",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "中等徒步 2–4 小时",
                detail: "准备度 \(readiness)，TSB \(tsb)。可走 2–4 小时，爬升 300–600m，注意节奏。",
                icon: "figure.hiking",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "长距离或大爬升徒步",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合 4 小时以上或爬升 600m+ 的路线，补给要跟上。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 登山

    private static func mountaineeringAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。登山对体能要求高，建议改期或改做轻松活动。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "低强度短途登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。选择难度较低、爬升 300m 内的路线，控制时间在 2–3 小时。",
                icon: "mountain.2.fill",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "中等强度登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。可挑战爬升 600–1000m 的路线，注意配速和补水。",
                icon: "mountain.2.fill",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "高强度登山",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合长距离、大爬升或技术性路线，需充分准备装备和补给。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 骑行

    private static func cyclingAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "不建议骑行",
                detail: "准备度 \(readiness)，TSB \(tsb)。建议完全休息，或只做非常轻松的活动。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松骑行 45–60 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。保持有氧区间，避免爬坡或冲刺。",
                icon: "figure.outdoor.cycle",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "节奏骑行 60–90 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。可进行 60–90 分钟稳定节奏骑行，接近阈值强度。",
                icon: "figure.outdoor.cycle",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "间歇或阈值骑行",
                detail: "准备度 \(readiness)，TSB \(tsb)。适合 FTP 间歇或长距离高强度骑行。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }

    // MARK: - 其他

    private static func genericAdvice(level: SportAdviceLevel, readiness: Int, tsb: String) -> SportAdvice {
        switch level {
        case .rest:
            return SportAdvice(
                tag: "休息",
                title: "建议休息",
                detail: "准备度 \(readiness)，TSB \(tsb)。身体需要恢复，建议改做轻松活动。",
                icon: "bed.double.fill",
                color: .red
            )
        case .easy:
            return SportAdvice(
                tag: "低强度",
                title: "轻松活动 30–45 分钟",
                detail: "准备度 \(readiness)，TSB \(tsb)。以轻松强度进行，注意控制时长。",
                icon: "figure.mixed.cardio",
                color: .yellow
            )
        case .moderate:
            return SportAdvice(
                tag: "中强度",
                title: "中等强度训练",
                detail: "准备度 \(readiness)，TSB \(tsb)。可按计划进行中等强度训练。",
                icon: "figure.mixed.cardio",
                color: .mint
            )
        case .hard:
            return SportAdvice(
                tag: "高强度",
                title: "适合高强度训练",
                detail: "准备度 \(readiness)，TSB \(tsb)。状态良好，可进行高强度训练或测试。",
                icon: "bolt.fill",
                color: .green
            )
        }
    }
}
