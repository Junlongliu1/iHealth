//
//  WeekRunsCard.swift
//  iHealth
//
//  需要 iOS 26+（Liquid Glass API）
//

import SwiftUI

/// 本周跑步卡片
struct WeekRunsCard: View {
    let workouts: [Workout]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本周跑步")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !workouts.isEmpty {
                    Text("\(workouts.count) 次")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 10)

            if workouts.isEmpty {
                Text("本周还没有跑步记录")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(workouts.enumerated()),
                            id: \.element.id) { index, workout in
                        NavigationLink(value: workout) {
                            WorkoutRow(workout: workout)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < workouts.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
