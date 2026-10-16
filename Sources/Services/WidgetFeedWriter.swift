import AppKit
import Foundation
import WidgetKit
import os

fileprivate nonisolated struct WidgetFeedThumbWrite: Sendable {
    let name: String
    let data: Data
}

/// 把最近历史导出成只读快照，供桌面小组件读取（共享通道的说明见 `WidgetFeed`）。
///
/// 为什么是「导出快照」而不是让小组件直接读库：
/// 小组件是独立沙盒进程，打不开主 App 的 SwiftData 库；App Group 在免签构建下
/// 又会被系统忽略。因此这里只导出展示所需的最小信息（标题、副标题、类型、时间、
/// 缩略图），字符串按当前界面语言预先渲染好，小组件拿到就能直接画。
@MainActor
final class WidgetFeedWriter {
    static let shared = WidgetFeedWriter()

    /// 快照最多保留的条目数：够铺满最大号小组件即可，避免无谓的磁盘与解析开销。
    private let limit = 12

    private let storage = ClipStorage.shared
    private var pending: Task<Void, Never>?
    /// 最近一次防抖调度对应的历史快照，退出前 flush 使用。
    private var latestItems: [ClipItem]?
    /// 防抖任务代数。取消只能阻止还没开始的写盘；已经进入 write() 的旧任务
    /// 还要靠它避免在磁盘序列化器里反过来覆盖较新的快照。
    private var updateGeneration: UInt64 = 0

    /// 防抖导出：历史频繁变化（连续复制、切换固定等）时合并成一次写盘 + 一次刷新。
    func scheduleUpdate(items: [ClipItem]) {
        // 小组件最多只展示 limit 条；不要把完整历史数组留在防抖任务里。
        let snapshot = Array(items.prefix(limit))
        latestItems = snapshot
        updateGeneration &+= 1
        let generation = updateGeneration
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.write(items: snapshot, generation: generation)
        }
    }

    /// 退出前立即写完最近一次历史快照，避免刚复制的内容只进了数据库、没进小组件。
    func flush() async {
        pending?.cancel()
        guard let items = latestItems else { return }
        updateGeneration &+= 1
        let generation = updateGeneration
        await write(items: items, generation: generation)
    }

    /// 立即导出并让系统刷新小组件时间线。
    private func write(items: [ClipItem], generation: UInt64) async {
        // 先在主线程把展示字符串渲染好（`title` / `detail` 要走 `L()`），
        // 其余磁盘 I/O 全部丢到后台（见 persist）。
        var feedItems: [WidgetFeedItem] = []
        var thumbWrites: [WidgetFeedThumbWrite] = []

        for item in items.prefix(limit) {
            guard !Task.isCancelled else { return }
            var thumbName: String?
            // 只有图片条目有缩略图；缩略图已经是小尺寸 JPEG，直接落盘复用。
            if item.kind == .image, let blob = item.thumbBlob,
               let data = await storage.readBlob(named: blob) {
                let name = "\(item.id.uuidString).jpg"
                thumbName = name
                thumbWrites.append(WidgetFeedThumbWrite(name: name, data: data))
            }
            feedItems.append(WidgetFeedItem(
                id: item.id,
                kind: item.kind.rawValue,
                title: item.title,
                detail: item.detail,
                isPinned: item.isPinned,
                lastUsedAt: item.lastUsedAt,
                thumb: thumbName
            ))
        }

        let feed = WidgetFeed(
            language: Localization.shared.resolved.rawValue,
            generatedAt: .now,
            items: feedItems
        )
        // 准备字符串和读取缩略图期间可能有更新的历史版本入队；旧版本直接丢弃。
        guard generation == updateGeneration else { return }
        await WidgetFeedDiskWriter.shared.persist(feed: feed, thumbWrites: thumbWrites)
    }
}

/// 串行化快照落盘。WidgetFeedWriter 可以从多个防抖任务调用 persist；
/// actor 保证缩略图写入、feed.json 原子替换和旧文件清理不会交叠。
fileprivate actor WidgetFeedDiskWriter {
    static let shared = WidgetFeedDiskWriter()

    /// 落盘 + 刷新小组件，整段在后台执行。
    /// 逐张缩略图写盘、目录扫描、JSON 编码原先都跑在主线程上，条目一多就会卡。
    fileprivate func persist(feed: WidgetFeed, thumbWrites: [WidgetFeedThumbWrite]) async {
        let fileManager = FileManager.default
        let thumbsDirectory = WidgetFeed.thumbsDirectoryURL()
        do {
            try fileManager.createDirectory(at: thumbsDirectory, withIntermediateDirectories: true)
        } catch {
            Log.store.error("创建小组件快照目录失败：\(String(describing: error), privacy: .public)")
            return
        }

        var keptThumbs: Set<String> = []
        for write in thumbWrites {
            do {
                try write.data.write(
                    to: thumbsDirectory.appending(path: write.name),
                    options: .atomic
                )
                keptThumbs.insert(write.name)
            } catch {
                Log.store.error("写入小组件缩略图失败：\(write.name, privacy: .public)")
            }
        }

        // 必须先成功替换 feed.json，再删旧缩略图。反过来会在 JSON 写入失败时
        // 留下旧快照引用已被删除缩略图的“空图”状态。
        do {
            // 写入缩略图失败的条目要去掉引用，不能让 feed 指向一个不存在的文件。
            var persistedFeed = feed
            persistedFeed.items = feed.items.map { item in
                var item = item
                if let thumb = item.thumb, !keptThumbs.contains(thumb) {
                    item.thumb = nil
                }
                return item
            }
            let data = try JSONEncoder.makeWidget().encode(persistedFeed)
            try data.write(to: WidgetFeed.fileURL(), options: .atomic)
        } catch {
            Log.store.error("写入小组件快照失败：\(String(describing: error), privacy: .public)")
            return
        }

        // 新 feed 已稳定落盘，清理它不再引用的旧缩略图。
        if let existing = try? fileManager.contentsOfDirectory(
            at: thumbsDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in existing where !keptThumbs.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }

        // 只刷新本 App 的小组件；reloadAllTimelines() 会把系统里所有 App 的小组件都重置一遍。
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetFeed.widgetKind)
    }
}
