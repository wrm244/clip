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

/// 后台搜索的返回值：命中的条目 id（按原顺序）+ 这次新构建的索引项。
private struct SearchRebuildResult: Sendable {
    var ids: [ClipItem.ID]
    var index: [ClipItem.ID: String]
}

/// 剪贴板历史的内存模型。所有改动都会增量写入 SwiftData（每笔写操作显式落库，
/// 不再全量重写历史文件），列表始终按“固定优先 + 最近使用”排序。
@Observable
final class ClipStore {
    /// 全量历史。
    private(set) var items: [ClipItem] = []
    /// 过滤/搜索之后用于展示的列表。
    private(set) var visibleItems: [ClipItem] = []
    /// 各分类的条目数，随列表变化一次性算好。
    private(set) var filterCounts: [ClipFilter: Int] = [:]

    var searchText: String = "" {
        didSet { if searchText != oldValue { scheduleSearchRebuild() } }
    }

    var filter: ClipFilter = .all {
        didSet { if filter != oldValue { rebuildVisible() } }
    }

    var selectedID: ClipItem.ID?
    var previewVisible: Bool = true
    var toast: ClipToast?

    /// 历史内容或顺序变化后的回调。桌面小组件据此导出只读快照（见 `WidgetFeedWriter`）。
    /// 只关心「会影响快照」的变化，因此搜索框输入（只改 visibleItems）不触发。
    @ObservationIgnored var onHistoryChange: (([ClipItem]) -> Void)?

    private let settings: ClipSettings
    private let storage = ClipStorage.shared
    /// 串行化落库任务：保证数据库写入顺序与内存改动顺序一致，避免新旧快照乱序互相覆盖。
    ///
    /// 这里使用一个长期复用、按需启动的 worker 和队列，而不是每次写入都
    /// `Task { await previous.value ... }` 链接任务。后者的完成 task 会一直持有
    /// `previous`，形成一条只增不减的任务链，长期运行会保留大量历史快照和闭包。
    private var pendingWrites: [@Sendable () async -> Void] = []
    private var pendingWriteIndex = 0
    private var saveWorker: Task<Void, Never>?
    /// 已排队写入的代数：每排一笔自增。`drainSaves` 靠它识别等待期间有没有新写入插队。
    private var saveGeneration: UInt64 = 0
    /// 「清空全部数据」进行中。置位期间拒绝新的采集，并让在途采集在检查点退出——
    /// 否则它们会在 `eraseEverything` 清库 / 删 Blobs 之后又把条目写回来。
    private var isErasing = false
    /// 清空操作的代数。`isErasing` 会在 erase 返回时马上清掉，而在途 `ingest` 的
    /// 挂起点可能在那之后才恢复；只靠布尔值会漏掉这个窗口。采集在入口记下代数，
    /// 提交前对不上就丢弃（见 `ingest`）。
    private var eraseGeneration: UInt64 = 0
    private var toastTask: Task<Void, Never>?

    /// 最近一次删除的条目，供 ⌘Z 撤销。
    ///
    /// 撤销窗口内 Blob 文件先留在磁盘上（只删数据库记录）：图片 / 富文本原样还在，
    /// 恢复时不用重新转码。窗口结束后才把文件真正删掉——见 `scheduleRemovalUndo`。
    @ObservationIgnored private var lastRemoval: (items: [ClipItem], purge: Task<Void, Never>)?
    /// 撤销窗口（秒）：既是 ⌘Z 的有效期，也是被删条目 Blob 在磁盘上多留的时长。
    private static let undoWindow: Double = 20
    /// 搜索索引缓存：id → 小写拼接的搜索文本（含本地化类型标题）。
    ///
    /// bump / markUsed / togglePin 只改 useCount / lastUsedAt / isPinned，
    /// 不动内容字段，缓存始终有效；新条目在重建可见列表时懒加载补齐，
    /// 删除条目 / 切换语言时随条目一起清掉。
    ///
    /// 只缓存不超过 `maxIndexedHaystackBytes` 的条目：超长文本（单条上限 120KB）
    /// 如果全部进索引，会再多占一份接近全文的内存（1000 条最坏 ~200MB）。
    /// 大条目在搜索时现算——主搜索路径走后台去抖重建，代价可接受。
    @ObservationIgnored private var searchIndex: [ClipItem.ID: String] = [:]

