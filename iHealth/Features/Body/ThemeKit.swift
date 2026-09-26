//
//  AppTheme.swift
//  iHealth
//

import SwiftUI

// MARK: - 环境值

extension EnvironmentValues {
    @Entry var cardCornerRadius: CGFloat = 16
    @Entry var cardPadding: CGFloat = 16
    @Entry var cardSpacing: CGFloat = 16
}

// MARK: - 玻璃卡片修饰符

extension View {

    func glassCard(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func glassCard(
        tint: Color,
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .glassEffect(
                .regular.tint(tint.opacity(0.18)),
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

// MARK: - 可访问性辅助

extension View {
    func accessibilityDecorative() -> some View {
        self.accessibilityHidden(true)
    }
}

// MARK: - 卡片入场级联动画

private struct CardRevealModifier: ViewModifier {
    let revealed: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
            .blur(radius: revealed ? 0 : 6)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.86).delay(delay),
                value: revealed
            )
    }
}

extension View {
    /// 卡片入场：淡入 + 上移 + 模糊消散，用 delay 做级联。
    func cardReveal(_ revealed: Bool, delay: Double = 0) -> some View {
        modifier(CardRevealModifier(revealed: revealed, delay: delay))
    }
}

// MARK: - 环形指标

struct MetricRing: View {
    let score: Double
    let color: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 72
    var fontSize: CGFloat = 24

    private var progress: Double {
        max(0.02, min(score / 100, 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.75, dampingFraction: 0.85), value: score)

            Text("\(Int(score.rounded()))")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText(value: score))
                .animation(.snappy(duration: 0.45), value: score)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 贡献度进度条

struct ContributionBar: View {
    let color: Color
    let fraction: Double   // 0...1
    var height: CGFloat = 4

    @State private var width: CGFloat = 0
    @State private var appeared = false

    private var clamped: Double {
        max(0.02, min(fraction, 1))
    }

    private var displayedProgress: Double {
        appeared ? clamped : 0
    }

    var body: some View {
        Capsule()
            .fill(color.opacity(0.12))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: width * displayedProgress)
            }
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                    appeared = true
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: clamped)
    }
}
