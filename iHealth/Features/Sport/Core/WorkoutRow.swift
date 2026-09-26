//
//  WorkoutRow.swift
//  iHealth
//

import SwiftUI

/// 单条运动记录行
struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(workout.type.color.opacity(0.15))
                Image(systemName: workout.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(workout.type.color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.type.rawValue)
                    .font(.body.weight(.medium))

                HStack(spacing: 6) {
                    Text(workout.startDate, format: .dateTime.hour().minute())
                    if let calories = workout.formattedCalories {
                        Text("·")
                        Text(calories)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.formattedDuration)
                    .font(.subheadline.weight(.semibold))
                if let distance = workout.formattedDistance {
                    Text(distance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
