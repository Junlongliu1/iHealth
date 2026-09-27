//
//  CacheManagerView.swift
//  iHealth
//
//  缓存管理：展示本地缓存占用，支持分项清理与一键清理。
//  · 日志文件    —— 今日以外的归档日志可单独清理
//  · 健康数据缓存 —— daily_metrics.json + sync_meta.json
//  · 内存缓存    —— 生命体征等运行时缓存
//
//  入口：设置 → 关于与开发者 → 缓存管理
//

import SwiftUI

struct CacheManagerView: View {

    // MARK: - 状态

    @State private var logBytes: Int = 0
    @State private var metricsDataBytes: Int = 0
    @State private var metricsMetaBytes: Int = 0

    @State private var isLoading = true
    @State private var isWorking = false
    @State private var toast: String?

    @State private var showClearLogConfirm = false
    @State private var showClearMetricsConfirm = false

    // MARK: - 派生

    private var metricsBytes: Int { metricsDataBytes + metricsMetaBytes }
    private var totalBytes: Int { logBytes + metricsBytes }

    // MARK: - Body

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: DSLayout.cardSpacing) {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    overviewCard
                    logCard
                    metricsCard
                    memoryCard
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
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .overlay(alignment: .top) {
            if let toast {
                ToastView(message: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("清理归档日志？", isPresented: $showClearLogConfirm) {
            Button("清理", role: .destructive) {
                Task { await clearArchives() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除今日以外的日志文件，当前日志不受影响。")
        }
        .alert("清空健康数据缓存？", isPresented: $showClearMetricsConfirm) {
            Button("清空", role: .destructive) {
                Task { await clearMetrics() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除本地缓存的每日健康指标。下次进入「身体」页面会重新从 HealthKit 同步。")
        }
    }

    // MARK: - 概览卡片

    private var overviewCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 26))
                .foregroundStyle(.indigo.gradient)
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.5))

            Text(formatBytes(totalBytes))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.45), value: totalBytes)

            Text("本地缓存占用")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .cardGlass()
        .overlay(alignment: .topTrailing) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(12)
            }
        }
    }

    // MARK: - 日志卡片

    private var logCard: some View {
        cacheRow(
            icon: "doc.text.fill",
            tint: .blue,
            title: "日志文件",
            subtitle: logBytes == 0 ? "暂无日志" : formatBytes(logBytes),
            actionTitle: "清理归档",
            actionDisabled: logBytes == 0 || isWorking
        ) {
            showClearLogConfirm = true
        }
    }

    // MARK: - 数据缓存卡片

    private var metricsCard: some View {
        cacheRow(
            icon: "chart.bar.doc.horizontal.fill",
            tint: .green,
            title: "健康数据缓存",
            subtitle: metricsBytes == 0 ? "暂无缓存" : formatBytes(metricsBytes),
            actionTitle: "清空",
            actionDisabled: metricsBytes == 0 || isWorking
        ) {
            showClearMetricsConfirm = true
        }
    }

    // MARK: - 内存缓存卡片

    private var memoryCard: some View {
        cacheRow(
            icon: "memorychip.fill",
            tint: .orange,
            title: "内存缓存",
            subtitle: "生命体征 · 计算结果",
            actionTitle: "清理",
            actionDisabled: isWorking
        ) {
            Task { await clearMemory() }
        }
    }

    // MARK: - 通用行

    private func cacheRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        actionTitle: String,
        actionDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    tint.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.4), value: subtitle)
            }

            Spacer(minLength: 8)

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(actionDisabled ? Color.secondary.opacity(0.5) : .red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(
                            actionDisabled
                                ? Color.secondary.opacity(0.08)
                                : Color.red.opacity(0.12)
                        )
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(actionDisabled)
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    // MARK: - 底部说明

    private var footerNote: some View {
        Text("清理缓存不会影响你的健康数据本身。健康数据缓存会在下次打开应用时自动重建；日志归档删除后无法恢复。")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.top, 4)
    }

    // MARK: - 数据加载

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let logsValue = LogManager.shared.totalLogBytes()
        let sizes = MetricsCache.shared.fileSizes()

        logBytes = await logsValue
        metricsDataBytes = sizes.data
        metricsMetaBytes = sizes.meta
    }

    // MARK: - 清理操作

    private func clearArchives() async {
        isWorking = true
        defer { isWorking = false }

        let removed = await LogManager.shared.clearArchives()
        await refresh()
        showToast(removed > 0 ? "已删除 \(removed) 个归档日志" : "没有可清理的归档")
    }

    private func clearMetrics() async {
        isWorking = true
        defer { isWorking = false }

        MetricsCache.shared.clear()
        // 同步清掉由此派生出的内存缓存，下次访问会重新计算
        VitalsCalculator.shared.invalidate()

        await refresh()
        showToast("健康数据缓存已清空")
    }

    private func clearMemory() async {
        isWorking = true
        defer { isWorking = false }

        VitalsCalculator.shared.invalidate()
        showToast("内存缓存已清理")
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        withAnimation(.smooth(duration: 0.2)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.smooth(duration: 0.2)) { toast = nil }
        }
    }

    // MARK: - 格式化

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB", mb)
    }
}

#Preview {
    NavigationStack {
        CacheManagerView()
    }
}
