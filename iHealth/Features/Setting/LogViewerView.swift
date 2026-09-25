// LogViewerView.swift
import SwiftUI

// MARK: - LogLevel 的 UI 扩展

extension LogLevel {
    var color: Color {
        switch self {
        case .error:   return .red
        case .warning: return .orange
        case .debug:   return Color(uiColor: .tertiaryLabel)
        case .info:    return .primary
        }
    }

    var hasWarningBackground: Bool {
        self == .error || self == .warning
    }

    var backgroundTint: Color {
        switch self {
        case .error:   return Color.red.opacity(0.08)
        case .warning: return Color.orange.opacity(0.06)
        default:       return .clear
        }
    }
}

// MARK: - 视图

struct LogViewerView: View {
    @Bindable private var logManager = LogManager.shared
    @State private var autoScroll = true
    @State private var showCopySuccess = false
    @State private var showConfirmClear = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSLayout.cardSpacing) {
                    controlCard
                        .id("logTop")
                    logCard
                }
                .padding(.horizontal, DSLayout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: logManager.entries.count) { _, newCount in
                if newCount == 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        withAnimation(.smooth(duration: 0.25)) {
                            proxy.scrollTo("logTop", anchor: .top)
                        }
                    }
                } else if autoScroll {
                    withAnimation(.smooth(duration: 0.12)) {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
        .navigationTitle("日志面板")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .onAppear {
            logManager.loadTodayLog()
        }
        .overlay(alignment: .top) {
            if showCopySuccess {
                ToastView(message: "已复制到剪贴板")
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("清空日志？", isPresented: $showConfirmClear) {
            Button("清空", role: .destructive) {
                withAnimation(.smooth(duration: 0.2)) {
                    logManager.clearTodayLog()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除今天的所有日志内容，归档文件不受影响。")
        }
    }

    // MARK: - 控制卡

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "slider.horizontal.3", title: "控制")

            HStack(spacing: 6) {
                toggleButton(
                    isOn: $logManager.consoleEnabled,
                    iconOn: "terminal.fill",
                    iconOff: "terminal",
                    label: "控制台"
                )

                toggleButton(
                    isOn: $logManager.fileWriteEnabled,
                    iconOn: "doc.text.fill",
                    iconOff: "doc.text",
                    label: "写文件"
                )

                toggleButton(
                    isOn: $autoScroll,
                    iconOn: "arrow.down.circle.fill",
                    iconOff: "arrow.down.circle",
                    label: "滚动"
                )

                Spacer(minLength: 4)

                lineCountBadge
            }
            .padding(.horizontal, DSLayout.rowHorizontalPadding)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    private var lineCountBadge: some View {
        HStack(spacing: 3) {
            Text("\(logManager.lineCount)")
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("行")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func toggleButton(
        isOn: Binding<Bool>,
        iconOn: String,
        iconOff: String,
        label: String
    ) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? iconOn : iconOff)
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))

                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isOn.wrappedValue ? .accentColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isOn.wrappedValue
                        ? Color.accentColor.opacity(0.16)
                        : Color.secondary.opacity(0.12)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 日志卡

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(icon: "text.alignleft", title: "运行日志")

            if logManager.entries.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logManager.entries) { entry in
                        logLineView(entry: entry)
                    }
                }
                .padding(.vertical, 6)
                .id("logBottom")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardGlass()
    }

    private func cardHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()
        }
        .padding(.horizontal, DSLayout.rowHorizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func logLineView(entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(entry.lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.45))
                .frame(width: 30, alignment: .trailing)
                .padding(.top, 2)

            if let timestamp = entry.timestamp {
                Text(timestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.75))
                    .monospacedDigit()
                    .frame(width: 78, alignment: .leading)
                    .padding(.top, 1)
            }

            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(entry.level.color)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 1)

            Text(entry.rest)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(background(for: entry))
    }

    private func background(for entry: LogEntry) -> Color {
        entry.id % 2 == 0 ? Color.clear : Color.primary.opacity(0.04)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))

            Text("暂无日志")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            Text("当应用运行时，日志将显示在这里")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 底部操作栏

    private var bottomBar: some View {
        HStack(spacing: 10) {
            floatingButton(icon: "doc.on.doc", label: "复制", tint: .primary) {
                copyLogs()
            }

            floatingButton(icon: "arrow.clockwise", label: "刷新", tint: .primary) {
                logManager.loadTodayLog()
            }

            floatingButton(icon: "trash", label: "清空", tint: .red) {
                showConfirmClear = true
            }
        }
        .padding(.horizontal, DSLayout.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// 原生液态玻璃按钮：使用系统 `.glass` ButtonStyle
    private func floatingButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
    }

    // MARK: - 复制

    private func copyLogs() {
        guard !logManager.entries.isEmpty else {
            AppLogWarn("[LogViewer] 尝试复制空日志，忽略")
            return
        }

        UIPasteboard.general.string = logManager.entries
            .map(\.raw)
            .joined(separator: "\n")

        withAnimation(.smooth(duration: 0.2)) {
            showCopySuccess = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth(duration: 0.2)) {
                showCopySuccess = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