    /// id → 在 `items` 中的下标。取代各处 `items.firstIndex(where:)` 的 O(n) 线性查找。
    /// 任何改变 `items` 内容或顺序的操作后都要调 `reindexItems()`。
    /// 标 `@ObservationIgnored`：内部索引，不是界面状态，读它不该让视图失效。
    @ObservationIgnored private var itemsByID: [ClipItem.ID: Int] = [:]

    /// id → 在 `visibleItems` 中的下标。键盘导航每按一次方向键都会查它，
    /// 不能是线性查找。任何给 `visibleItems` 赋值后都要调 `reindexVisible()`。
    /// 标 `@ObservationIgnored`：同上，内部索引不参与观察（`selectedItem` 会读它）。
    @ObservationIgnored private var visibleIndexByID: [ClipItem.ID: Int] = [:]

    /// 单条被缓存进搜索索引的最大字节数（见 `searchHaystack(for:)`）。
    /// `nonisolated`：后台搜索重建任务也要读它。
    nonisolated private static let maxIndexedHaystackBytes = 16 * 1024

    /// 搜索去抖 + 后台匹配的任务。连续输入期间前一个任务被取消。
    private var searchTask: Task<Void, Never>?
    /// 后台字符串扫描任务。`Task.detached` 不会自动继承父任务取消状态，
    /// 所以必须单独保存并取消，否则快速输入会同时跑多个大文本扫描。
    private var searchWorker: Task<SearchRebuildResult, Never>?
    /// 搜索代数：每次计划 / 同步重建可见列表都自增。后台任务完成时若代数已变，
    /// 说明期间又输入了新关键词或发生了结构变化，本次结果作废。
    private var searchGeneration: UInt64 = 0

    /// 行副标题（`detail`）缓存。文本条目要数全文字符数与行数，是 O(全文长度) 的
    /// 字素簇 / 字节扫描（实测单条 120KB 文本约 0.8ms），而列表行在悬停、
    /// 选中、滚动时都会重绘，所以按 id 缓存——条目内容建好之后不再变化，缓存永不失效，
    /// 只在删除条目时随条目一起清掉。
    @ObservationIgnored private var detailCache: [ClipItem.ID: String] = [:]

    init(settings: ClipSettings) {
        self.settings = settings
        previewVisible = settings.showPreview
    }

    // MARK: - 生命周期

    func load() async {
        // 读取失败时拿到 nil：内存保持为空，但绝不清库、绝不清 Blobs——
        // 否则一次暂时性 I/O 故障就会把整份历史连同图片文件全部删光。
        guard let loaded = await storage.fetchAllItems() else {
            Log.store.fault("历史读取失败，本次运行以空列表运行，不执行任何清理")
            rebuildVisible()
            return
        }
        items = applyRetention(loaded)
        // 整体重载：搜索索引与副标题缓存一起重建（懒填充）
        searchIndex = [:]
        detailCache = [:]
        sortItems()
        rebuildVisible()
        notifyHistoryChanged()
        // 被保留策略淘汰的条目同步从数据库删掉（固定条目永不淘汰）。
        let keptIDs = Set(items.map(\.id))
        let droppedIDs = loaded.map(\.id).filter { !keptIDs.contains($0) }
        if !droppedIDs.isEmpty {
            let droppedBlobs = loaded
                .filter { !keptIDs.contains($0.id) }
                .flatMap(\.blobNames)
            let deleted = await storage.delete(ids: droppedIDs, removingBlobs: droppedBlobs)
            // 删除失败时不能继续清孤儿文件，也不要让内存和数据库分叉：
            // 本次会话恢复成完整历史，下一次启动再尝试清理。
            guard deleted else {
                items = loaded
                sortItems()
                rebuildVisible()
                notifyHistoryChanged()
                return
            }
        }
        let keep = Set(items.flatMap(\.blobNames))
        await storage.purgeOrphanBlobs(keeping: keep)
    }

    func diskUsage() async -> Int {
        await storage.diskUsage()
    }

    // MARK: - 写入

