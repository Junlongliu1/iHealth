// LogManager.swift
import Foundation
import Observation

// MARK: - 日志等级
enum LogLevel: String {
    case error   = "ERROR"
    case warning = "WARN"
    case debug   = "DEBUG"
    case info    = "INFO"

    var tag: String { "[\(rawValue)]" }

    static func detect(in line: String) -> LogLevel {
        if line.contains("[ERROR]") { return .error }
        if line.contains("[WARN]")  { return .warning }
        if line.contains("[DEBUG]") { return .debug }
        return .info
    }
}

struct LogEntry: Identifiable {
    let id: Int
    let timestamp: String?
    let rest: String
    let level: LogLevel
    let raw: String
    var lineNumber: Int { id + 1 }
}

// MARK: - 便捷日志函数
nonisolated func AppLogInfo(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
    dispatchLog(message, level: .info, file: file, function: function, line: line)
}
nonisolated func AppLogWarn(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
    dispatchLog(message, level: .warning, file: file, function: function, line: line)
}
nonisolated func AppLogError(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
    dispatchLog(message, level: .error, file: file, function: function, line: line)
}
nonisolated func AppLogDebug(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
    dispatchLog(message, level: .debug, file: file, function: function, line: line)
}

nonisolated private func dispatchLog(_ message: Any, level: LogLevel, file: String, function: String, line: Int) {
    let text = String(describing: message)
    let f = file, fn = function, l = line

    if Thread.isMainThread {
        MainActor.assumeIsolated {
            emitLog(text, level: level, file: f, function: fn, line: l)
        }
    } else {
        Task { @MainActor in
            emitLog(text, level: level, file: f, function: fn, line: l)
        }
    }
}

@MainActor
private func emitLog(_ message: Any, level: LogLevel, file: String, function: String, line: Int) {
    let fileName = (file as NSString).lastPathComponent
    let ts = LogTimestamp.now()
    let formatted = "[\(ts)] \(level.tag) [\(fileName):\(line)] \(function) -> \(message)"

    let manager = LogManager.shared
    if manager.consoleEnabled { print(formatted) }
    manager.write(formatted)
}

