//  ThemeKit.swift
//  iHealth
//
//  职责：全局视觉基础设施。
//
//  · EnvironmentValues 扩展 —— cardCornerRadius / cardPadding / cardSpacing
//  · glassCard(...)          —— 玻璃卡片统一修饰符（含硬边界裁剪）
//  · cardReveal(...)         —— 卡片入场动画（淡入 + 上移 + 模糊消散）
//  · accessibilityDecorative —— 装饰性元素 a11y 简写
//  · PulsingHeartLoader      —— 加载动画（脉冲心跳 + 扩散波纹）
//  · MetricRing              —— 0–100 分环形指示器（入场生长动画）
//  · ContributionBar         —— 贡献度水平进度条
//
//  所有跨页面复用的视觉元素集中在此。

import SwiftUI

// MARK: - 环境值

extension EnvironmentValues {
    @Entry var cardCornerRadius: CGFloat = 16
    @Entry var cardPadding: CGFloat = 16
    @Entry var cardSpacing: CGFloat = 16
}

// MARK: - 玻璃卡片修饰符

extension View {

    /// 统一玻璃卡片。
    ///
    /// 顺序很关键：`padding → clipShape → glassEffect`
    /// · clipShape 让"卡片圆角"成为真正的物理边界，内容（含 ScrollView 溢出）会被裁掉；
    /// · glassEffect 在裁剪后的边界上绘制玻璃背景，保持完整不被切。
    func glassCard(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func glassCard(
        tint: Color,
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

// MARK: - 加载动画

/// 脉冲心跳 + 扩散波纹加载指示器
struct PulsingHeartLoader: View {
    var tint: Color = .red
    var size: CGFloat = 68
    var ringCount: Int = 3

    @State private var animate = false

    var body: some View {
        ZStack {
            // 扩散的波纹环
            ForEach(0..<ringCount, id: \.self) { i in
                Circle()
                    .stroke(tint.opacity(0.28), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(animate ? 2.2 : 0.8)
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: 2.0)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 2.0 / Double(ringCount)),
                        value: animate
                    )
            }

            // 底色圆
            Circle()
                .fill(tint.opacity(0.10))
                .frame(width: size * 1.1, height: size * 1.1)
                .overlay(
                    Circle()
                        .stroke(tint.opacity(0.15), lineWidth: 1)
                )

            // 心跳图标（symbolEffect 自带脉冲）
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint.gradient)
                .symbolEffect(.pulse.byLayer)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear {
            // 触发波纹动画
            DispatchQueue.main.async {
                animate = true
            }
        }
    }
}

// MARK: - 环形指标

struct MetricRing: View {
    let score: Double
    let color: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 72
    var fontSize: CGFloat = 24

    @State private var appeared = false

    private var progress: Double {
        max(0.02, min(score / 100, 1))
    }

    private var displayedProgress: Double {
        appeared ? progress : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: displayedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.85, dampingFraction: 0.82), value: displayedProgress)

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
        .onAppear {
            // 让初始渲染先落在 0，再弹到目标值
            DispatchQueue.main.async {
                appeared = true
            }
        }
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
