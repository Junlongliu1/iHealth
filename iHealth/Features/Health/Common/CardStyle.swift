//
//  CardStyle.swift
//  iHealth
//
//  统一卡片外观：iOS 26+ 官方液态玻璃（Liquid Glass）。
//

import SwiftUI

extension View {
    /// 应用 iOS 26 官方液态玻璃卡片样式。
    /// - Parameter radius: 圆角半径，默认 18。
    func cardStyle(radius: CGFloat = 18) -> some View {
        glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }

    /// 可交互的液态玻璃（用于可点击的容器，例如 NavigationLink 内）。
    func interactiveCardStyle(radius: CGFloat = 18) -> some View {
        glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}
