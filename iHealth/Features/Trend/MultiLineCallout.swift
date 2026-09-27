//  MultiLineCallout.swift
//  iHealth
//
//  多线图表气泡（横排单行）。
//  每项 = 色点 + 名称 + 数值，用 3pt 圆点分隔。
//  高度与单线气泡相同，不会从图表顶部溢出。
//  背景固定磨砂，不随图表颜色变化。

import SwiftUI

struct MultiLineCallout: View {
    struct Item {
        let color: Color
        let name: String
        let value: String
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Circle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3, height: 3)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 6, height: 6)

                    Text(item.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(item.value)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color(.systemBackground).opacity(0.92))
                .background(.ultraThinMaterial, in: Capsule())
        }
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
