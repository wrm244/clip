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
        didSet { if searchText != oldValue { rebuildVisible() } }
    }

    var filter: ClipFilter = .all {
        didSet { if filter != oldValue { rebuildVisible() } }
    }

    var selectedID: ClipItem.ID?
    var previewVisible: Bool = true
    var toast: ClipToast?
    private(set) var isReady = false

    /// 历史内容或顺序变化后的回调。桌面小组件据此导出只读快照（见 `WidgetFeedWriter`）。
    /// 只关心「会影响快照」的变化，因此搜索框输入（只改 visibleItems）不触发。
    @ObservationIgnored var onHistoryChange: (([ClipItem]) -> Void)?

    private let settings: ClipSettings
    private let storage = ClipStorage.shared
    /// 串行化落库任务：保证数据库写入顺序与内存改动顺序一致，避免新旧快照乱序互相覆盖。
    /// 注意：任务完成后引用不会被清空，所以判断“是否还有在途写入”不能看它是否为 nil，
    /// 要用下面的 saveGeneration。
    private var pendingSave: Task<Void, Never>?
    /// 已排队写入的代数：每排一笔自增。`drainSaves` 靠它识别等待期间有没有新写入插队。
    private var saveGeneration: UInt64 = 0
    private var toastTask: Task<Void, Never>?
    /// 搜索索引缓存：id → 小写拼接的搜索文本。
    ///
    /// bump / markUsed / togglePin 只改 useCount / lastUsedAt / isPinned，
    /// 不动内容字段，缓存始终有效；新条目在 rebuildVisible 里懒加载补齐，
    /// 删除条目时随条目一起清掉。没有这层缓存，搜索框每敲一个字都要对
    /// 全部历史重新拼接 + 小写化（单条文本上限 120KB，几百条时一次按键
    /// 就是几十 MB 量级的字符串分配）。
    private var searchIndex: [ClipItem.ID: String] = [:]

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
            isReady = true
            return
        }
        items = applyRetention(loaded)
        // 整体重载：搜索索引与副标题缓存一起重建（懒填充）
        searchIndex = [:]
        detailCache = [:]
        sortItems()
        rebuildVisible()
        isReady = true
        notifyHistoryChanged()
        // 被保留策略淘汰的条目同步从数据库删掉（固定条目永不淘汰）。
        let keptIDs = Set(items.map(\.id))
        let droppedIDs = loaded.map(\.id).filter { !keptIDs.contains($0) }
        if !droppedIDs.isEmpty {
            await storage.delete(ids: droppedIDs)
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
            item.thumbBlob = thumbBlob
            item.pixelWidth = transcoded.width
            item.pixelHeight = transcoded.height
            item.byteCount = transcoded.png.count
            item.contentHash = transcoded.hash
            blobWrites.append((transcoded.png, imageBlob))
            if let thumbnail = transcoded.thumbnail {
                blobWrites.append((thumbnail, thumbBlob))
            }

        default:
            item.contentHash = draft.contentHash
            if let rtf = draft.rtfData, let name = draft.rtfBlob {
                item.rtfBlob = name
                blobWrites.append((rtf, name))
            }
        }

        // 阶段二（无 await，原子）：去重 → 插入 → 排序 → 淘汰 → 重建视图。
        // 去重和插入之间绝不能有挂起点：两条相同内容并发采集时，
        // 挂起窗口里的另一条查不到刚插进来的这条，同一条目就会入库两次。
        if !item.contentHash.isEmpty,
           let duplicate = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            bump(duplicate)
            return
        }
        items.insert(item, at: 0)
        sortItems()
        prune()
        rebuildVisible()
        notifyHistoryChanged()

        // 阶段三（可挂起）：落盘 blob、排队落库。内存状态已就位，
        // 这里的 I/O 顺序不影响正确性。
        for blob in blobWrites {
            await storage.writeBlob(blob.data, named: blob.name)
        }
        let snapshot = item
        enqueueSave { [storage] in await storage.insert(snapshot) }
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
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
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
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        let updated = items[index]   // 排序前快照：固定状态切换后会换分组
        sortItems()
        rebuildVisible()
        notifyHistoryChanged()
        enqueueUpdate(updated)
        showToast(updated.isPinned ? L("已固定") : L("已取消固定"), symbol: "pin.fill")
    }

    func remove(_ id: ClipItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removedID = items[index].id
        let blobs = items[index].blobNames
        searchIndex[removedID] = nil
        detailCache[removedID] = nil
        items.remove(at: index)
        rebuildVisible()
        notifyHistoryChanged()
        enqueueSave { [storage] in
            await storage.delete(ids: [removedID])
            await storage.removeBlobs(blobs)
        }
    }

    /// 保留策略改变时立即淘汰一次（设置界面里的「最多保留 / 保留时长」）。
    /// `prune()` 只改内存并排队落库，视图重建由这里补上。
    func applyRetentionNow() {
        let before = items.count
        prune()
        rebuildVisible()
        notifyHistoryChanged()
        if items.count < before {
            showToast(L("已按保留策略清理 %ld 条", before - items.count), symbol: "trash.fill")
        }
    }

    func removeAll(keepingPinned: Bool = true) {
        let dropped = items.filter { !(keepingPinned && $0.isPinned) }
        for item in dropped {
            searchIndex[item.id] = nil
            detailCache[item.id] = nil
        }
        items.removeAll { !(keepingPinned && $0.isPinned) }
        rebuildVisible()
        notifyHistoryChanged()
        let ids = dropped.map(\.id)
        let blobs = dropped.flatMap(\.blobNames)
        enqueueSave { [storage] in
            await storage.delete(ids: ids)
            await storage.removeBlobs(blobs)
        }
        showToast(keepingPinned ? L("已清空未固定记录") : L("已清空全部记录"), symbol: "trash.fill")
    }

    func eraseEverything() async {
        items = []
        searchIndex = [:]
        detailCache = [:]
        rebuildVisible()
        // 先把排队中的写入全部执行完再整体清空，避免在途写入把数据“复活”。
        await drainSaves()
        await storage.eraseEverything()
        notifyHistoryChanged()
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

    /// 直接选中指定条目（仅当它当前可见时生效）。
    func select(id: ClipItem.ID) {
        guard visibleItems.contains(where: { $0.id == id }) else { return }
        selectedID = id
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
    }

    /// 行副标题。走缓存，避免每次重绘都对超长文本重新做字符 / 行数统计。
    func detail(for item: ClipItem) -> String {
        if let cached = detailCache[item.id] { return cached }
        let value = item.detail
        detailCache[item.id] = value
        return value
    }

    /// 取条目的搜索文本，优先走缓存。
    /// 超大文本不缓存，避免索引本身吃掉几十 MB 内存。
    private func searchHaystack(for item: ClipItem) -> String {
        if let cached = searchIndex[item.id] { return cached }
        let value = item.searchHaystack
        if value.utf8.count <= 65_536 {
            searchIndex[item.id] = value
        }
        return value
    }

    private func rebuildVisible() {
        // 分词只做一次；匹配时对每条历史是纯 contains 扫描
        let keywords = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
        // 关键词为空时必须走单独的短路分支：searchHaystack(for:) 是实参，
        // 会在进入 matches 之前就被求值——否则每次打开面板 / 清空搜索框，
        // 都要把全部历史重新拼接 + 小写化一遍（实测单条 120KB 文本约 2.3ms，
        // 几百条就是几百毫秒的主线程卡顿），而这一步对空搜索毫无用处。
        if keywords.isEmpty {
            visibleItems = items.filter { filter.matches($0) }
        } else {
            visibleItems = items.filter { item in
                guard filter.matches(item) else { return false }
                return item.matches(keywords: keywords, haystack: searchHaystack(for: item))
            }
        }
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
        if filterCounts[.pinned] == 0, filter == .pinned {
            filter = .all
        }
        ensureSelection()
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
        for item in dropped {
            searchIndex[item.id] = nil
            detailCache[item.id] = nil
        }
        let droppedIDs = dropped.map(\.id)
        let droppedBlobs = dropped.flatMap(\.blobNames)
        enqueueSave { [storage] in
            await storage.delete(ids: droppedIDs)
            await storage.removeBlobs(droppedBlobs)
        }
    }

    // MARK: - 落库

    /// 把一次数据库写入排到队尾。每笔写操作在改完内存后立即排队，
    /// 上一笔写完才轮到下一笔：写入顺序与内存改动顺序严格一致，
    /// 不会出现“后产生的快照先落库、再被旧快照覆盖”。写失败只记日志，不影响内存状态。
    private func enqueueSave(_ write: @escaping @Sendable () async -> Void) {
        let previous = pendingSave
        saveGeneration += 1
        pendingSave = Task {
            await previous?.value
            await write()
        }
    }

    /// 整条覆盖式更新（useCount / lastUsedAt / isPinned 等小字段改动都走这里，
    /// SwiftData 只重写这一行，代价极小）。
    private func enqueueUpdate(_ item: ClipItem) {
        enqueueSave { [storage] in await storage.update(item) }
    }

    /// 等待所有在途写入完成（清空数据前调用）。
    ///
    /// 队尾任务内部链式等待了它之前的每一笔写入，所以「当前队尾完成」就等于
    /// 「此刻已排队的写入全部落库」；只有等待期间又排进了新写入（代数变化）时才再等一轮。
    private func drainSaves() async {
        while true {
            // 必须先读代数、后读队尾：顺序反过来的话，两次读之间插进来的新写入会被漏等。
            let generation = saveGeneration
            guard let pending = pendingSave else { return }
            await pending.value
            // 绝不能写成 `while let pending = pendingSave { await pending.value }`：
            // pendingSave 在任务完成后不会被置空，对已完成的任务再 await 会立即返回，
            // 条件恒为真、循环永不退出——这段代码跑在主线程上，整个 App 会直接卡死
            // （旧版「清空全部数据」必卡死就是这个原因）。
            if saveGeneration == generation { return }
        }
    }
}
