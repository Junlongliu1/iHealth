//
//  HealthCardEditorView.swift
//  iHealth
//
//  编辑健康首页卡片：拖拽排序、显示 / 隐藏。
//

import SwiftUI

struct HealthCardEditorView: View {
    @State private var prefs = HealthCardPreferences.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(prefs.order) { kind in
                        row(for: kind)
                    }
                    .onMove { from, to in
                        prefs.order.move(fromOffsets: from, toOffset: to)
                    }
                } footer: {
                    Text("拖动调整顺序，点击右侧图标可显示 / 隐藏卡片。活动圆环固定显示。")
                        .font(.footnote)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("编辑卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置", role: .destructive) {
                        withAnimation(.smooth(duration: 0.2)) { prefs.reset() }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 单行

    private func row(for kind: HealthCardKind) -> some View {
        let visible = prefs.isVisible(kind)

        return HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(visible ? kind.iconColor : Color.secondary.opacity(0.5))
                .frame(width: 24)

            Text(kind.title)
                .font(.system(size: 15))
                .foregroundStyle(visible ? Color.primary : Color.secondary)

            Spacer(minLength: 8)

            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    prefs.setVisible(!visible, for: kind)
                }
            } label: {
                Image(systemName: visible ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(visible ? kind.iconColor : Color.secondary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
