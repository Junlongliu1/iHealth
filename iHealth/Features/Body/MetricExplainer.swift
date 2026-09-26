//
//  MetricExplainer.swift
//  iHealth
//

import SwiftUI

// MARK: - 数据模型

struct MetricExplanation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let sections: [Section]

    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }
}

// MARK: - 参数库

enum MetricLibrary {

    // MARK: 准备度

    static let readiness = MetricExplanation(
        id: "readiness",
        title: "准备度",
        subtitle: "今天适合承受多少训练",
        icon: "gauge.with.dots.needle.67percent",
        color: .green,
        sections: [
            .init(
                title: "是什么",
                body: "准备度综合了身体的恢复信号和当前的训练负荷背景，给出一个 0–100 的分数，用来判断今天是否适合进行高强度训练。"
            ),
            .init(
                title: "怎么算",
                body: "准备度 = 恢复度 × 70% + TSB分 × 30%\n\n恢复度占主导，因为身体的真实反应比训练计划更重要。TSB 提供训练负荷的背景信息，但不应该压过身体的实际状态。"
            ),
            .init(
                title: "怎么看",
                body: "85–100：巅峰状态，适合测试或高强度课\n70–84：良好，按计划训练即可\n50–69：一般，降低强度或缩短时长\n30–49：偏低，安排主动恢复\n0–29：恢复优先，完全休息"
            ),
            .init(
                title: "注意",
                body: "准备度是趋势指标，不是绝对判断。单日波动是正常的，连续 3 天以上的趋势才有参考价值。"
            )
        ]
    )

    // MARK: 恢复度

    static let recovery = MetricExplanation(
        id: "recovery",
        title: "恢复度",
        subtitle: "身体当前恢复到了什么程度",
        icon: "battery.100",
        color: .blue,
        sections: [
            .init(
                title: "是什么",
                body: "恢复度只看身体本身的恢复信号，不包含任何训练负荷信息。它回答的是：你的身体现在准备好了吗？"
            ),
            .init(
                title: "怎么算",
                body: "恢复度 = HRV分 × 40% + 睡眠分 × 35% + 静息心率分 × 25%\n\nHRV 权重最高，因为它最直接反映自主神经系统的恢复状态；睡眠是恢复的基础；静息心率作为辅助确认信号。"
            ),
            .init(
                title: "一致性加成",
                body: "当 HRV 和静息心率同时指向同一方向时，信号会加强：\n\n两者都偏低 → 恢复度额外扣 10%\n两者都良好 → 恢复度额外加 5%\n\n单一指标异常可能是测量误差，但多个指标同时异常通常意味着真实的疲劳累积。"
            ),
            .init(
                title: "怎么看",
                body: "70 以上：身体恢复良好\n50–69：恢复一般\n30–49：恢复不足\n0–29：恢复很差，建议休息"
            )
        ]
    )

    // MARK: HRV

    static let hrv = MetricExplanation(
        id: "hrv",
        title: "HRV（心率变异性）",
        subtitle: "自主神经系统的恢复状态",
        icon: "waveform.path.ecg",
        color: .blue,
        sections: [
            .init(
                title: "是什么",
                body: "HRV 是相邻两次心跳之间时间间隔的变化程度，单位毫秒（ms）。它反映了自主神经系统在「交感（应激）」和「副交感（恢复）」之间的平衡状态。\n\nHRV 高通常意味着恢复好，HRV 低则提示身体处于压力或疲劳状态。"
            ),
            .init(
                title: "怎么算分",
                body: "第一步：计算趋势值\n取过去 7 天 HRV 的平均值，作为当前趋势。\n\n第二步：计算基线\n取过去 28 天 HRV 的中位数，作为个人长期基线。\n\n第三步：映射到 0–100\n比率 = 趋势值 ÷ 基线\n分数 = 50 + 50 × tanh(3 × (比率 − 1))\n\n用 S 形曲线而不是线性映射，是为了让小幅偏离更稳定，大幅偏离时更快触发警告。"
            ),
            .init(
                title: "怎么看",
                body: "比率 ≥ 1.05：显著高于基线，恢复极好\n比率 0.95–1.05：正常范围\n比率 0.85–0.94：轻度抑制，需要留意\n比率 < 0.85：显著抑制，恢复不足"
            ),
            .init(
                title: "注意",
                body: "单日 HRV 波动很大，不要因为一天下降就恐慌。连续 3 天低于基线的 90% 才是值得关注的信号。测量条件（卧姿/坐姿、测量时长、是否深呼吸）也会影响数值，尽量每天保持一致。"
            )
        ]
    )

