import AppKit
import Foundation
import WidgetKit

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

    /// 防抖导出：历史频繁变化（连续复制、切换固定等）时合并成一次写盘 + 一次刷新。
    func scheduleUpdate(items: [ClipItem]) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.write(items: items)
        }
    }

    /// 立即导出并让系统刷新小组件时间线。
    func write(items: [ClipItem]) async {
        let fileManager = FileManager.default
        let thumbsDirectory = WidgetFeed.thumbsDirectoryURL()
        try? fileManager.createDirectory(at: thumbsDirectory, withIntermediateDirectories: true)

        var feedItems: [WidgetFeedItem] = []
        var keptThumbs: Set<String> = []

        for item in items.prefix(limit) {
            var thumbName: String?
            // 只有图片条目有缩略图；缩略图已经是小尺寸 JPEG，直接落盘复用。
            if item.kind == .image, let blob = item.thumbBlob,
               let data = await storage.readBlob(named: blob) {
                let name = "\(item.id.uuidString).jpg"
                if (try? data.write(to: thumbsDirectory.appending(path: name), options: .atomic)) != nil {
                    thumbName = name
                    keptThumbs.insert(name)
                }
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

        // 清掉已不再被引用的缩略图，避免目录随历史无限增长。
        if let existing = try? fileManager.contentsOfDirectory(at: thumbsDirectory, includingPropertiesForKeys: nil) {
            for file in existing where !keptThumbs.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }

        let feed = WidgetFeed(
            language: Localization.shared.resolved.rawValue,
            generatedAt: .now,
            items: feedItems
        )
        if let data = try? JSONEncoder.widget.encode(feed) {
            try? data.write(to: WidgetFeed.fileURL(), options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
