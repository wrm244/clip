import AppKit
import Foundation
import Observation
import os

/// 短暂的状态提示。
struct ClipToast: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String
    var symbol: String
}

/// 剪贴板历史的内存模型。所有改动都会防抖后写盘，列表始终按“固定优先 + 最近使用”排序。
@Observable
final class ClipStore {
    /// 全量历史。
    private(set) var items: [ClipItem] = []
    /// 过滤/搜索之后用于展示的列表。
    private(set) var visibleItems: [ClipItem] = []
    /// 各分类的条目数，随列表变化一次性算好。
    private(set) var filterCounts: [ClipFilter: Int] = [:]

    var searchText: String = "" {
        didSet { if searchText != oldValue { rebuildVisible() } }
    }

    var filter: ClipFilter = .all {
        didSet { if filter != oldValue { rebuildVisible() } }
    }

    var selectedID: ClipItem.ID?
    var previewVisible: Bool = true
    var toast: ClipToast?
    private(set) var isReady = false

    private let settings: ClipSettings
    private let storage = ClipStorage.shared
    private var saveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init(settings: ClipSettings) {
        self.settings = settings
        previewVisible = settings.showPreview
    }

    // MARK: - 生命周期

    func load() async {
        let outcome = await storage.loadItems()
        guard !outcome.failed else {
            // 磁盘上的历史读不出来，就不要用空列表覆盖它，也不要清理图片。
            isReady = true
            showToast("历史文件损坏，已备份，未覆盖原数据", symbol: "exclamationmark.triangle.fill")
            return
        }
        items = applyRetention(outcome.items)
        sortItems()
        rebuildVisible()
        isReady = true
        saveSoon()
        let keep = Set(items.flatMap(\.blobNames))
        await storage.purgeOrphanBlobs(keeping: keep)
    }

    func flush() async {
        saveTask?.cancel()
        await storage.save(items)
    }

    func diskUsage() async -> Int {
        await storage.diskUsage()
    }

    // MARK: - 写入

    /// 采集到一块新的剪贴板内容。
    func ingest(_ draft: ClipDraft) async {
        guard settings.isMonitoringEnabled else { return }

        var item = ClipItem(
            id: draft.id,
            kind: draft.kind,
            text: draft.text,
            filePaths: draft.filePaths,
            byteCount: draft.byteCount,
            sourceName: draft.sourceName,
            sourceBundleID: draft.sourceBundleID
        )

        switch draft.kind {
        case .image:
            guard let raw = draft.imageData, let imageBlob = draft.imageBlob, let thumbBlob = draft.thumbBlob else { return }
            guard let transcoded = await ImageTranscoder.shared.transcode(raw, maxBytes: settings.maxItemBytes) else {
                showToast("图片过大或无法解析，已忽略", symbol: "exclamationmark.triangle.fill")
                return
            }
            if let duplicate = items.firstIndex(where: { $0.contentHash == transcoded.hash }) {
                bump(duplicate)
                return
            }
            item.imageBlob = imageBlob
            item.thumbBlob = thumbBlob
            item.pixelWidth = transcoded.width
            item.pixelHeight = transcoded.height
            item.byteCount = transcoded.png.count
            item.contentHash = transcoded.hash
            await storage.writeBlob(transcoded.png, named: imageBlob)
            if let thumbnail = transcoded.thumbnail {
                await storage.writeBlob(thumbnail, named: thumbBlob)
            }

        default:
            if !draft.contentHash.isEmpty,
               let duplicate = items.firstIndex(where: { $0.contentHash == draft.contentHash }) {
                bump(duplicate)
                return
            }
            item.contentHash = draft.contentHash
            if let rtf = draft.rtfData, let name = draft.rtfBlob {
                await storage.writeBlob(rtf, named: name)
                item.rtfBlob = name
            }
        }

        items.insert(item, at: 0)
        sortItems()
        prune()
        rebuildVisible()
        saveSoon()
    }

