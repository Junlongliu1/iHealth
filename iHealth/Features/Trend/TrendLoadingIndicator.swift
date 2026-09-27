//  TrendLoadingIndicator.swift
//  iHealth
//
//  趋势页加载指示器。
//  · 双层扩散脉冲环
//  · 中心渐变圆 + 趋势图标
//  · 下方文案：正在读取趋势数据

import SwiftUI

struct TrendLoadingIndicator: View {
    @State private var ringPhase = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.80, blue: 0.44),  // 准备度绿
                Color(red: 0.20, green: 0.55, blue: 0.95)   // 恢复度蓝
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 22) {
            // 图标 + 脉冲环
            ZStack {
                // 外层脉冲环（大）
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.35),
                                Color.blue.opacity(0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 58, height: 58)
                    .scaleEffect(ringPhase ? 1.75 : 0.85)
                    .opacity(ringPhase ? 0 : 0.9)

                // 内层脉冲环（小）
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.45),
                                Color.blue.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 58, height: 58)
                    .scaleEffect(ringPhase ? 1.35 : 0.85)
                    .opacity(ringPhase ? 0 : 0.9)

                // 中心渐变圆
                Circle()
                    .fill(gradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: .green.opacity(0.30), radius: 12, y: 4)
                    .shadow(color: .blue.opacity(0.20), radius: 16, y: 6)

                // 中心图标
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 108, height: 108)

            // 文案
            VStack(spacing: 5) {
                Text("正在读取趋势数据")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Text("这可能需要几秒钟")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
        .onAppear {
            withAnimation(
                .easeOut(duration: 1.8)
                    .repeatForever(autoreverses: false)
            ) {
                ringPhase = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        TrendLoadingIndicator()
    }
}