    /// 采集到一块新的剪贴板内容。
    func ingest(_ draft: ClipDraft) async {
        // 清空操作进行中时丢弃新内容：否则在途采集会在 `eraseEverything` 清库之后
        // 又把条目（及其已被删除的 Blob 引用）写回来。
        guard settings.isMonitoringEnabled, !isErasing else { return }
        // 记下本次采集开始时的清空代数：期间只要清空过，后面就不再提交。
        let generation = eraseGeneration

        var item = ClipItem(
            id: draft.id,
            kind: draft.kind,
            text: draft.text,
            filePaths: draft.filePaths,
            byteCount: draft.byteCount,
            sourceName: draft.sourceName,
            sourceBundleID: draft.sourceBundleID
        )

        // 阶段一（可挂起）：解析内容、准备二进制负载。
        var blobWrites: [(data: Data, name: String)] = []
        switch draft.kind {
        case .image:
            guard let raw = draft.imageData, let imageBlob = draft.imageBlob, let thumbBlob = draft.thumbBlob else { return }
            guard let transcoded = await ImageTranscoder.shared.transcode(raw, maxBytes: settings.maxItemBytes) else {
                showToast(L("图片过大或无法解析，已忽略"), symbol: "exclamationmark.triangle.fill")
                return
            }
            item.imageBlob = imageBlob
            item.pixelWidth = transcoded.width
            item.pixelHeight = transcoded.height
            item.byteCount = transcoded.png.count
            item.contentHash = transcoded.hash
            blobWrites.append((transcoded.png, imageBlob))
            if let thumbnail = transcoded.thumbnail {
                item.thumbBlob = thumbBlob
                blobWrites.append((thumbnail, thumbBlob))
            }

        default:
            item.contentHash = draft.contentHash
            if let rtf = draft.rtfData, let name = draft.rtfBlob {
                item.rtfBlob = name
                blobWrites.append((rtf, name))
            }
        }

        // 转码 / 解析期间可能开始了「清空全部数据」：此时直接丢弃，别写库。
        guard settings.isMonitoringEnabled, !isErasing, generation == eraseGeneration else { return }

        // 阶段二：先查一次重。命中就只更新用量，不用白写一遍图。
        if let duplicate = duplicateIndex(of: item) {
            bump(duplicate)
            return
        }

        // 阶段三（可挂起）：把二进制**先落盘**，再让条目进内存。
        //
        // 顺序是这里的关键：列表行和预览窗在条目进入 `visibleItems` 的那一帧就会去读
        // 缩略图 / 预览图（`ImageCache` 同步读文件）。文件还没写完就先入内存的话，
        // 第一帧只能画占位图标，等下一次重绘才跳成真图——图片条目看起来就是
        // 「缩略图闪一下 / 预览窗里的图晚一拍出现，把下面的尺寸体积挤下去」。
        var writtenBlobNames: [String] = []
        var failedBlobNames: Set<String> = []
        for blob in blobWrites {
            if await storage.writeBlob(blob.data, named: blob.name) {
                writtenBlobNames.append(blob.name)
            } else {
                failedBlobNames.insert(blob.name)
            }
        }

        // 图片主文件写不进去时整条记录不能提交；缩略图只是展示优化，失败时
        // 去掉引用即可，仍可使用原图作为列表缩略图。
        if let imageBlob = item.imageBlob, failedBlobNames.contains(imageBlob) {
            await storage.removeBlobs(writtenBlobNames)
            showToast(L("图片过大或无法解析，已忽略"), symbol: "exclamationmark.triangle.fill")
            return
        }
        if let thumbBlob = item.thumbBlob, failedBlobNames.contains(thumbBlob) {
            item.thumbBlob = nil
        }
        if let rtfBlob = item.rtfBlob, failedBlobNames.contains(rtfBlob) {
            item.rtfBlob = nil
        }

        // 落盘期间开始过「清空全部数据」：刚写的 Blob 可能已被删掉，直接放弃。
        // 这里必须比对代数：erase 返回时会把 isErasing 清掉，在途采集的恢复点可能落在
        // 那之后，只看布尔值就会漏。
        guard settings.isMonitoringEnabled, !isErasing, generation == eraseGeneration else {
            await storage.removeBlobs(blobWrites.map { $0.name })
            return
        }

        // 阶段四（无 await，原子）：重查重 → 插入 → 排序 → 淘汰 → 重建视图。
        // 上面落盘有挂起点，期间可能已经有另一条相同内容采集进来，所以要再查一次；
        // 这一次查重和插入之间同样**不能**有挂起点，否则两条并发采集会双双入库。
        if let duplicate = duplicateIndex(of: item) {
            bump(duplicate)
            // 刚写下的这版用不上了，删掉，别在 Blobs/ 里留垃圾。
            await storage.removeBlobs(blobWrites.map { $0.name })
            return
        }
        items.insert(item, at: 0)
        sortItems()

        // 先排入写入，再执行保留策略。否则当新条目刚好超出保留上限时，
        // prune 会先把 delete 排进队列，随后 insert 又补回数据库，重启后出现
        // “内存已清理但数据库仍保留”的幽灵记录。
        let snapshot = item
        enqueueSave { [weak self, storage] in
            guard await storage.insert(snapshot) else {
                await self?.reportSaveFailure()
                return
            }
        }

        prune()
        rebuildVisible()
        notifyHistoryChanged()
    }