    /// 同一条内容被重复复制：只更新时间与次数，不新增记录。
    private func bump(_ index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].useCount += 1
        items[index].lastUsedAt = .now
        sortItems()
        rebuildVisible()
        saveSoon()
    }

    /// 使用（粘贴/复制）某条记录，把它提到最前面。
    func markUsed(_ id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].useCount += 1
        items[index].lastUsedAt = .now
        sortItems()
        rebuildVisible()
        saveSoon()
    }

    // MARK: - 修改

    func togglePin(_ id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        rebuildVisible()
        saveSoon()
        showToast(items[index].isPinned ? "已固定" : "已取消固定", symbol: "pin.fill")
    }

    func remove(_ id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let blobs = items[index].blobNames
        items.remove(at: index)
        rebuildVisible()
        saveSoon()
        Task { await storage.removeBlobs(blobs) }
    }

    func removeAll(keepingPinned: Bool = true) {
        let dropped = items.filter { !(keepingPinned && $0.isPinned) }
        items.removeAll { !(keepingPinned && $0.isPinned) }
        rebuildVisible()
        saveSoon()
        let blobs = dropped.flatMap(\.blobNames)
        Task { await storage.removeBlobs(blobs) }
        showToast(keepingPinned ? "已清空未固定记录" : "已清空全部记录", symbol: "trash.fill")
    }

    func eraseEverything() async {
        saveTask?.cancel()
        items = []
        rebuildVisible()
        await storage.eraseEverything()
    }

    // MARK: - 选择

    var selectedItem: ClipItem? {
        guard let selectedID else { return nil }
        return visibleItems.first { $0.id == selectedID }
    }

    func ensureSelection() {
        if let selectedID, visibleItems.contains(where: { $0.id == selectedID }) { return }
        selectedID = visibleItems.first?.id
    }

    func selectFirst() {
        selectedID = visibleItems.first?.id
    }

    func moveSelection(by delta: Int) {
        guard !visibleItems.isEmpty else {
            selectedID = nil
            return
        }
        guard let current = visibleItems.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = visibleItems.first?.id
            return
        }
        let next = min(max(current + delta, 0), visibleItems.count - 1)
        selectedID = visibleItems[next].id
    }

    func removeSelected() {
        guard let id = selectedID, let index = visibleItems.firstIndex(where: { $0.id == id }) else { return }
        remove(id)
        guard !visibleItems.isEmpty else {
            selectedID = nil
            return
        }
        selectedID = visibleItems[min(index, visibleItems.count - 1)].id
    }

    func togglePinSelected() {
        guard let id = selectedID else { return }
        togglePin(id)
    }

    func count(for filter: ClipFilter) -> Int {
        filterCounts[filter] ?? 0
    }

    // MARK: - 提示

    func showToast(_ text: String, symbol: String = "checkmark.circle.fill", seconds: Double = 2) {
        let newToast = ClipToast(text: text, symbol: symbol)
        toast = newToast
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if toast?.id == newToast.id { toast = nil }
        }
    }

    // MARK: - 内部

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    private func rebuildVisible() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        visibleItems = items.filter { item in
            filter.matches(item) && item.matches(query: query)
        }
        var counts: [ClipFilter: Int] = [:]
        for candidate in ClipFilter.allCases {
            counts[candidate] = items.filter { candidate.matches($0) }.count
        }
        filterCounts = counts
        if filterCounts[.pinned] == 0, filter == .pinned {
            filter = .all
        }
        ensureSelection()
    }

    /// 按“条数上限 / 保留天数”过滤，固定条目永不淘汰。
    private func applyRetention(_ list: [ClipItem]) -> [ClipItem] {
        let cutoff = settings.retentionDays > 0
            ? Date.now.addingTimeInterval(-Double(settings.retentionDays) * 86_400)
            : nil
        var result: [ClipItem] = []
        var dynamicCount = 0
        for item in list {
            if item.isPinned {
                result.append(item)
                continue
            }
            if let cutoff, item.createdAt < cutoff { continue }
            dynamicCount += 1
            if dynamicCount > settings.maxItems { continue }
            result.append(item)
        }
        return result
    }

    private func prune() {
        let kept = applyRetention(items)
        guard kept.count != items.count else { return }
        let keptIDs = Set(kept.map(\.id))
        let droppedBlobs = items.filter { !keptIDs.contains($0.id) }.flatMap(\.blobNames)
        items = kept
        guard !droppedBlobs.isEmpty else { return }
        Task { await storage.removeBlobs(droppedBlobs) }
    }

    /// 防抖写盘，避免连续复制时频繁落盘。
    private func saveSoon() {
        saveTask?.cancel()
        let snapshot = items
        saveTask = Task { [storage] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await storage.save(snapshot)
        }
    }
}
