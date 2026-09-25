//
//  ActivityRingsView.swift
//  iHealth
//
//  SwiftUI 包装器，用于承载 UIKit 的 HKActivityRingView。
//  传入 HKActivitySummary 后，自动渲染苹果官方的健身圆环，
//  并支持数据变化时的平滑动画。
//

import SwiftUI
import HealthKit
import HealthKitUI

// MARK: - SwiftUI 包装器
struct ActivityRingsView: UIViewRepresentable {
    /// 要显示的活动摘要数据
    let summary: HKActivitySummary?

    /// 创建一个 HKActivityRingView 实例
    func makeUIView(context: Context) -> HKActivityRingView {
        let ringView = HKActivityRingView()
        ringView.backgroundColor = .clear
        // 设置一个初始的方形尺寸，实际大小由 SwiftUI 的 frame 决定
        ringView.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        return ringView
    }

    /// 当数据变化时更新视图
    func updateUIView(_ uiView: HKActivityRingView, context: Context) {
        // 如果 summary 为 nil，传入 nil 会显示空圆环（或仅显示圆点）
        // animated: true 会让圆环平滑过渡到新值
        uiView.setActivitySummary(summary, animated: true)
    }
}
