//  BodyStateViews.swift
//  iHealth
//
//  职责：身体 Tab 的四种"非内容"状态视图。
//
//  · LoadingStateView —— 首屏加载（全屏居中 loader + 文案）
//  · RefreshOverlay   —— 下拉刷新遮罩（磨砂 + 玻璃卡 + loader）
//  · ErrorStateView   —— 读取失败（图标 + 提示 + 授权指引）
//  · EmptyStateView   —— 无数据（图标 + 授权提示）
//
//  统一在此收敛，BodyTabView 按状态挑选。

import SwiftUI

// MARK: - 首屏加载

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            PulsingHeartLoader()

            VStack(spacing: 6) {
                Text("正在读取健康数据")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("这可能需要几秒钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - 下拉刷新遮罩

struct RefreshOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                PulsingHeartLoader(size: 56)

                VStack(spacing: 4) {
                    Text("正在同步")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("更新最新健康数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }
    }
}

// MARK: - 错误

struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.red.gradient)
                .symbolEffect(.pulse.byLayer)

            Text("无法读取数据")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 空数据

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.blue.gradient)
                .symbolEffect(.variableColor.iterative)

            Text("暂无数据")
                .font(.headline)

            Text("请先在健康 App 中授权数据访问")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
