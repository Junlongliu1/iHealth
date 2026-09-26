//
//  RunSummarySection.swift
//  iHealth
//

import SwiftUI

// MARK: - 顶部浮动玻璃工具栏

/// 跑步详情页顶部浮动工具栏：返回、分享、更多、标题
struct RunTopBar: View {
    let onBack: () -> Void
    let onShare: () -> Void
    let onMore: () -> Void
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 10) {
            GlassEffectContainer {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .circle)
                .glassEffectID("back", in: namespace)
            }

            Spacer()

            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        onShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 22)

                    Button {
                        onMore()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("actions", in: namespace)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .overlay {
            Text("iHealth")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.74, blue: 0.92),
                            Color(red: 0.55, green: 0.55, blue: 0.95)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 18)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("title", in: namespace)
        }
    }
}

// MARK: - 卡片头部：大字距离 / 日期 / 来源 / 头像

struct RunSummaryHeader: View {
    let detail: RunDetail?
    let workout: Workout

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(bigDistanceValue)
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(distanceUnit)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .offset(y: 1)
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(formattedDate)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                if let source = detail?.sourceName, !source.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: sourceIcon(for: source))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(source)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.75, blue: 0.4),
                                Color(red: 0.85, green: 0.5, blue: 0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Image(systemName: "person.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

                Text("Evron")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var bigDistanceValue: String {
        guard let distance = detail?.distance, distance > 0 else { return "--" }
        let km = (distance / 1000).truncated(to: 2)
        return String(format: "%.2f", km)
    }

    private var distanceUnit: String {
        detail?.distance != nil ? "km" : ""
    }

    private var formattedDate: String {
        workout.startDate.formatted(
            .dateTime.month(.twoDigits).day(.twoDigits)
                .weekday(.abbreviated)
                .hour().minute()
        )
    }

    private func sourceIcon(for name: String) -> String {
        name.localizedCaseInsensitiveContains("watch") ? "applewatch" : "iphone"
    }
}

// MARK: - 九宫格指标

struct RunMetricsGrid: View {
    let detail: RunDetail?

    var body: some View {
        let items: [MetricItem] = [
            .init(title: "运动时间",
                  value: RunDetailFormat.duration(detail?.duration),
                  unit: ""),

            .init(title: "平均配速",
                  value: RunDetailFormat.pace(detail?.averagePace),
                  unit: detail?.averagePace != nil ? "/km" : "",
                  accent: true),

            .init(title: "平均心率",
                  value: RunDetailFormat.heartRate(detail?.averageHeartRate),
                  unit: detail?.averageHeartRate != nil ? "bpm" : ""),

            .init(title: "最大心率",
                  value: RunDetailFormat.heartRate(detail?.maxHeartRate),
                  unit: detail?.maxHeartRate != nil ? "bpm" : ""),

            .init(title: "平均步频",
                  value: RunDetailFormat.cadence(detail?.averageCadence),
                  unit: detail?.averageCadence != nil ? "/min" : ""),

            .init(title: "平均步幅",
                  value: strideValue,
                  unit: detail?.averageStrideLength != nil ? "cm" : ""),

            .init(title: "累计上升",
                  value: RunDetailFormat.int(detail?.elevationAscended),
                  unit: detail?.elevationAscended != nil ? "m" : ""),

            .init(title: "消耗能量",
                  value: RunDetailFormat.int(detail?.activeEnergy),
                  unit: detail?.activeEnergy != nil ? "kcal" : ""),

            .init(title: "平均功率",
                  value: RunDetailFormat.power(detail?.averagePower),
                  unit: detail?.averagePower != nil ? "W" : ""),
        ]

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 18
        ) {
            ForEach(items) { item in
                MetricColumn(item: item)
            }
        }
    }

    private var strideValue: String {
        guard let stride = detail?.averageStrideLength else { return "--" }
        return String(Int(stride * 100))
    }
}

// MARK: - 单个指标列

private struct MetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    var accent: Bool = false
}

private struct MetricColumn: View {
    let item: MetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(item.accent
                                     ? Color(red: 0.29, green: 0.65, blue: 0.92)
                                     : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText())

                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(item.title)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
