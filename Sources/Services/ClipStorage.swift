import Foundation
import os
import SwiftData

/// SwiftData schema v1。以后模型演进时：复制一份成 V2 并修改字段，
/// 在 ClipMigrationPlan 里登记两个版本与迁移阶段（lightweight 或 custom）。
private enum ClipSchemaV1: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)
    nonisolated static var models: [any PersistentModel.Type] { [ClipRecord.self] }
}

/// 迁移计划。当前只有 v1（stages 为空），但容器会据此记录 schema 版本，
/// 之后的每次模型演进都能走显式、可控的迁移路径。
private enum ClipMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] { [ClipSchemaV1.self] }
    nonisolated static var stages: [MigrationStage] { [] }
}

/// 磁盘存储。布局：~/Library/Application Support/Clip/{Clip.store, Blobs/*}
///
/// **静态数据保护**：历史全文就是数据库里的明文，没有加密（SwiftData /
/// SQLite 本身不提供静态加密，加就要引 SQLCipher 或自建加密容器）。
/// 所以这里只做能做的部分：数据目录 0700、库文件和 Blob 0600、
/// 整棵目录树排除出备份，避免历史随 Time Machine / iCloud 离开本机。
/// 以同一用户身份运行的代码仍然能读到这些文件——它同样能直接读剪贴板，
/// 所以这类隔离靠权限是拦不住的，只能靠「不存明文」才能解决。
///
/// 条目元数据与文本存进 SwiftData（底层 SQLite，按条增量写，不再全量重写历史文件）；
/// 图片 / RTF 等大块二进制保留为 `Blobs/` 下的独立文件，记录里只存文件名——
/// `ImageCache` 依赖同步读盘，保持这个行为可以把改动面降到最小。
///
/// 并发模型：普通 `actor` + 懒创建 `ModelContext`。actor 方法跑在全局并发执行器上，
/// 每次访问都串行执行，`ModelContext` 不会被多个线程并发使用。
/// （`@ModelActor` 同样能提供互斥的 context 访问——它的 executor 不绑定创建线程，
/// 旧注释说法有误；不用它只是因为它会把 context 暴露成 actor 隔离属性并生成一整套
/// fetch/save 模板，而这里自己持有一个私有 context 更贴合现有接口形态。）
/// 不依赖 autosave（强杀时 autosave 不落盘），每次写操作显式 `save()`。
actor ClipStorage {
    static let shared = ClipStorage()

    /// 数据目录，界面里“在访达中显示”时会用到。
    nonisolated let rootURL: URL
    nonisolated let blobsURL: URL
    /// ModelContainer 是 Sendable，可以在 nonisolated init 里建好。
    nonisolated let container: ModelContainer
    /// 是否为「磁盘库打开失败」后的内存回退容器。
    ///
    /// 回退时磁盘上的历史其实还在，只是这次运行读不到——此时必须被视为
    /// 「读取失败」而**不能**被当成「库里是空的」：否则启动清理逻辑会把
    /// Blobs/ 下所有图片当成孤儿文件删掉（见 fetchAllItems）。
    nonisolated let isEphemeralFallback: Bool

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        let root = base.appending(path: "Clip", directoryHint: .isDirectory)
        rootURL = root
        blobsURL = root.appending(path: "Blobs", directoryHint: .isDirectory)
        Self.createPrivateDirectory(at: rootURL)

        // 数据库文件：Clip.store（另生成 -wal / -shm）。
        // 以后模型演进时：新增 ClipSchemaV2 + 对应 MigrationStage，登记进 ClipMigrationPlan
        // 即可走版本化迁移；当前只有一个版本，stages 为空。
        var fallback = false
        let config = ModelConfiguration(url: root.appending(path: "Clip.store"))
        do {
            container = try ModelContainer(
                for: ClipRecord.self,
                migrationPlan: ClipMigrationPlan.self,
                configurations: config)
        } catch {
            // 打开失败（磁盘故障、迁移异常等）绝不能静默换空库覆盖原数据：
            // 回退到内存容器保住本次运行可用，磁盘上的原始库文件原样保留。
            container = try! ModelContainer(
                for: ClipRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            fallback = true
            Log.store.error("SwiftData 打开失败，本次运行使用内存容器：\(String(describing: error), privacy: .public)")
        }
        // 库文件是 SwiftData 按默认 umask 建的（0644），这里统一收紧；
        // -wal / -shm 在打开时才创建，所以必须在容器建好之后做。
        Self.restrictStoreFiles(in: root)
        isEphemeralFallback = fallback
    }

    // MARK: - 磁盘访问控制

    /// 创建（或收紧）一个只有当前用户可进入的目录。
    /// 剪贴板历史默认是明文：能拦住的是同机其他账号、以及任何按路径遍历的
    /// 扫描程序，拦不住以本用户身份运行的代码（那需要加密，见 ClipStorage 顶部说明）。
    nonisolated static func createPrivateDirectory(at url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        // 备份会把明文历史复制到 Time Machine / iCloud 等本机之外的地方，
        // 而用户并没有「把剪贴板同步到云上」的预期。
        excludeFromBackup(url)
    }

    /// 把目录 / 文件排除出备份。失败不致命（旧系统或不支持的卷），所以静默跳过。
    nonisolated static func excludeFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    /// 收紧数据目录里所有已知文件的权限（数据库本体 + 三个 SQLite 伴生文件）。
    nonisolated static func restrictStoreFiles(in root: URL) {
        let manager = FileManager.default
        for name in ["Clip.store", "Clip.store-wal", "Clip.store-shm"] {
            let url = root.appending(path: name)
            guard manager.fileExists(atPath: url.path) else { continue }
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            excludeFromBackup(url)
        }
    }

    nonisolated static func isSafeBlobName(_ name: String) -> Bool {
        return !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    nonisolated func blobURL(named name: String) -> URL? {
        guard Self.isSafeBlobName(name) else { return nil }
        return blobsURL.appending(path: name)
    }

    private func ensureDirectories() {
        Self.createPrivateDirectory(at: blobsURL)
    }

    // MARK: - ModelContext

    /// 非 Sendable：只允许在 actor 内使用，正好由 actor 隔离保护。
    private var _context: ModelContext?
    private var context: ModelContext {
        if let _context { return _context }
        let context = ModelContext(container)
        // 不依赖 autosave（强杀时 autosave 不落盘），所有写操作显式 save()。
        context.autosaveEnabled = false
        _context = context
        return context
    }

    /// 显式落盘。返回是否成功。
    @discardableResult
    private func save(_ context: ModelContext, operation: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            // 保存失败时撤销本次 context 内的改动，避免下一次无关写入把一份
            // 已经失败（尤其是删除/清空）的变更意外落盘。
            context.rollback()
            Log.store.error("\(operation, privacy: .public)数据库失败：\(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - 记录 CRUD

    /// 全量读出（最近在前）。返回 Sendable 的 ClipItem——@Model 实例绝不跨出这个 actor。
    ///
    /// 返回 nil 表示「读取失败」，和「库确实是空的」是两回事：
    /// 调用方拿到 nil 时绝不能执行任何清理（删记录、删孤儿 blob），
    /// 否则一次暂时性 I/O 故障就会把整份历史连同图片文件全部删光。
    func fetchAllItems() -> [ClipItem]? {
        // 内存回退容器里看到的「空库」不是真的空：磁盘上还躺着完整历史。
        // 这里返回 nil（读取失败），调用方就会跳过所有清理动作。
        guard !isEphemeralFallback else {
            Log.store.fault("数据库回退为内存容器：本次运行不读取也不清理磁盘数据")
            return nil
        }
        let descriptor = FetchDescriptor<ClipRecord>(
            sortBy: [
                SortDescriptor(\.lastUsedAt, order: .reverse),
                SortDescriptor(\.id, order: .forward),
            ])
        do {
            return try context.fetch(descriptor).map(\.dto)
        } catch {
            Log.store.error("读取历史失败：\(String(describing: error), privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func insert(_ item: ClipItem) -> Bool {
        let context = self.context
        context.insert(ClipRecord(item))
        return save(context, operation: "写入")
    }

    /// 只更新使用状态字段。`markUsed` / `bump` / `togglePin` 不改变正文、
    /// 文件路径或富文本，避免每次粘贴都把大条目的全文/路径数组重新写一遍。
    @discardableResult
    func updateUsage(_ item: ClipItem) -> Bool {
        let context = self.context
        let id = item.id
        var descriptor = FetchDescriptor<ClipRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            if let record = try context.fetch(descriptor).first {
                record.useCount = item.useCount
                record.lastUsedAt = item.lastUsedAt
                record.isPinned = item.isPinned
            } else {
                // 内存里有、库里没有（例如上次写库失败）：补插完整条目。
                context.insert(ClipRecord(item))
            }
            return save(context, operation: "更新使用状态")
        } catch {
            context.rollback()
            Log.store.error("更新使用状态失败：\(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// 删除记录，并在数据库确认删除成功后删除对应 Blob。
    /// 不能先删文件再删库：中途失败会让数据库留下指向空文件的记录。
    @discardableResult
    func delete(ids: [ClipItem.ID], removingBlobs blobNames: [String] = []) -> Bool {
        guard !ids.isEmpty else {
            removeBlobs(blobNames)
            return true
        }
        let context = self.context
        let targets = ids
        let descriptor = FetchDescriptor<ClipRecord>(predicate: #Predicate { targets.contains($0.id) })
        do {
            let records = try context.fetch(descriptor)
            guard !records.isEmpty else {
                removeBlobs(blobNames)
                return true
            }
            for record in records {
                context.delete(record)
            }
            let saved = save(context, operation: "删除")
            if saved { removeBlobs(blobNames) }
            return saved
        } catch {
            context.rollback()
            Log.store.error("删除记录失败：\(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func deleteAll() -> Bool {
        let context = self.context
        do {
            try context.delete(model: ClipRecord.self)
            return save(context, operation: "清空")
        } catch {
            context.rollback()
            Log.store.error("清空记录失败：\(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: - 二进制负载（保留外置文件）

    @discardableResult
    func writeBlob(_ data: Data, named name: String) -> Bool {
        guard Self.isSafeBlobName(name) else { return false }
        ensureDirectories()
        let url = blobsURL.appending(path: name)
        do {
            try data.write(to: url, options: .atomic)
            // 原子写会同时生成临时文件，落盘后按 0600 收紧，和目录的 0700 对齐。
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            Log.store.error("写入 Blob 失败：\(name, privacy: .public)，\(String(describing: error), privacy: .public)")
            return false
        }
    }

    func readBlob(named name: String) -> Data? {
        guard Self.isSafeBlobName(name) else { return nil }
        return try? Data(contentsOf: blobsURL.appending(path: name))
    }

    func removeBlobs(_ names: [String]) {
        let manager = FileManager.default
        for name in names {
            guard Self.isSafeBlobName(name), let url = blobURL(named: name) else { continue }
            try? manager.removeItem(at: url)
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

    // MARK: - 维护

    /// 清空全部数据：记录清零，Blobs/ 一并删除。
    /// 注意不能删 Clip.store 本身——容器还开着，删文件会造成不可恢复的损坏。
    @discardableResult
    func eraseEverything() -> Bool {
        // 内存回退时磁盘数据库仍然存在，清空 Blob 会让下次成功打开数据库后
        // 所有图片条目都指向不存在的文件。宁可本次不清理，也不能破坏磁盘数据。
        guard !isEphemeralFallback else {
            Log.store.fault("数据库处于内存回退状态，拒绝删除磁盘 Blob")
            return false
        }
        guard deleteAll() else { return false }
        do {
            if FileManager.default.fileExists(atPath: blobsURL.path) {
                try FileManager.default.removeItem(at: blobsURL)
            }
            ensureDirectories()
        } catch {
            // 记录已经删掉了，残留的 Blob 只会占用空间，之后可由孤儿清理任务回收。
            Log.store.error("删除 Blob 目录失败：\(String(describing: error), privacy: .public)")
            ensureDirectories()
        }
        // 数据库清空已经成功，Blob 清理失败只造成空间残留，不应让调用方
        // 误以为整个操作失败并把旧记录继续留在内存中。
        return true
    }

    /// 数据目录占用的字节数（递归统计 Clip.store / -wal / -shm 与 Blobs/）。
    func diskUsage() -> Int {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += values.fileSize ?? 0
        }
        return total
    }
}
