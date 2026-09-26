//
//  SplitsTableCard.swift
//  iHealth
//

import SwiftUI

struct SplitsTableCard: View {
    let splits: [KilometerSplit]

    private var fastestIndex: Int? {
        splits
            .filter(\.isFullKilometer)
            .min(by: { ($0.pace ?? .infinity) < ($1.pace ?? .infinity) })?
            .index
    }

    private let colIndex:   CGFloat = 46
    private let colPace:    CGFloat = 70
    private let colHR:      CGFloat = 50
    private let colStride:  CGFloat = 50
    private let colCadence: CGFloat = 50
    private let colPower:   CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("公里分段")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                if let idx = fastestIndex {
                    Text("第 \(idx) 段最快")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                headerCell("序号", width: colIndex, alignment: .leading)
                headerCell("配速", width: colPace)
                headerCell("心率", width: colHR)
                headerCell("步幅", width: colStride)
                headerCell("步频", width: colCadence)
                headerCell("功率", width: colPower)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                    rowView(
                        split: split,
                        isFastest: split.index == fastestIndex,
                        isOdd: idx % 2 == 1
                    )
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        }
    }

    private func headerCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .trailing
    ) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(width: width, alignment: alignment)
    }

    private func rowView(
        split: KilometerSplit,
        isFastest: Bool,
        isOdd: Bool
    ) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(split.index)")
                    .font(.system(size: 14, weight: isFastest ? .semibold : .regular))
                    .foregroundStyle(isFastest ? .primary : .secondary)
                    .monospacedDigit()
                    .frame(minWidth: 16, alignment: .leading)

                if isFastest {
                    Text("最快")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.runGradient))
                }
            }
            .frame(width: colIndex, alignment: .leading)

            valueCell(split.formattedPace,        width: colPace, primary: true)
            valueCell(split.formattedHeartRate,   width: colHR)
            valueCell(split.formattedStride,      width: colStride)
            valueCell(split.formattedCadence,     width: colCadence)
            valueCell(split.formattedPower,       width: colPower)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            isFastest
                ? Color.orange.opacity(0.07)
                : (isOdd ? Color.primary.opacity(0.025) : Color.clear)
        )
    }

    private func valueCell(
        _ text: String,
        width: CGFloat,
        primary: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 14, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? .primary : .secondary)
            .monospacedDigit()
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, 4)
    }
}