    // MARK: 静息心率

    static let rhr = MetricExplanation(
        id: "rhr",
        title: "静息心率（RHR）",
        subtitle: "心血管系统的负担水平",
        icon: "heart.fill",
        color: .pink,
        sections: [
            .init(
                title: "是什么",
                body: "静息心率是你完全安静状态下的心率，单位 bpm（次/分）。它反映了心血管系统在基础状态下的工作负荷。\n\n静息心率升高通常意味着疲劳累积、睡眠不足、脱水或潜在疾病。"
            ),
            .init(
                title: "怎么算分",
                body: "第一步：计算基线\n取过去 14 天晨起静息心率的中位数。\n\n第二步：计算偏离值\n偏离 = 今晨 RHR − 14天基线\n\n第三步：映射到 0–100\n分数 = 75 − 偏离 × 8\n\n每升高 1 bpm 扣 8 分。基线为 0 分偏离时得 75 分，是中性状态。"
            ),
            .init(
                title: "怎么看",
                body: "低于基线 3 bpm 以上：恢复极好\n基线 ±2 bpm：正常范围\n高于基线 3–5 bpm：轻度升高，注意恢复\n高于基线 6 bpm 以上：显著升高，需要警惕"
            ),
            .init(
                title: "注意",
                body: "静息心率受咖啡因、酒精、高温、情绪和睡眠质量影响。如果某天数值异常但 HRV 正常，可能是暂时性因素。"
            )
        ]
    )

    // MARK: 睡眠

    static let sleep = MetricExplanation(
        id: "sleep",
        title: "睡眠",
        subtitle: "昨晚睡眠对恢复的贡献",
        icon: "moon.zzz.fill",
        color: .purple,
        sections: [
            .init(
                title: "是什么",
                body: "睡眠是身体修复和恢复的核心。睡眠评分综合了昨晚的睡眠时长、睡眠阶段构成和睡眠效率，反映睡眠对恢复的实际贡献。"
            ),
            .init(
                title: "怎么算分",
                body: "睡眠分 = 时长分 × 40% + 质量分 × 40% + 效率分 × 20%\n\n时长分：以 8 小时为目标，每偏离 1 小时扣 20 分\n质量分：基于深睡、REM、浅睡的比例加权\n效率分：入睡时长 ÷ 在床时长，60% 为 0 分，100% 为满分"
            ),
            .init(
                title: "睡眠阶段权重",
                body: "不同阶段的恢复价值不同：\n\n深睡（N3）：权重 1.0，身体修复和免疫恢复\nREM：权重 0.8，记忆巩固和情绪调节\n浅睡（N1/N2）：权重 0.3，基础休息\n\n正常睡眠构成下，单位小时价值约为 0.54。深睡和 REM 占比越高，质量分越高。"
            ),
            .init(
                title: "怎么看",
                body: "85 以上：睡眠极佳\n70–84：睡眠良好\n50–69：睡眠一般\n30–49：睡眠不足\n0–29：严重睡眠不足，优先补觉"
            ),
            .init(
                title: "注意",
                body: "如果你的设备不支持睡眠阶段检测，质量分会自动退化为时长分，仅时长和效率参与评分。"
            )
        ]
    )

    // MARK: TSB

    static let tsb = MetricExplanation(
        id: "tsb",
        title: "TSB（训练压力平衡）",
        subtitle: "体能储备与疲劳的差值",
        icon: "chart.line.flattrend.down",
        color: .orange,
        sections: [
            .init(
                title: "是什么",
                body: "TSB 是 CTL 与 ATL 的差值，反映你当前是「新鲜」还是「疲劳」。它是训练计划里的核心参考指标，但不能单独作为状态判断。"
            ),
            .init(
                title: "怎么算",
                body: "TSB = CTL − ATL\n\nCTL 代表你的长期体能基础（42 天累积），ATL 代表你近期的疲劳（7 天累积）。两者相减，就是负荷层面的「净状态」。"
            ),
            .init(
                title: "怎么看",
                body: "TSB ≥ +10：非常新鲜，可能训练不足\n0 到 +10：新鲜，适合高质量训练\n−10 到 0：中性，正常训练区\n−10 到 −30：有目的的训练负荷区\n< −30：过度负荷，需要恢复"
            ),
            .init(
                title: "注意",
                body: "TSB 为负不代表状态差。系统的训练计划通常会让 TSB 在 −10 到 −30 之间波动，这是正常的负荷累积。关键是要在关键比赛或测试前让 TSB 回升到正值。"
            )
        ]
    )

