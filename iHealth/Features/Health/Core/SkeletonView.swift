//
//  SkeletonView.swift
//  iHealth
//
//  通用骨架屏与微光扫过动画。
//  用作加载占位，替代简单的 ProgressView，让首屏过渡更自然。
//

import SwiftUI

// MARK: - 微光扫过层

private struct ShimmerLayer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.white.opacity(0.45), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.6)
            .offset(x: phase * width * 1.6)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - 骨架块

struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .overlay { ShimmerLayer() }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - 健康首页骨架屏

struct HealthTabSkeleton: View {
    var cardCount: Int = 6

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 20) {
            ringsCardSkeleton
                .padding(.top, 24)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(0..<cardCount, id: \.self) { _ in
                    cardSkeleton
                }
            }
        }
    }

    private var ringsCardSkeleton: some View {
        HStack(spacing: 48) {
            SkeletonBlock(cornerRadius: 55)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(cornerRadius: 4).frame(width: 80, height: 12)
                SkeletonBlock(cornerRadius: 5).frame(width: 110, height: 16)
                SkeletonBlock(cornerRadius: 4).frame(width: 80, height: 12)
                SkeletonBlock(cornerRadius: 5).frame(width: 110, height: 16)
                SkeletonBlock(cornerRadius: 4).frame(width: 80, height: 12)
                SkeletonBlock(cornerRadius: 5).frame(width: 110, height: 16)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .cardStyle(radius: 14)
    }

    private var cardSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                SkeletonBlock(cornerRadius: 4).frame(width: 14, height: 14)
                SkeletonBlock(cornerRadius: 4).frame(width: 56, height: 14)
                Spacer(minLength: 0)
            }

            SkeletonBlock(cornerRadius: 6).frame(width: 70, height: 22)

            Spacer(minLength: 4)

            SkeletonBlock(cornerRadius: 6)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .cardStyle(radius: 14)
    }
}

// MARK: - 通用详情页骨架屏

struct MetricDetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(cornerRadius: 4).frame(width: 60, height: 12)
                SkeletonBlock(cornerRadius: 6).frame(width: 110, height: 28)
            }

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(cornerRadius: 4).frame(width: 80, height: 12)
                SkeletonBlock(cornerRadius: 10).frame(height: 140)
            }

            HStack(spacing: 12) {
                SkeletonBlock(cornerRadius: 4).frame(height: 14).frame(maxWidth: .infinity)
                SkeletonBlock(cornerRadius: 4).frame(height: 14).frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - 生命体征骨架屏

struct VitalsSkeleton: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        SkeletonBlock(cornerRadius: 4).frame(width: 16, height: 14)
                        SkeletonBlock(cornerRadius: 4).frame(width: 60, height: 14)
                        Spacer(minLength: 0)
                        SkeletonBlock(cornerRadius: 8).frame(width: 46, height: 18)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SkeletonBlock(cornerRadius: 6).frame(width: 76, height: 28)
                        SkeletonBlock(cornerRadius: 4).frame(width: 40, height: 12)
                        Spacer(minLength: 0)
                    }

                    SkeletonBlock(cornerRadius: 8).frame(width: 140, height: 16)

                    SkeletonBlock(cornerRadius: 10).frame(height: 80)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }
}
