//
//  AthleteProfileView.swift
//  iHealth
//

import SwiftUI

struct AthleteProfileView: View {
    @State private var profile = AthleteProfileStore.shared

    var body: some View {
        Form {
            Section {
                Stepper(value: $profile.age, in: 10...90) {
                    HStack {
                        Text("年龄")
                        Spacer()
                        Text("\(profile.age) 岁")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("基本信息")
            } footer: {
                Text("用于估算最大心率")
            }

            Section {
                Toggle("自定义最大心率", isOn: Binding(
                    get: { profile.customMaxHR != nil },
                    set: { on in
                        profile.customMaxHR = on ? Int(profile.maxHR) : nil
                    }
                ))

                if profile.customMaxHR != nil {
                    HStack {
                        Text("最大心率")
                        Spacer()
                        TextField("bpm", value: Binding(
                            get: { profile.customMaxHR ?? 0 },
                            set: { profile.customMaxHR = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        Text("bpm").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("最大心率")
            } footer: {
                Text("当前最大心率：\(Int(profile.maxHR)) bpm（\(profile.maxHRSource)）")
            }

            Section {
                ForEach(SportType.allCases) { sport in
                    NavigationLink {
                        SportThresholdView(sport: sport)
                    } label: {
                        HStack {
                            Label(sport.displayName, systemImage: sport.icon)
                            Spacer()
                            Text("\(Int(profile.thresholdHR(for: sport))) bpm")
                                .foregroundStyle(profile.isCustomThreshold(for: sport) ? .primary : .secondary)
                                .font(.subheadline)
                        }
                    }
                }
            } header: {
                Text("各运动阈值心率")
            } footer: {
                Text("阈值心率是你在该运动中全力运动 1 小时能维持的平均心率。留空时按最大心率的默认比例估算。")
            }
        }
        .navigationTitle("个人资料")
        .navigationBarTitleDisplayMode(.inline)
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
