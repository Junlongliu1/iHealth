//
//  AthleteProfileView.swift
//  iHealth
//

import SwiftUI

struct AthleteProfileView: View {
    @State private var profile = AthleteProfileStore.shared
    @State private var isSyncingRHR = false

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    basicInfoCard
                    maxHRCard
                    restingHRCard
                    hrZonesCard
                    thresholdCard
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await syncRestingHR()
        }
    }

    // MARK: - 基本信息

    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "person.fill",
                iconColor: .teal,
                title: "基本信息"
            )

            Stepper(value: $profile.age, in: 10...90) {
                HStack {
                    Text("年龄")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(profile.age) 岁")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(profile.age)))
                        .animation(.snappy(duration: 0.3), value: profile.age)
                }
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 12)

            footerText("用于估算最大心率（220 − 年龄）")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 最大心率

    private var maxHRCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "heart.fill",
                iconColor: .pink,
                title: "最大心率"
            )

            // 大数字 + 来源徽章
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(profile.maxHR))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.pink)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: profile.maxHR))
                    .animation(.snappy(duration: 0.4), value: profile.maxHR)

                Text("bpm")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(profile.maxHRSource)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.pink.opacity(0.12), in: Capsule())
                    .contentTransition(.interpolate)
                    .animation(.snappy(duration: 0.3), value: profile.maxHRSource)
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 10)

            if profile.customMaxHR == nil {
                Text("220 − \(profile.age)（年龄） = \(Int(profile.maxHR))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.horizontal, DSLayout.rowHorizontalPadding)
                    .padding(.bottom, 12)
            }

            SettingsRowDivider()

            Toggle("自定义最大心率", isOn: Binding(
                get: { profile.customMaxHR != nil },
                set: { on in
                    profile.customMaxHR = on ? Int(profile.maxHR) : nil
                }
            ))
            .font(.system(size: 15))
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.vertical, DSLayout.rowVerticalPadding)

            if profile.customMaxHR != nil {
                SettingsRowDivider()

                HStack {
                    Text("最大心率")
                        .font(.system(size: 15))
                    Spacer()
                    TextField("bpm", value: Binding(
                        get: { profile.customMaxHR ?? 0 },
                        set: { profile.customMaxHR = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 80)
                    Text("bpm")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DSLayout.rowHorizontalPadding)
                .padding(.vertical, DSLayout.rowVerticalPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 静息心率

    private var restingHRCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "waveform.path.ecg",
                iconColor: .blue,
                title: "静息心率"
            )

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(profile.restingHR))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: profile.restingHR))
                    .animation(.snappy(duration: 0.4), value: profile.restingHR)

                Text("bpm")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(profile.restingHRSource)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.12), in: Capsule())
                    .contentTransition(.interpolate)
                    .animation(.snappy(duration: 0.3), value: profile.restingHRSource)
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.top, 2)
            .padding(.bottom, 10)

            if profile.customRestingHR == nil, let synced = profile.syncedRestingHR {
                Text("过去 14 天健康数据中位数 \(synced) bpm")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.horizontal, DSLayout.rowHorizontalPadding)
                    .padding(.bottom, 12)
            } else if profile.customRestingHR == nil, profile.syncedRestingHR == nil {
                HStack(spacing: 6) {
                    if isSyncingRHR {
                        ProgressView().scaleEffect(0.7)
                    }
                    Text(isSyncingRHR ? "正在同步健康数据…" : "未读取到健康数据，使用默认值 60 bpm")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .padding(.horizontal, DSLayout.rowHorizontalPadding)
                .padding(.bottom, 12)
            }

            SettingsRowDivider()

            Toggle("自定义静息心率", isOn: Binding(
                get: { profile.customRestingHR != nil },
                set: { on in
                    profile.customRestingHR = on ? Int(profile.restingHR) : nil
                }
            ))
            .font(.system(size: 15))
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.vertical, DSLayout.rowVerticalPadding)

            if profile.customRestingHR != nil {
                SettingsRowDivider()

                HStack {
                    Text("静息心率")
                        .font(.system(size: 15))
                    Spacer()
                    TextField("bpm", value: Binding(
                        get: { profile.customRestingHR ?? 0 },
                        set: { profile.customRestingHR = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 80)
                    Text("bpm")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DSLayout.rowHorizontalPadding)
                .padding(.vertical, DSLayout.rowVerticalPadding)
            }

            footerText("静息心率用于 Karvonen 公式计算训练心率区间。健康数据自动取最近 14 天的中位数。")
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 心率区间（Karvonen）

    private var hrZonesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "chart.bar.fill",
                iconColor: .orange,
                title: "心率区间"
            )

            // 心率储备展示
            HStack(spacing: 6) {
                Text("心率储备")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(profile.maxHR)) − \(Int(profile.restingHR)) = \(Int(profile.heartRateReserve)) bpm")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: profile.heartRateReserve)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(HRZone.all) { zone in
                    hrZoneRow(zone)
                }
            }

            footerText("基于 Karvonen 公式：目标心率 = 静息心率 + 心率储备 × 百分比。比最大心率百分比法更适合个体差异。")
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    private func hrZoneRow(_ zone: HRZone) -> some View {
        let r = zone.range(
            maxHR: profile.maxHR,
            restingHR: profile.restingHR
        )

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(zone.color)
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Z\(zone.id) · \(zone.name)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("\(Int(zone.lowerFraction * 100))–\(Int(zone.upperFraction * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(zone.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(zone.color.opacity(0.12), in: Capsule())
                }
                Text(zone.purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(r.low)–\(r.high)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(zone.color)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: r.low)
                Text("bpm")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(zone.name)，\(zone.purpose)")
        .accessibilityValue("\(r.low) 到 \(r.high) bpm")
    }

    // MARK: - 阈值心率

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "figure.run",
                iconColor: .orange,
                title: "各运动阈值心率"
            )

            ForEach(Array(SportType.allCases.enumerated()), id: \.element) { index, sport in
                if index > 0 {
                    SettingsRowDivider()
                }

                NavigationLink {
                    SportThresholdView(sport: sport)
                } label: {
                    thresholdRow(sport: sport)
                }
                .buttonStyle(.plain)
            }

            footerText("阈值心率是你在该运动中全力运动 1 小时能维持的平均心率，按 Karvonen 公式估算。留空使用默认系数。")
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    private func thresholdRow(sport: SportType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sport.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(
                    Color.orange.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Text(sport.displayName)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("\(Int(profile.thresholdHR(for: sport))) bpm")
                .font(.system(size: 14))
                .foregroundStyle(profile.isCustomThreshold(for: sport) ? .primary : .secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.35), value: profile.thresholdHR(for: sport))

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.vertical, DSLayout.rowVerticalPadding)
        .contentShape(Rectangle())
    }

    // MARK: - 辅助

    private func footerText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 14)
    }

    private func syncRestingHR() async {
        isSyncingRHR = true
        defer { isSyncingRHR = false }

        if let median = await HealthKitManager.shared.fetchRestingHRMedian(days: 14) {
            profile.syncedRestingHR = Int(median.rounded())
        }
    }
}

