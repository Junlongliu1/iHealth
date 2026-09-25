//
//  DesignSystem.swift
//  iHealth
//

import SwiftUI

enum DSLayout {
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 11
    static let cornerRadius: CGFloat = 22
}

extension View {
    /// 统一液态玻璃卡片
    func cardGlass(cornerRadius: CGFloat = DSLayout.cornerRadius) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - 卡片头

struct SettingsCardHeader: View {
    let icon: String
    var iconColor: Color = .secondary
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - 设置行

struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    var detail: String? = nil
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    tint.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let detail {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.vertical, DSLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, DSLayout.rowHorizontalPadding + 40)
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}