    // MARK: CTL

    static let ctl = MetricExplanation(
        id: "ctl",
        title: "CTL（慢性训练负荷）",
        subtitle: "长期体能基础的近似指标",
        icon: "chart.line.uptrend.xyaxis",
        color: .teal,
        sections: [
            .init(
                title: "是什么",
                body: "CTL 是过去 42 天每日训练负荷（TSS）的指数加权移动平均值，常被用作「体能」的近似指标。数值越高，说明身体已适应越大的训练量。"
            ),
            .init(
                title: "怎么算",
                body: "CTL 采用递推计算：\n\nCTL今日 = CTL昨日 + (今日TSS − CTL昨日) ÷ 42\n\n近期训练的权重更高，越久远的训练权重越低。首次使用时从 40 起步，避免前两周被严重低估。"
            ),
            .init(
                title: "怎么看",
                body: "CTL 上升：体能正在积累\nCTL 持平：维持状态\nCTL 下降：体能正在流失\n\nCTL 的绝对值意义有限，关键在于它的变化趋势。"
            ),
            .init(
                title: "注意",
                body: "CTL 反映的是训练负荷，不等于实际运动表现。同样 CTL 的两个人，实际能力可能差异很大。"
            )
        ]
    )

    // MARK: ATL

    static let atl = MetricExplanation(
        id: "atl",
        title: "ATL（急性训练负荷）",
        subtitle: "近期疲劳的量化指标",
        icon: "chart.line.flattrend.down",
        color: .orange,
        sections: [
            .init(
                title: "是什么",
                body: "ATL 是过去 7 天每日训练负荷（TSS）的指数加权移动平均值，反映近期训练带来的疲劳程度。"
            ),
            .init(
                title: "怎么算",
                body: "ATL 采用递推计算：\n\nATL今日 = ATL昨日 + (今日TSS − ATL昨日) ÷ 7\n\n时间窗口比 CTL 短得多，所以 ATL 对近期训练量的变化非常敏感。一次高强度训练就能让 ATL 显著上升。"
            ),
            .init(
                title: "怎么看",
                body: "ATL 急剧上升：近期负荷大，疲劳累积\nATL 缓慢下降：正在恢复\nATL 与 CTL 的差值（即 TSB）决定了你的训练状态"
            ),
            .init(
                title: "注意",
                body: "ATL 是疲劳指标，不是负面指标。适当的 ATL 上升是训练刺激的必要条件。关键是不要让它持续远高于 CTL。"
            )
        ]
    )

    // MARK: 分项评分

    static let subScores = MetricExplanation(
        id: "subScores",
        title: "分项评分",
        subtitle: "构成恢复度的三个维度",
        icon: "list.bullet.rectangle",
        color: .gray,
        sections: [
            .init(
                title: "是什么",
                body: "分项评分把恢复度拆解成三个独立的 0–100 分数，让你清楚看到恢复度是被哪个维度拉低或拉高的。"
            ),
            .init(
                title: "HRV 分",
                body: "对比过去 7 天 HRV 趋势与 28 天个人基线，通过 S 形曲线映射到 0–100。反映自主神经系统的恢复状态，权重 40%。"
            ),
            .init(
                title: "睡眠分",
                body: "综合睡眠时长、睡眠阶段和睡眠效率，权重 35%。是恢复的基础，也是你能主动改善的最大杠杆。"
            ),
            .init(
                title: "RHR 分",
                body: "对比今晨静息心率与 14 天基线，每高 1 bpm 扣 8 分，权重 25%。作为 HRV 的辅助确认信号。"
            ),
            .init(
                title: "TSB 分",
                body: "把 TSB 映射到 0–100，用于计算准备度。TSB 分为 60 时表示中性，高于 60 表示新鲜，低于 60 表示疲劳累积。"
            )
        ]
    )
}

// MARK: - 说明页

struct MetricExplanationView: View {
    let explanation: MetricExplanation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    ForEach(explanation.sections) { section in
                        sectionView(section)
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(explanation.color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: explanation.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(explanation.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(explanation.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(explanation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionView(_ section: MetricExplanation.Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(section.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 可点击信息按钮

struct InfoDot: View {
    let color: Color

    var body: some View {
        Image(systemName: "info.circle")
            .font(.caption2)
            .foregroundStyle(color.opacity(0.7))
    }
}