// MARK: - 时间戳格式化
nonisolated enum LogTimestamp {
    static func now() -> String {
        let c = Calendar.current.dateComponents(
            [.hour, .minute, .second, .nanosecond], from: Date()
        )
        let ms = (c.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d",
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }

    static func dayOnly(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func archiveName(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        return String(format: "%04d-%02d-%02d_%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

// MARK: - Manager
@MainActor
@Observable
final class LogManager {
    static let shared = LogManager()

    private(set) var entries: [LogEntry] = []
    var lineCount: Int { entries.count }

    // 控制台：DEBUG 打开，Release 关闭
    var consoleEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // 写文件：默认打开（Release 也写）
    var fileWriteEnabled: Bool = true

    /// ★ 内存中最多保留的日志行数
    private let maxEntriesInMemory = 1500

    @ObservationIgnored private let writer = LogFileWriter()
    @ObservationIgnored private var pendingWrites: [String] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private init() {
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await writer.setup()
        let content = await writer.readTail(maxLines: maxEntriesInMemory)
        entries = Self.parseLines(content)
    }

    func write(_ message: String) {
        guard fileWriteEnabled else { return }

        entries.append(Self.parse(message, index: entries.count))

        // ★ 超过内存上限，丢弃最早的
        if entries.count > maxEntriesInMemory {
            entries.removeFirst(entries.count - maxEntriesInMemory)
            // 重新编号，保证 lineNumber 连续
            for i in 0..<entries.count {
                let e = entries[i]
                entries[i] = LogEntry(id: i, timestamp: e.timestamp, rest: e.rest, level: e.level, raw: e.raw)
            }
        }

        pendingWrites.append(message)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            await self?.flushNow()
        }
    }

    private func flushNow() async {
        flushTask = nil
        let batch = pendingWrites
        pendingWrites = []
        guard !batch.isEmpty else { return }
        await writer.appendBatch(batch)
    }

    func loadTodayLog() {
        Task {
            let content = await writer.readTail(maxLines: maxEntriesInMemory)
            entries = Self.parseLines(content)
        }
    }

    func clearTodayLog() {
        entries = []
        pendingWrites = []
        flushTask?.cancel()
        flushTask = nil
        Task {
            await writer.clear()
            AppLogInfo("=== 日志已清空 ===")
        }
    }
    
    /// Logs 目录总占用（字节）
    func totalLogBytes() async -> Int {
        await writer.totalBytes()
    }

    /// 清理归档日志，返回清理数量（当前日志不受影响）
    @discardableResult
    func clearArchives() async -> Int {
        await writer.clearArchives()
    }

    private static func parseLines(_ content: String) -> [LogEntry] {
        guard !content.isEmpty else { return [] }
        var parts = content.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts.enumerated().map { parse($0.element, index: $0.offset) }
    }

    private static func parse(_ line: String, index: Int) -> LogEntry {
        let (timestamp, rest) = splitTimestamp(line)
        let level = LogLevel.detect(in: line)
        let cleaned = stripLevelTag(from: rest, level: level)
        return LogEntry(id: index, timestamp: timestamp, rest: cleaned, level: level, raw: line)
    }

    private static func stripLevelTag(from text: String, level: LogLevel) -> String {
        let tag = level.tag
        guard text.hasPrefix(tag) else { return text }
        return String(text.dropFirst(tag.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func splitTimestamp(_ line: String) -> (String?, String) {
        guard line.hasPrefix("[") else { return (nil, line) }
        guard let end = line.firstIndex(of: "]") else { return (nil, line) }
        let inside = String(line[line.index(after: line.startIndex)..<end])
        guard inside.contains(":") else { return (nil, line) }
        let rest = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        return (inside, rest)
    }
}

// MARK: - 磁盘 I/O actor
actor LogFileWriter {
    private var fileSize: UInt64 = 0
    private var fileURL: URL?

    private let fileManager = FileManager.default
    private let maxFileSizeBytes: UInt64 = 10 * 1024 * 1024
    private let maxRetentionDays: Int = 7

    private var logsDirectory: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func setup() {
        let fileName = "\(LogTimestamp.dayOnly()).log"
        let url = logsDirectory.appendingPathComponent(fileName)

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
            fileSize = 0
        } else if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? UInt64 {
            fileSize = size
        }
        fileURL = url
        cleanOldLogs()
    }

    func appendBatch(_ messages: [String]) {
        guard !messages.isEmpty else { return }
        let combined = messages.joined(separator: "\n") + "\n"
        let data = combined.data(using: .utf8) ?? Data()

        if fileSize + UInt64(data.count) >= maxFileSizeBytes { rollOver() }

        guard let url = fileURL, let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
        fileSize += UInt64(data.count)
    }

    /// ★ A4：只读取末尾 N 行
    func readTail(maxLines: Int) -> String {
        guard let url = fileURL,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return content }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    func clear() {
        guard let url = fileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
        fileSize = 0
    }
    
    /// 当前 Logs 目录内所有 .log 文件的总字节数
    func totalBytes() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total = 0
        for url in files where url.pathExtension == "log" {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }

    /// 清理归档日志（保留当前正在写入的当日文件）
    @discardableResult
    func clearArchives() -> Int {
        guard let current = fileURL else { return 0 }
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var removed = 0
        for url in files where url.pathExtension == "log" && url != current {
            if (try? fileManager.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    private func rollOver() {
        guard let url = fileURL else { return }
        let archive = "\(LogTimestamp.archiveName()).log"
        let archiveURL = logsDirectory.appendingPathComponent(archive)
        try? fileManager.moveItem(at: url, to: archiveURL)
        fileManager.createFile(atPath: url.path, contents: nil)
        fileSize = 0
    }

    private func cleanOldLogs() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxRetentionDays, to: Date()) ?? Date()
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        for fileURL in files where fileURL.pathExtension == "log" {
            if let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let mod = attrs.contentModificationDate,
               mod < cutoff {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
