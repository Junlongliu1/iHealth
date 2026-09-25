//
//  CardStyle.swift
//  iHealth
//
//  统一卡片外观：背景、圆角、描边。
//

import SwiftUI

extension View {
    func cardStyle(radius: CGFloat = 18) -> some View {
        modifier(CardStyleModifier(radius: radius))
    }
}

private struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                colorScheme == .dark
                ? Color(red: 0.11, green: 0.11, blue: 0.12)
                : Color(.secondarySystemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