// MARK: - 单项阈值编辑

struct SportThresholdView: View {
    let sport: SportType
    @State private var profile = AthleteProfileStore.shared
    @State private var text: String = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("阈值心率")
                    Spacer()
                    TextField("bpm", text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 80)
                        .onChange(of: text) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if filtered != newValue { text = filtered }
                        }
                    Text("bpm").foregroundStyle(.secondary)
                }
            } header: {
                Text("自定义阈值")
            } footer: {
                Text("留空使用默认值。默认系数为 \(Int(sport.defaultThresholdFraction * 100))% HRR，当前默认估算为 \(Int(profile.restingHR + profile.heartRateReserve * sport.defaultThresholdFraction)) bpm。")
            }

            Section {
                Button("使用默认值") {
                    text = ""
                    profile.setThreshold(nil, for: sport)
                }
                .foregroundStyle(.red)

                Button("保存") {
                    profile.setThreshold(Int(text), for: sport)
                }
                .disabled(text.isEmpty)
            }
        }
        .navigationTitle(sport.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if profile.isCustomThreshold(for: sport) {
                text = "\(Int(profile.thresholdHR(for: sport)))"
            } else {
                text = ""
            }
        }
    }
}

#Preview {
    NavigationStack {
        AthleteProfileView()
    }
}
