//
//  SettingsView.swift
//  iHealth
//

import SwiftUI

private enum SettingsRoute: Hashable {
    case logs
    case about
}

struct SettingsView: View {
    @State private var appearanceStore = AppearanceStore.shared
    @State private var path = NavigationPath()

    private var logLineCount: Int {
        LogManager.shared.lineCount
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                    LazyVStack(spacing: DSLayout.cardSpacing) {
                        appearanceCard
                        developerCard
                    }
                }
                .padding(.horizontal, DSLayout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)

                footerNote
                    .padding(.horizontal, DSLayout.horizontalPadding)
                    .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .logs:  LogViewerView()
                case .about: AboutView()
                }
            }
        }
    }

    // MARK: - 外观

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "paintpalette.fill",
                iconColor: .pink,
                title: "外观"
            )

            Picker("外观", selection: $appearanceStore.mode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 12)
            .onChange(of: appearanceStore.mode) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }

            Text("选择「跟随系统」将自动匹配设备深色模式。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DSLayout.rowHorizontalPadding)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 关于与开发者

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "hammer.fill",
                iconColor: .orange,
                title: "关于与开发者"
            )

            Button { path.append(SettingsRoute.logs) } label: {
                SettingsRow(
                    icon: "text.alignleft",
                    tint: .blue,
                    title: "调试日志",
                    detail: "\(logLineCount) 行"
                )
            }
            .buttonStyle(.plain)

            SettingsRowDivider()

            Button { path.append(SettingsRoute.about) } label: {
                SettingsRow(
                    icon: "info.circle.fill",
                    tint: .indigo,
                    title: "关于 iHealth"
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 脚注

    private var footerNote: some View {
        Text("iHealth 是一个本地健康数据看板，所有数据均保存在本机，不会上传到任何服务器。")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }
}

#Preview {
    SettingsView()
}
