//  SportAdviceCard.swift
//  iHealth
//
//  职责：身体 Tab 的「运动建议」卡片。
//
//  · 顶部：横向运动 SportChip 选择器（7 种运动）
//  · 下部：当日建议文案（标题 / 标签 / 详细说明）
//
//  建议由 SportAdviceEngine 计算，卡片本身只负责
//  切换选中的运动类型和展示。

import SwiftUI

struct SportAdviceCard: View {
    let snapshot: ReadinessSnapshot
    @Binding var selectedSport: SportType

    @State private var store = BodyMetricsStore.shared

    @Environment(\.cardCornerRadius) private var cardRadius

    private var advice: SportAdvice {
        SportAdviceEngine.advice(
            for: selectedSport,
            snapshot: snapshot,
            recentSnapshots: store.allSnapshots
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sportPicker

            Divider()

            adviceBody
        }
        .glassCard(cornerRadius: cardRadius)
        .animation(.snappy(duration: 0.3), value: selectedSport)
    }

    // MARK: - 运动选择器

    private var sportPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SportType.allCases) { sport in
                    SportChip(
                        sport: sport,
                        isSelected: sport == selectedSport
                    ) {
                        withAnimation(.snappy(duration: 0.32)) {
                            selectedSport = sport
                        }
                    }
                }
            }
            // 给 chip 的 glass 上下留空间，避免被裁到边缘
            .padding(.vertical, 4)
        }
        // 强制 ScrollView 占满父级可用宽度，不随内容膨胀，
        // 这样 clipShape 的边界才会落在卡片圆角上。
        .frame(maxWidth: .infinity)
    }

    // MARK: - 建议正文

    private var adviceBody: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(advice.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: advice.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(advice.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityDecorative()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("\(selectedSport.displayName)建议")
                        .font(.headline)
                        .contentTransition(.interpolate)
                        .animation(.snappy(duration: 0.3), value: selectedSport)

                    Text(advice.tag)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(advice.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(advice.color.opacity(0.12), in: Capsule())
                        .contentTransition(.interpolate)
                        .animation(.snappy(duration: 0.3), value: advice.tag)
                }

                Text(advice.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .contentTransition(.interpolate)
                    .animation(.snappy(duration: 0.3), value: advice.title)

                Text(advice.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.interpolate)
                    .animation(.snappy(duration: 0.3), value: advice.detail)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 运动胶囊

private struct SportChip: View {
    let sport: SportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: sport.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(sport.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(isSelected ? .regular.tint(.accentColor) : .regular, in: .capsule)
        .animation(.snappy(duration: 0.32), value: isSelected)
        .accessibilityLabel(sport.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