    /// 内存里是否已有内容相同的条目（图片按转码后的 hash 判重）。
    private func duplicateIndex(of item: ClipItem) -> Int? {
        guard !item.contentHash.isEmpty else { return nil }
        return items.firstIndex { $0.contentHash == item.contentHash }
    }

    /// 同一条内容被重复复制：只更新时间与次数，不新增记录。
    private func bump(_ index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].useCount += 1
        items[index].lastUsedAt = .now
        // 必须在排序前取快照：sortItems 会把这条移到最前（或换分组），
        // 之后 items[index] 已经是另一条了，再拿它落库就会写错行。
        let updated = items[index]
        sortItems()
        rebuildVisible()
        notifyHistoryChanged()
        enqueueUpdate(updated)
    }

    /// 使用（粘贴/复制）某条记录，把它提到最前面。
    func markUsed(_ id: ClipItem.ID) {
        guard !isErasing else { return }
        guard let index = itemsByID[id], items.indices.contains(index) else { return }
        items[index].useCount += 1
        items[index].lastUsedAt = .now
        let updated = items[index]   // 排序前快照，排序后位置会变
        sortItems()
        rebuildVisible()
        notifyHistoryChanged()
        enqueueUpdate(updated)
    }

    // MARK: - 修改

    func togglePin(_ id: ClipItem.ID) {
        guard !isErasing else { return }
        guard let index = itemsByID[id], items.indices.contains(index) else { return }
        items[index].isPinned.toggle()
        let updated = items[index]   // 排序前快照：固定状态切换后会换分组
        sortItems()
        rebuildVisible()
        notifyHistoryChanged()
        enqueueUpdate(updated)
        showToast(updated.isPinned ? L("已固定") : L("已取消固定"), symbol: "pin.fill")
    }

    func remove(_ id: ClipItem.ID) {
        guard !isErasing else { return }
        guard let index = itemsByID[id], items.indices.contains(index) else { return }
        let removed = items[index]
        searchIndex[removed.id] = nil
        detailCache[removed.id] = nil
        items.remove(at: index)
        reindexItems()
        rebuildVisible()
        notifyHistoryChanged()
        // 只删数据库记录，Blob 文件留到撤销窗口结束：这一条要是被 ⌘Z 恢复，
        // 图片 / 富文本仍然在，不用重新转码。真正删文件在 `scheduleRemovalUndo` 里。
        enqueueSave { [weak self, storage] in
            guard await storage.delete(ids: [removed.id]) else {
                await self?.reportSaveFailure()
                return
            }
        }
        scheduleRemovalUndo(for: [removed])
        showToast(L("已删除，⌘Z 撤销"), symbol: "trash.fill")
    }

    /// 记下这次删除，并安排撤销窗口结束后回收它的 Blob 文件。
    ///
    /// 只保留最近一次：再删一条，上一条就不可撤销了。但上一批的回收任务**不能取消**——
    /// 它对应的记录已经不在内存里，窗口过去后那些文件必须删掉，否则会一直占着磁盘。
    private func scheduleRemovalUndo(for removed: [ClipItem]) {
        guard !removed.isEmpty else { return }
        let pairs = removed.map { (id: $0.id, blobs: $0.blobNames) }
        let purge = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            await self?.purgeBlobs(afterUndoWindow: pairs)
        }
        lastRemoval = (items: removed, purge: purge)
    }

    /// 撤销窗口结束：把这些条目真正删除（Blob 文件 + 图片缓存）。
    /// 已经被 ⌘Z 恢复的条目还在 `items` 里，跳过——它的文件还要接着用。
    private func purgeBlobs(afterUndoWindow pairs: [(id: ClipItem.ID, blobs: [String])]) async {
        var names: [String] = []
        for pair in pairs where itemsByID[pair.id] == nil {
            names.append(contentsOf: pair.blobs)
        }
        guard !names.isEmpty else { return }
        ImageCache.shared.remove(names: names)
        await storage.removeBlobs(names)
    }

    /// 撤销最近一次删除（⌘Z）。只在撤销窗口内有效，返回是否恢复了内容。
    @discardableResult
    func undoLastRemoval() -> Bool {
        guard !isErasing, let removal = lastRemoval else { return false }
        lastRemoval = nil
        // 文件还在：取消回收任务，重新插入记录即可原样恢复。
        removal.purge.cancel()
        var restored = 0
        for item in removal.items where itemsByID[item.id] == nil {
            items.append(item)
            restored += 1
        }
        guard restored > 0 else { return false }
        sortItems()
        rebuildVisible()
        notifyHistoryChanged()
        for item in removal.items {
            // 先排行插入，再让 prune 排删除：FIFO 保证顺序与内存一致。
            enqueueSave { [weak self, storage] in
                guard await storage.insert(item) else {
                    await self?.reportSaveFailure()
                    return
                }
            }
        }
        // 恢复后可能又超出保留上限：此时由 prune 自己删记录 + 删 Blob，
        // 上面那条回收任务已经取消，不用再管这批文件。
        prune()
        rebuildVisible()
        showToast(L("已恢复 %ld 条", restored), symbol: "arrow.uturn.backward.circle.fill")
        return true
    }

    /// 保留策略改变时立即淘汰一次（设置界面里的「最多保留 / 保留时长」）。
    /// `prune()` 只改内存并排队落库，视图重建由这里补上。
    func applyRetentionNow() {
        guard !isErasing else { return }
        let before = items.count
        prune()
        rebuildVisible()
        notifyHistoryChanged()
        if items.count < before {
            showToast(L("已按保留策略清理 %ld 条", before - items.count), symbol: "trash.fill")
        }
    }

    func removeAll(keepingPinned: Bool = true) {
        guard !isErasing else { return }
        // 清空是不可逆的批量操作：撤销只针对单条删除，这里把撤销记录一并作废。
        lastRemoval?.purge.cancel()
        lastRemoval = nil
        let dropped = items.filter { !(keepingPinned && $0.isPinned) }
        for item in dropped {
            searchIndex[item.id] = nil
            detailCache[item.id] = nil
        }
        items.removeAll { !(keepingPinned && $0.isPinned) }
        reindexItems()
        rebuildVisible()
        notifyHistoryChanged()
        let ids = dropped.map(\.id)
        let blobs = dropped.flatMap(\.blobNames)
        ImageCache.shared.remove(names: blobs)
        enqueueSave { [storage] in
            _ = await storage.delete(ids: ids, removingBlobs: blobs)
        }
        showToast(keepingPinned ? L("已清空未固定记录") : L("已清空全部记录"), symbol: "trash.fill")
    }

    @discardableResult
    func eraseEverything() async -> Bool {
        // 闸门置位后：新采集会被 ingest 的 guard 丢弃，在途采集也会在各自的检查点退出，
        // 避免它们在清库 / 删 Blobs 之后又把数据写回来。
        isErasing = true
        eraseGeneration &+= 1
        defer { isErasing = false }
        // 先把排队中的写入全部执行完再整体清空，避免在途写入把数据“复活”。
        await drainSaves()
        guard await storage.eraseEverything() else {
            showToast(L("无法清空全部数据"), symbol: "exclamationmark.triangle.fill")
            return false
        }
        lastRemoval?.purge.cancel()
        lastRemoval = nil
        items = []
        searchIndex = [:]
        detailCache = [:]
        ImageCache.shared.clear()
        reindexItems()
        rebuildVisible()
        notifyHistoryChanged()
        return true
    }

    // MARK: - 选择

    /// 按 id 取全量历史里的条目（O(1)）。
    func item(withID id: ClipItem.ID) -> ClipItem? {
        guard let index = itemsByID[id], items.indices.contains(index) else { return nil }
        return items[index]
    }

    var selectedItem: ClipItem? {
        guard let selectedID, let index = visibleIndexByID[selectedID],
              visibleItems.indices.contains(index) else { return nil }
        return visibleItems[index]
    }

    func ensureSelection() {
        if let selectedID, visibleIndexByID[selectedID] != nil { return }
        selectedID = visibleItems.first?.id
    }

    func selectFirst() {
        selectedID = visibleItems.first?.id
    }

    /// 直接选中指定条目（仅当它当前可见时生效）。
    func select(id: ClipItem.ID) {
        guard visibleIndexByID[id] != nil else { return }
        selectedID = id
    }

    func moveSelection(by delta: Int) {
        guard !visibleItems.isEmpty else {
            selectedID = nil
            return
        }
        guard let currentID = selectedID, let current = visibleIndexByID[currentID] else {
            selectedID = visibleItems.first?.id
            return
        }
        let next = min(max(current + delta, 0), visibleItems.count - 1)
        selectedID = visibleItems[next].id
    }

    func removeSelected() {
        guard let id = selectedID, let index = visibleIndexByID[id] else { return }
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

    // MARK: - 本地化

    /// 界面语言变化后调用。
    /// 搜索索引（内含类别标题）与行副标题都按旧语言生成过，必须清掉重建，
    /// 否则英文界面下会搜不到、或列表里夹杂旧语言文案。
    func localizationDidChange() {
        searchIndex = [:]
        detailCache = [:]
        rebuildVisible()
        notifyHistoryChanged()
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

    private func notifyHistoryChanged() {
        onHistoryChange?(items)
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
        reindexItems()
    }

    /// 行副标题。走缓存，避免每次重绘都对超长文本重新做字符 / 行数统计。
    func detail(for item: ClipItem) -> String {
        if let cached = detailCache[item.id] { return cached }
        let value = item.detail
        detailCache[item.id] = value
        return value
    }

    /// 取条目的搜索文本，优先走缓存。所有条目都进缓存（含大文本），
    /// 避免每个按键对同一条大文本重复拼接 + 小写化。
    private func searchHaystack(for item: ClipItem) -> String {
        if let cached = searchIndex[item.id] { return cached }
        let value = item.searchHaystack
        // 只缓存小条目，避免索引再多占一份接近全文的内存（见 searchIndex 声明）。
        if value.utf8.count <= Self.maxIndexedHaystackBytes {
            searchIndex[item.id] = value
        }
        return value
    }

    /// 把搜索框文本切成小写关键词（空格分词）。空串 → 空数组。
    private func normalizedKeywords(_ text: String) -> [Substring] {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
    }

    /// 同步重建可见列表。用于结构变化（增删 / 排序 / 切分类）以及不需要去抖的场景。
    ///
    /// 关键词匹配走已经缓存的搜索索引，所以这里基本只是 O(n) 的 contains 扫描；
    /// 真正的字符串拼接 / 小写化只会发生在索引还没建好的条目上。
    private func rebuildVisible() {
        // 代数自增，作废任何在途的异步搜索结果（它基于更旧的快照）。
        searchGeneration &+= 1
        searchTask?.cancel()
        searchWorker?.cancel()
        searchWorker = nil
        // 分词只做一次；匹配时对每条历史是纯 contains 扫描。
        let keywords = normalizedKeywords(searchText)
        // 关键词为空时必须走单独的短路分支，不要对每条都求值 searchHaystack。
        if keywords.isEmpty {
            visibleItems = items.filter { filter.matches($0) }
        } else {
            visibleItems = items.filter { item in
                guard filter.matches(item) else { return false }
                return item.matches(keywords: keywords, haystack: searchHaystack(for: item))
            }
        }
        finishRebuild()
    }

    /// 搜索文本变化：去抖后把匹配放到后台算，主线程只落最终结果。
    ///
    /// 关键词匹配是 O(条目数 × 文本长度) 的字符串扫描（首次还要拼接 + 小写化），
    /// 直接同步跑会在每个按键上卡主线程。这里先等 120ms，连续输入只算最后一次。
    private func scheduleSearchRebuild() {
        // 清空搜索（或只剩空白）时立即同步重建：空关键词只是 O(n) 的 filter，
        // 没必要去抖，否则清空后会先看到 120ms 的旧结果。
        guard !normalizedKeywords(searchText).isEmpty else {
            rebuildVisible()
            return
        }
        searchTask?.cancel()
        searchWorker?.cancel()
        searchWorker = nil
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            await self.performSearchRebuild(generation: generation)
        }
    }

    /// 在后台线程算好命中条目的 id 与新增的索引项，回到主线程落结果。
    private func performSearchRebuild(generation: UInt64) async {
        let keywords = normalizedKeywords(searchText)
        let snapshot = items
        let filter = self.filter
        let cachedIndex = searchIndex
        // `L()` 是 MainActor：类型标题必须先在主线程取好，再带进后台任务。
        let kindTitles = Dictionary(
            uniqueKeysWithValues: ClipKind.allCases.map { ($0, $0.title.lowercased()) }
        )

        let worker = Task.detached(priority: .userInitiated) { () -> SearchRebuildResult in
            var index = cachedIndex
            var ids: [ClipItem.ID] = []
            ids.reserveCapacity(snapshot.count)
            guard !Task.isCancelled else {
                return SearchRebuildResult(ids: [], index: cachedIndex)
            }
            if keywords.isEmpty {
                for item in snapshot {
                    if Task.isCancelled {
                        return SearchRebuildResult(ids: [], index: cachedIndex)
                    }
                    if filter.matches(item) { ids.append(item.id) }
                }
            } else {
                for item in snapshot {
                    if Task.isCancelled {
                        return SearchRebuildResult(ids: [], index: cachedIndex)
                    }
                    guard filter.matches(item) else { continue }
                    let haystack: String
                    if let cached = index[item.id] {
                        haystack = cached
                    } else {
                        let body = item.searchableBody
                        let title = kindTitles[item.kind] ?? ""
                        let value = body.isEmpty ? title : title + "\n" + body
                        // 与 searchHaystack(for:) 保持一致：只缓存小条目。
                        if value.utf8.count <= ClipStore.maxIndexedHaystackBytes {
                            index[item.id] = value
                        }
                        haystack = value
                    }
                    if item.matches(keywords: keywords, haystack: haystack) {
                        ids.append(item.id)
                    }
                }
            }
            return SearchRebuildResult(ids: ids, index: index)
        }
        searchWorker = worker
        let result = await worker.value
        guard generation == searchGeneration else { return }
        searchWorker = nil
        // 只补写仍然存在、且尚未缓存的索引项：被删除的条目不要借机复活。
        let liveIDs = Set(snapshot.map(\.id))
        for (id, value) in result.index where searchIndex[id] == nil && liveIDs.contains(id) {
            searchIndex[id] = value
        }
        let byID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        visibleItems = result.ids.compactMap { byID[$0] }
        finishRebuild()
    }

    /// 可见列表算好后统一收尾：更新下标的索引、分类计数、选中项。
    private func finishRebuild() {
        reindexVisible()
        // 各分类计数一次遍历统计（原来是每个分类各 filter 一遍，7 次 O(n)）
        var counts = [ClipFilter: Int]()
        counts.reserveCapacity(ClipFilter.allCases.count)
        for item in items {
            counts[.all, default: 0] += 1
            if item.isPinned { counts[.pinned, default: 0] += 1 }
            switch item.kind {
            case .text: counts[.text, default: 0] += 1
            case .image: counts[.image, default: 0] += 1
            case .file: counts[.file, default: 0] += 1
            case .link: counts[.link, default: 0] += 1
            case .color: counts[.color, default: 0] += 1
            }
        }
        filterCounts = counts
        // 注意用 count(for:)：filterCounts 里没有 .pinned 键时值是 nil，
        // 直接写 filterCounts[.pinned] == 0 会得到 false（nil == 0 不成立），
        // 「固定」空分类就永远不回退。
        if count(for: .pinned) == 0, filter == .pinned {
            // 这里会经 didSet 再跑一轮 rebuildVisible（多一次重建）：代价可以接受，
            // 递归深度固定为 1——新一轮里 filter 已经是 .all，不会再次回退。
            // 别为了省这一轮改成「悄悄改值」：那样 visibleItems 会停留在「固定」的
            // 空结果上，界面看着像「列表全没了」。
            filter = .all
        }
        ensureSelection()
    }

    private func reindexItems() {
        itemsByID = Dictionary(
            items.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func reindexVisible() {
        visibleIndexByID = Dictionary(
            visibleItems.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// 按“条数上限 / 保留天数”过滤，固定条目永不淘汰。
    ///
    /// 保留天数按「最后使用时间（lastUsedAt）」计算，而不是创建时间：
    /// 列表里展示的相对时间、以及条数上限保留最新 N 条的取舍，用的都是 lastUsedAt，
    /// 口径必须一致——否则一条昨天刚用过的记录会因为「创建于 30 天前」被删掉，
    /// 而它旁边还写着「1 天前」。
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
            if let cutoff, item.lastUsedAt < cutoff { continue }
            dynamicCount += 1
            if dynamicCount > settings.maxItems { continue }
            result.append(item)
        }
        return result
    }

    /// 按“条数上限 / 保留天数”淘汰超限条目：内存、数据库、Blobs 三侧同步删除。
    private func prune() {
        let kept = applyRetention(items)
        guard kept.count != items.count else { return }
        let keptIDs = Set(kept.map(\.id))
        let dropped = items.filter { !keptIDs.contains($0.id) }
        items = kept
        reindexItems()
        for item in dropped {
            searchIndex[item.id] = nil
            detailCache[item.id] = nil
        }
        let droppedIDs = dropped.map(\.id)
        let droppedBlobs = dropped.flatMap(\.blobNames)
        ImageCache.shared.remove(names: droppedBlobs)
        enqueueSave { [weak self, storage] in
            guard await storage.delete(ids: droppedIDs, removingBlobs: droppedBlobs) else {
                await self?.reportSaveFailure()
                return
            }
        }
    }

    /// 落库失败时给用户一个可见的反馈。
    ///
    /// 落库任务的返回值以前被 `_ = await` 直接丢掉：磁盘满 / 数据库损坏时内存与磁盘
    /// 会静默分叉——被淘汰的条目重启后复活，新采集的内容则直接丢失，界面上看不出
    /// 任何异常。这里至少提示一次，并把细节写进日志。
    private func reportSaveFailure() {
        Log.store.error("本地数据库写入失败，内存与磁盘可能已不一致")
        showToast(L("本地数据库写入失败，改动可能无法保存"), symbol: "exclamationmark.triangle.fill", seconds: 5)
    }

    // MARK: - 落库

    /// 把一次数据库写入排到队尾。每笔写操作在改完内存后立即排队，
    /// 上一笔写完才轮到下一笔：写入顺序与内存改动顺序严格一致，
    /// 不会出现“后产生的快照先落库、再被旧快照覆盖”。写失败只记日志，不影响内存状态。
    private func enqueueSave(_ write: @escaping @Sendable () async -> Void) {
        saveGeneration &+= 1
        pendingWrites.append(write)
        guard saveWorker == nil else { return }
        saveWorker = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSaveQueue()
        }
    }

    /// 单 worker 按 FIFO 顺序消费写入队列。所有访问都在 MainActor 上，
    /// 队列中的闭包只捕获 Sendable 快照，不跨 actor 传递非 Sendable 对象。
    private func runSaveQueue() async {
        while pendingWriteIndex < pendingWrites.count {
            let write = pendingWrites[pendingWriteIndex]
            pendingWriteIndex += 1
            await write()
        }
        pendingWrites.removeAll(keepingCapacity: true)
        pendingWriteIndex = 0
        saveWorker = nil
    }

    /// 只更新使用状态（useCount / lastUsedAt / isPinned）。
    /// SwiftData 不会因为全文/文件路径很大而重复写大块数据。
    private func enqueueUpdate(_ item: ClipItem) {
        enqueueSave { [storage] in _ = await storage.updateUsage(item) }
    }

    /// 等待所有在途写入完成（清空数据前调用）。
    ///
    /// 单 worker 会持续消费队列，所以「当前 worker 完成」就等于「此刻已排队的写入
    /// 全部落库」；只有等待期间又排进了新写入（代数变化）时才再等一轮。
    private func drainSaves() async {
        while true {
            let generation = saveGeneration
            guard let worker = saveWorker else { return }
            await worker.value
            // worker 可能已经消费完当前队列；若等待期间又排入了新写入，再等一轮。
            // 绝不能写成 `while let worker = saveWorker { await worker.value }`：
            // 已完成的 task 再 await 会立即返回，条件仍可能成立。
            if saveGeneration == generation { return }
        }
    }

    /// 退出前等待所有在途写入落库。
    /// 配合 `applicationShouldTerminate` 的 `.terminateLater` 使用，
    /// 否则 `enqueueSave` 队列若没跑完，最后一次复制会丢。
    func drainSavesForTermination() async {
        await drainSaves()
    }
}
