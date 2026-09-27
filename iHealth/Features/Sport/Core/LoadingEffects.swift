//
//  LoadingEffects.swift
//  iHealth
//
//  加载态与骨架屏通用动效
//

import SwiftUI

// MARK: - 微光

/// 在当前视图上叠加一层流动微光，用于骨架屏
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    var duration: Double = 1.8

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.35),
                            .white.opacity(0.10),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 1.2)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2.4)
                }
            }
            .mask(content)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(
                    .linear(duration: duration)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func shimmer(duration: Double = 1.8) -> some View {
        modifier(ShimmerModifier(duration: duration))
    }
}

// MARK: - 脉冲加载指示器

/// 运动页 / 详情页的高级加载指示器：脉冲圆环 + 跑步图标
struct PulseRunIndicator: View {
    var size: CGFloat = 54
    var caption: String? = nil

    @State private var isAnimating = false

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.62, blue: 0.2),
                Color(red: 1.0, green: 0.42, blue: 0.15)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(isAnimating ? 1.65 : 0.85)
                    .opacity(isAnimating ? 0 : 0.9)

                Circle()
                    .stroke(Color.orange.opacity(0.45), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(isAnimating ? 1.35 : 0.85)
                    .opacity(isAnimating ? 0 : 0.9)

                Circle()
                    .fill(gradient)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .shadow(color: .orange.opacity(0.35), radius: 12, y: 4)

                Image(systemName: "figure.run")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size * 1.9, height: size * 1.9)

            if let caption {
                Text(caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(
                .easeOut(duration: 1.8)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - 地图骨架

/// 顶部 Hero 地图的加载骨架：网格 + 脉冲图标 + 微光
struct HeroMapSkeleton: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.secondarySystemBackground),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { ctx, size in
                let step: CGFloat = 32
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                ctx.stroke(
                    path,
                    with: .color(Color.primary.opacity(0.04)),
                    lineWidth: 0.5
                )
            }

            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.pulse.byLayer, options: .repeating)

                Text("正在载入路线")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .shimmer(duration: 2.2)
    }
}
