//
//  PBCard.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI

/// 个人最好成绩卡片
struct PBCard: View {
    let bests: [PersonalBest]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("个人最好成绩")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("分段最快")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("PB")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.runGradient)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                ForEach(Array(bests.enumerated()), id: \.element.id) { index, pb in
                    pbRow(pb)
                    if index < bests.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func pbRow(_ pb: PersonalBest) -> some View {
        HStack(spacing: 0) {
            Text(pb.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 52, alignment: .leading)

            if let time = pb.time {
                Text(formatTime(time))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.runGradient)

                Spacer(minLength: 8)

                if let date = pb.date {
                    Text(formatDate(date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("——")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Text("暂无记录")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 9)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        PBCard.dateFormatter.string(from: date)
    }
}
