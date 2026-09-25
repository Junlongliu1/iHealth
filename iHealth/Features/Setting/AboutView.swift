//
//  AboutView.swift
//  iHealth
//

import SwiftUI
import UIKit

struct AboutView: View {
    // MARK: - 版本信息

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) iHealth"
    }

    private var systemVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// 尝试读取真实的 AppIcon
    private var appIconImage: UIImage? {
        if let icon = UIImage(named: "AppIcon") { return icon }
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last {
            return UIImage(named: name)
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    heroCard
                    introCard
                    infoCard
                }
            }
            .padding(.horizontal, DSLayout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)

            copyrightNote
                .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("关于")
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 12) {
            Group {
                if let icon = appIconImage {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.28, blue: 0.36),
                                    Color(red: 0.78, green: 0.16, blue: 0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "heart.fill")
                                .font(.system(size: 38))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            VStack(spacing: 4) {
                Text("iHealth")
                    .font(.title2.bold())

                Text("版本 \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .cardGlass()
    }

    // MARK: - 简介

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "text.alignleft",
                iconColor: .blue,
                title: "简介"
            )

            Text("iHealth 是一款轻量的健康数据看板，聚合 Apple Watch 与 iPhone 的活动、锻炼与站立数据。所有健康信息均在设备本地读取与展示，不会上传到任何服务器。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DSLayout.rowHorizontalPadding)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 信息

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCardHeader(
                icon: "info.circle",
                iconColor: .blue,
                title: "信息"
            )

            InfoRow(label: "版本",   value: appVersion)
            divider
            InfoRow(label: "构建号", value: buildNumber)
            divider
            InfoRow(label: "系统",   value: systemVersionString)
            divider
            InfoRow(label: "开发者", value: "iHealth")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
    }

    // MARK: - 版权

    private var copyrightNote: some View {
        Text(copyright)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}

// MARK: - 信息行

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.vertical, DSLayout.rowVerticalPadding)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
