//
//  VitalsDotChart.swift
//  iHealth
//
//  生命体征点状图。
//  每行一个指标，横向范围条 + 位置点，
//  归一化到典型范围中，超出范围时点变粉色。
//  仅渲染指标列表，标题由调用方提供。
//

import SwiftUI

struct VitalsDotChart: View {
    let vitals: HealthManager.VitalsData?
    let sleepDuration: TimeInterval?

    // MARK: - 单指标数据模型

    private struct VitalMetric: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let value: Double?
        let normalRange: ClosedRange<Double>
        let color: Color

        /// 归一化到 0~1（0.5 = 典型范围中点）
        var normalizedPosition: Double? {
            guard let value else { return nil }
            let lower = normalRange.lowerBound
            let upper = normalRange.upperBound
            return min(max((value - lower) / (upper - lower), 0), 1)
        }

        var isNormal: Bool {
            guard let value else { return false }
            return normalRange.contains(value)
        }

        var displayValue: String {
            guard let value else { return "--" }
            switch name {
            case "体温", "睡眠":
                return String(format: "%.1f", value)
            default:
                return "\(Int(value))"
            }
        }

        var unit: String {
            switch name {
            case "心率", "呼吸": return "次/分"
            case "体温":            return "°C"
            case "血氧":            return "%"
            case "睡眠":            return "小时"
            default:                return ""
            }
        }

        /// 生效的颜色：正常 → 指标色；异常 → 粉色
        var activeColor: Color {
            isNormal ? color : .pink
        }
    }

    // MARK: - 五项指标

    private var metrics: [VitalMetric] {
        let sleepHours: Double? = sleepDuration.map { $0 / 3600 }
        return [
            VitalMetric(name: "心率", icon: "heart.fill",
                        value: vitals?.heartRate,
                        normalRange: 50...100, color: .red),
            VitalMetric(name: "呼吸", icon: "wind",
                        value: vitals?.respiratoryRate,
                        normalRange: 12...20, color: .cyan),
            VitalMetric(name: "体温", icon: "thermometer.medium",
                        value: vitals?.wristTemperature,
                        normalRange: 35.0...37.5, color: .orange),
            VitalMetric(name: "血氧", icon: "drop.fill",
                        value: vitals?.bloodOxygen,
                        normalRange: 95...100, color: .blue),
            VitalMetric(name: "睡眠", icon: "moon.zzz.fill",
                        value: sleepHours,
                        normalRange: 7...9, color: .indigo)
        ]
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if metrics.allSatisfy({ $0.value == nil }) {
                Text("暂无数据")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(metrics) { metric in
                        metricRow(metric)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 单行

    private func metricRow(_ metric: VitalMetric) -> some View {
        HStack(spacing: 6) {
            // 图标
            Image(systemName: metric.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(metric.activeColor)
                .frame(width: 14)

            // 名称
            Text(metric.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            // 横向范围条 + 点
            GeometryReader { geo in
                let dotSize: CGFloat = 9
                let inset: CGFloat = dotSize / 2
                let trackWidth = max(geo.size.width - dotSize, 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: trackWidth, height: 4)
                        .offset(x: inset)

                    Capsule()
                        .fill(metric.color.opacity(0.18))
                        .frame(width: trackWidth * 0.5, height: 4)
                        .offset(x: inset + trackWidth * 0.25)

                    if let pos = metric.normalizedPosition {
                        Circle()
                            .fill(metric.activeColor)
                            .overlay(
                                Circle().stroke(.white.opacity(0.85), lineWidth: 1.2)
                            )
                            .frame(width: dotSize, height: dotSize)
                            .shadow(color: metric.activeColor.opacity(0.45), radius: 2)
                            .offset(x: inset + trackWidth * pos - dotSize / 2)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: pos)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            // 数值
            Text(metric.displayValue)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(metric.value == nil ? Color.secondary.opacity(0.5) : metric.activeColor)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)

            // 单位
            Text(metric.unit)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .leading)
        }
    }
}
