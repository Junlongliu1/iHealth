//
//  BodyTabView.swift
//  iHealth
//
//  职责：身体 Tab 的顶层容器。
//
//  · 根据 store 状态在 4 种状态视图之间切换
//  · 编排 5 张卡片的堆叠顺序和 cardReveal 级联延迟
//  · 持有卡片间共享的 @State
//  · 管理卡片弹出的 sheet
//  · 协调首屏加载（≥ 0.5s）和下拉刷新的最短时长
//
//  不实现卡片内容，只负责"放哪里、何时出现"。
//

import SwiftUI

struct BodyTabView: View {
    @State private var store = BodyMetricsStore.shared
    @State private var activeExplanation: MetricExplanation?
    @State private var showSubScores = false
    @State private var showTrainingLoad = false
    @State private var selectedSport: SportType = .running

    @State private var revealed = false
    @State private var isInitialLoading = true
    @State private var isRefreshing = false

    /// 中间加载动画的最短持续时间
    private let minimumLoadingSeconds: TimeInterval = 0.5

    var body: some View {
        Group {
            if isInitialLoading {
                LoadingStateView()
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .scale(scale: 1.04))
                        )
                    )
            } else if let error = store.loadError, store.history.isEmpty {
                ErrorStateView(message: error)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let s = store.todaySnapshot {
                content(s)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                EmptyStateView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.45), value: isInitialLoading)
        .animation(.smooth(duration: 0.45), value: store.todaySnapshot?.date)
        .animation(.smooth(duration: 0.45), value: store.loadError)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: isRefreshing)
        .overlay {
            if isRefreshing {
                RefreshOverlay()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal:   .opacity.combined(with: .scale(scale: 1.06))
                        )
                    )
            }
        }
        .environment(\.cardCornerRadius, 16)
        .environment(\.cardPadding, 16)
        .environment(\.cardSpacing, 16)
        .navigationTitle("身体")
        .navigationBarTitleDisplayMode(.large)
        .task {
            let start = Date()
            await store.load()
            await ensureMinimumDuration(since: start)

            withAnimation(.smooth(duration: 0.45)) {
                isInitialLoading = false
            }
            // 首屏入场动画：只播一次
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                revealed = true
            }
        }
        .sheet(item: $activeExplanation) { explanation in
            MetricExplanationView(explanation: explanation)
        }
        .sheet(isPresented: $showSubScores) {
            SubScoresView(snapshot: store.todaySnapshot)
        }
        .sheet(isPresented: $showTrainingLoad) {
            TrainingLoadDetailView(
                snapshot: store.todaySnapshot,
                previousSnapshot: store.allSnapshots.dropLast().last,
                todayTSS: store.history.last?.tss ?? 0
            )
        }
    }

    // MARK: - 主内容

    private func content(_ s: ReadinessSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                TrainingLoadCard(
                    snapshot: s,
                    activeExplanation: $activeExplanation,
                    showDetail: $showTrainingLoad
                )
                .cardReveal(revealed, delay: 0)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ReadinessCard(
                        snapshot: s,
                        activeExplanation: $activeExplanation,
                        showDetail: $showSubScores
                    )
                    .cardReveal(revealed, delay: 0.06)

                    RecoveryCard(
                        snapshot: s,
                        activeExplanation: $activeExplanation
                    )
                    .cardReveal(revealed, delay: 0.12)
                }

                SubScoresCard(
                    snapshot: s,
                    activeExplanation: $activeExplanation,
                    showDetail: $showSubScores
                )
                .cardReveal(revealed, delay: 0.18)

                SportAdviceCard(
                    snapshot: s,
                    selectedSport: $selectedSport
                )
                .cardReveal(revealed, delay: 0.24)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await performRefresh()
        }
    }

    // MARK: - 刷新

    private func performRefresh() async {
        let start = Date()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            isRefreshing = true
        }

        await store.refresh()
        await ensureMinimumDuration(since: start)

        withAnimation(.smooth(duration: 0.32)) {
            isRefreshing = false
        }

        // 下拉刷新后重播一次卡片入场（这是用户主动操作，保留）
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            revealed = false
        }
        try? await Task.sleep(for: .milliseconds(60))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            revealed = true
        }
    }

    // MARK: - 工具

    private func ensureMinimumDuration(since start: Date) async {
        let elapsed = Date().timeIntervalSince(start)
        let remaining = minimumLoadingSeconds - elapsed
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }
}

#Preview {
    NavigationStack {
        BodyTabView()
    }
}
