import Foundation
import os

/// 读取结果。failed 表示文件存在但无法解析，此时绝不能覆盖磁盘内容。
struct StorageLoadOutcome: Sendable {
    var items: [ClipItem] = []
    var failed = false
    var hadFile = false
}

/// 磁盘存储。布局：~/Library/Application Support/Clip/{history.json, Blobs/*}
/// 所有文件读写都在这个 actor 上完成，主线程不碰磁盘。
actor ClipStorage {
    static let shared = ClipStorage()

    /// 数据目录，界面里“在访达中显示”时会用到。
    nonisolated let rootURL: URL
    nonisolated let blobsURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        let root = base.appending(path: "Clip", directoryHint: .isDirectory)
        rootURL = root
        blobsURL = root.appending(path: "Blobs", directoryHint: .isDirectory)
    }

    nonisolated var historyURL: URL { rootURL.appending(path: "history.json") }

    nonisolated func blobURL(named name: String) -> URL {
        blobsURL.appending(path: name)
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    }

    // MARK: 历史记录

    func loadItems() -> StorageLoadOutcome {
        ensureDirectories()
        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return StorageLoadOutcome()
        }
        guard let data = try? Data(contentsOf: historyURL) else {
            return StorageLoadOutcome(failed: true, hadFile: true)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return StorageLoadOutcome(items: try decoder.decode([ClipItem].self, from: data), hadFile: true)
        } catch {
            // 容错：备份现场后报告失败，由上层决定不做任何覆盖或清理。
            let stamp = Int(Date.now.timeIntervalSince1970)
            let backup = rootURL.appending(path: "history-corrupt-\(stamp).json")
            try? data.write(to: backup, options: .atomic)
            Log.store.error("history.json 解析失败，已备份到 \(backup.lastPathComponent, privacy: .public)")
            return StorageLoadOutcome(failed: true, hadFile: true)
        }
    }

    func save(_ items: [ClipItem]) {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    /// 退出流程里使用：不经过 actor 直接同步写盘。
    nonisolated func saveSynchronously(_ items: [ClipItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    // MARK: 二进制负载

    func writeBlob(_ data: Data, named name: String) {
        ensureDirectories()
        try? data.write(to: blobsURL.appending(path: name), options: .atomic)
    }

    func readBlob(named name: String) -> Data? {
        try? Data(contentsOf: blobsURL.appending(path: name))
    }

    func removeBlobs(_ names: [String]) {
        let manager = FileManager.default
        for name in names {
            try? manager.removeItem(at: blobsURL.appending(path: name))
        }
    }

    /// 删除没有任何条目引用的残留文件。
    func purgeOrphanBlobs(keeping names: Set<String>) {
        ensureDirectories()
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: blobsURL, includingPropertiesForKeys: nil) else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? manager.removeItem(at: file)
        }
    }

    func eraseEverything() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// 数据目录占用的字节数。
    func diskUsage() -> Int {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for file in files {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
