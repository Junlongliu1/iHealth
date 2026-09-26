//
//  ReadinessTrendView.swift
//  iHealth
//

import SwiftUI
import Charts

struct ReadinessTrendView: View {
    @State private var store = BodyMetricsStore.shared
    @State private var range: TrendRange = .thirtyDays
    @State private var selectedDate: Date?

    enum TrendRange: String, CaseIterable, Identifiable {
        case sevenDays  = "7 天"
        case thirtyDays = "30 天"
        case sixtyDays  = "60 天"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .sevenDays:  return 7
            case .thirtyDays: return 30
            case .sixtyDays:  return 60
            }
        }
    }

    private var snapshots: [ReadinessSnapshot] {
        let all = store.allSnapshots
        return all.count > range.days ? Array(all.suffix(range.days)) : all
    }

    private var selectedSnapshot: ReadinessSnapshot? {
        guard let selectedDate else { return nil }
        return snapshots.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("范围", selection: $range) {
                    ForEach(TrendRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: range) { _, _ in selectedDate = nil }

                if snapshots.isEmpty {
                    ContentUnavailableView(
                        "暂无趋势数据",
                        systemImage: "chart.xyaxis.line",
                        description: Text("累积几天数据后即可查看趋势")
                    )
                    .padding(.top, 60)
                } else {
                    readinessChart
                    recoveryChart
                    loadChart
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("趋势")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readinessChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("准备度与恢复度")
                    .font(.headline)
                Spacer()
                if let s = selectedSnapshot {
                    Text(dayLabel(s.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Chart {
                ForEach(snapshots) { s in
                    LineMark(
                        x: .value("日期", s.date),
                        y: .value("分数", s.readiness),
                        series: .value("类型", "准备度")
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("日期", s.date),
                        y: .value("分数", s.recovery),
                        series: .value("类型", "恢复度")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }

                if let s = selectedSnapshot {
                    RuleMark(x: .value("选中", s.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .annotation(position: .top, spacing: 4) {
                            selectionCallout(
                                lines: [
                                    ("准备度", "\(Int(s.readiness.rounded()))"),
                                    ("恢复度", "\(Int(s.recovery.rounded()))")
                                ]
                            )
                        }
                }

                RuleMark(y: .value("良好线", 70))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.green.opacity(0.4))
                RuleMark(y: .value("警告线", 50))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.orange.opacity(0.4))
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: $selectedDate)
            .frame(height: 220)

            HStack(spacing: 16) {
                Label("准备度", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
                Label("恢复度", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    private var recoveryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分项评分")
                .font(.headline)

            Chart {
                ForEach(snapshots) { s in
                    LineMark(x: .value("日期", s.date), y: .value("HRV", s.hrvScore), series: .value("类型", "HRV"))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("睡眠", s.sleepScore), series: .value("类型", "睡眠"))
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("RHR", s.rhrScore), series: .value("类型", "RHR"))
                        .foregroundStyle(.pink)
                        .interpolationMethod(.catmullRom)
                }
                if let s = selectedSnapshot {
                    RuleMark(x: .value("选中", s.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)

            HStack(spacing: 16) {
                Label("HRV", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
                Label("睡眠", systemImage: "circle.fill").foregroundStyle(.purple).font(.caption)
                Label("RHR", systemImage: "circle.fill").foregroundStyle(.pink).font(.caption)
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    private var loadChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练负荷")
                .font(.headline)

            Chart {
                ForEach(snapshots) { s in
                    LineMark(x: .value("日期", s.date), y: .value("CTL", s.ctl), series: .value("类型", "CTL"))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("ATL", s.atl), series: .value("类型", "ATL"))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("日期", s.date), y: .value("TSB", s.tsb), series: .value("类型", "TSB"))
                        .foregroundStyle(.green)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("零线", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary.opacity(0.4))
                if let s = selectedSnapshot {
                    RuleMark(x: .value("选中", s.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)

            HStack(spacing: 16) {
                Label("CTL", systemImage: "circle.fill").foregroundStyle(.blue).font(.caption)
                Label("ATL", systemImage: "circle.fill").foregroundStyle(.orange).font(.caption)
                Label("TSB", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal)
    }

    // MARK: - 辅助

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
    }

    private func selectionCallout(lines: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.0) { line in
                HStack(spacing: 6) {
                    Text(line.0)
                        .foregroundStyle(.secondary)
                    Text(line.1)
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            }
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        ReadinessTrendView()
    }
}
