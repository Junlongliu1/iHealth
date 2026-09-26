//
//  AthleteProfileView.swift
//  iHealth
//

import SwiftUI

struct AthleteProfileView: View {
    @State private var profile = AthleteProfileStore.shared

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    basicInfoCard
                    maxHRCard
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

            Toggle("自定义最大心率", isOn: Binding(
                get: { profile.customMaxHR != nil },
                set: { on in
                    profile.customMaxHR = on ? Int(profile.maxHR) : nil
                }
            ))
            .font(.system(size: 15))
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 12)

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

            footerText("当前最大心率：\(Int(profile.maxHR)) bpm（\(profile.maxHRSource)）")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
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

            footerText("阈值心率是你在该运动中全力运动 1 小时能维持的平均心率。留空时按最大心率的默认比例估算。")
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
                Text("留空使用默认值。该运动默认阈值为最大心率的 \(Int(sport.defaultThresholdFraction * 100))%，当前为 \(Int(profile.thresholdHR(for: sport))) bpm。")
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
