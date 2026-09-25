//
//  VitalsDotChart.swift
//  iHealth
//
//  生命体征环形图。
//  高度自适应：圆环大小随卡片高度缩放。
//  显示一位小数。
//

import SwiftUI

struct VitalsDotChart: View {
    let vitals: HealthManager.VitalsData?
    let sleepDuration: TimeInterval?

    private let rowSpacing: CGFloat = 6

    private struct VitalMetric: Identifiable {
        let id = UUID()
        let name: String
        let value: Double?
        let normalRange: ClosedRange<Double>
        let color: Color

        var isNormal: Bool {
            guard let value else { return true }
            return normalRange.contains(value)
        }

        var progress: Double {
            guard let value else { return 0 }
            let lo = normalRange.lowerBound
            let hi = normalRange.upperBound
            return min(max((value - lo) / (hi - lo), 0), 1)
        }

        var displayValue: String {
            guard let value else { return "--" }
            return String(format: "%.1f", value)
        }

        var activeColor: Color { isNormal ? color : .pink }
    }

    private var metrics: [VitalMetric] {
        let sleepHours: Double? = sleepDuration.map { $0 / 3600 }
        return [
            VitalMetric(name: "心率", value: vitals?.heartRate,
                        normalRange: 40...60, color: .red),
            VitalMetric(name: "呼吸", value: vitals?.respiratoryRate,
                        normalRange: 12...20, color: .cyan),
            VitalMetric(name: "体温", value: vitals?.wristTemperature,
                        normalRange: 33.0...36.0, color: .orange),
            VitalMetric(name: "血氧", value: vitals?.bloodOxygen,
                        normalRange: 95...100, color: .blue),
            VitalMetric(name: "睡眠", value: sleepHours,
                        normalRange: 7...9, color: .indigo)
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(metrics.count, 1)
            let totalSpacing = rowSpacing * CGFloat(count - 1)
            let rowHeight = max((geo.size.height - totalSpacing) / CGFloat(count), 14)
            let ringSize = min(22, max(14, rowHeight - 2))
            let valueSize = min(17, max(12, rowHeight * 0.82))

            VStack(spacing: rowSpacing) {
                ForEach(metrics) { metric in
                    row(metric, ringSize: ringSize, valueSize: valueSize)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func row(_ metric: VitalMetric, ringSize: CGFloat, valueSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: max(2, ringSize * 0.14))

                Circle()
                    .trim(from: 0, to: max(metric.progress, 0.04))
                    .stroke(
                        metric.activeColor.gradient,
                        style: StrokeStyle(lineWidth: max(2, ringSize * 0.14), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if metric.value == nil {
                    Text("–")
                        .font(.system(size: ringSize * 0.4))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: ringSize, height: ringSize)

            Text(metric.name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(metric.displayValue)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(metric.value == nil
                                 ? Color.secondary.opacity(0.5)
                                 : metric.activeColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
