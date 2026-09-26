//
//  MetricsCache.swift
//  iHealth
//

import Foundation

/// 每日指标的本地缓存，使用 JSON 文件持久化。
/// 读同步（数据量小），写异步（避免阻塞主线程）。
nonisolated final class MetricsCache: @unchecked Sendable {

    static let shared = MetricsCache()

    private let fileURL: URL
    private let metaURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iHealth", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("daily_metrics.json")
        self.metaURL = base.appendingPathComponent("sync_meta.json")
    }

    // MARK: - 每日指标

    func loadMetrics() -> [DailyMetrics] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([DailyMetrics].self, from: data)) ?? []
    }

    func saveMetrics(_ metrics: [DailyMetrics]) {
        let url = fileURL
        let encoder = self.encoder
        Task.detached(priority: .background) {
            guard let data = try? encoder.encode(metrics) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 同步时间戳

    func loadLastSync() -> Date? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return (try? decoder.decode(SyncMeta.self, from: data))?.lastSyncDate
    }

    func saveLastSync(_ date: Date) {
        let url = metaURL
        let encoder = self.encoder
        let meta = SyncMeta(lastSyncDate: date)
        Task.detached(priority: .background) {
            guard let data = try? encoder.encode(meta) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 清理

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: metaURL)
    }
}

// MARK: - 内部类型

private nonisolated struct SyncMeta: Codable {
    var lastSyncDate: Date
}
