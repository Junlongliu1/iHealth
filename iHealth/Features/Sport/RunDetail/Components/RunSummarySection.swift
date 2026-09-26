//
//  RunSummarySection.swift
//  iHealth
//

import SwiftUI

// MARK: - 顶部浮动玻璃工具栏

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
                .glassEffect(.regular.interactive(), in: .circle)
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
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("actions", in: namespace)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .overlay {
            Text("iHealth")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(.runGradient)
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

            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.75, blue: 0.4).opacity(0.35))
                        .frame(width: 52, height: 52)
                        .blur(radius: 6)

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
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)

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

// MARK: - 九宫格指标（居中）

struct RunMetricsGrid: View {
    let detail: RunDetail?

    var body: some View {
        let rows: [[MetricItem]] = [
            [
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
            ],
            [
                .init(title: "最大心率",
                      value: RunDetailFormat.heartRate(detail?.maxHeartRate),
                      unit: detail?.maxHeartRate != nil ? "bpm" : ""),
                .init(title: "平均步频",
                      value: RunDetailFormat.cadence(detail?.averageCadence),
                      unit: detail?.averageCadence != nil ? "/min" : ""),
                .init(title: "平均步幅",
                      value: strideValue,
                      unit: detail?.averageStrideLength != nil ? "cm" : ""),
            ],
            [
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
        ]

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { colIdx, item in
                        MetricColumn(item: item)
                            .frame(maxWidth: .infinity, alignment: .center)

                        if colIdx < row.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(width: 1, height: 32)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.vertical, 12)

                if rowIdx < rows.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 0.5)
                }
            }
        }
    }

    private var strideValue: String {
        guard let stride = detail?.averageStrideLength else { return "--" }
        return String(Int(stride * 100))
    }
}

// MARK: - 单个指标列（内容居中）

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
        VStack(alignment: .center, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(item.accent
                                     ? AnyShapeStyle(LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.62, blue: 0.2),
                                            Color(red: 1.0, green: 0.42, blue: 0.15)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing))
                                     : AnyShapeStyle(.primary))
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
    }
}
