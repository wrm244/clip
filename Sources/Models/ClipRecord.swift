import Foundation
import SwiftData

/// SwiftData 持久化记录，字段与内存模型 `ClipItem` 一一对应。
///
/// 注意：`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 会把 `@Model` 类隐式推断成
/// 主线程隔离，导致无法在后台 actor 的 `ModelContext` 里创建和读写，
/// 因此必须显式标 `nonisolated`（Apple DTS 在开发者论坛确认的官方写法）。
/// `PersistentModel` 实例不是 Sendable，绝不能跨 actor 边界传递；
/// 跨边界只传 `ClipItem`（Sendable DTO）或凭 `id` 重新查询。
@Model
nonisolated final class ClipRecord {
    /// id 唯一。内容去重仍按现状在内存里按 contentHash 做——
    /// 这里刻意不给 contentHash 加唯一约束（空串与正常重复值都会撞约束）。
    #Unique<ClipRecord>([\.id])
    #Index<ClipRecord>([\.lastUsedAt], [\.isPinned], [\.contentHash])

    var id: UUID = UUID()
    /// 枚举存 rawValue 最稳：不引入 Codable 建模，也避免枚举演进带来的隐性迁移。
    var kindRaw: String = ClipKind.text.rawValue
    var text: String?
    var rtfBlob: String?
    var imageBlob: String?
    var thumbBlob: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var filePaths: [String]?
    var byteCount: Int = 0
    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now
    var useCount: Int = 1
    var isPinned: Bool = false
    var sourceName: String?
    var sourceBundleID: String?
    var contentHash: String = ""

    init(_ item: ClipItem) {
        id = item.id
        kindRaw = item.kind.rawValue
        text = item.text
        rtfBlob = item.rtfBlob
        imageBlob = item.imageBlob
        thumbBlob = item.thumbBlob
        pixelWidth = item.pixelWidth
        pixelHeight = item.pixelHeight
        filePaths = item.filePaths
        byteCount = item.byteCount
        createdAt = item.createdAt
        lastUsedAt = item.lastUsedAt
        useCount = item.useCount
        isPinned = item.isPinned
        sourceName = item.sourceName
        sourceBundleID = item.sourceBundleID
        contentHash = item.contentHash
    }

    /// 转回内存 DTO。kindRaw 解不出来时兜底为文本类型。
    var dto: ClipItem {
        ClipItem(
            id: id,
            kind: ClipKind(rawValue: kindRaw) ?? .text,
            text: text,
            rtfBlob: rtfBlob,
            imageBlob: imageBlob,
            thumbBlob: thumbBlob,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            filePaths: filePaths,
            byteCount: byteCount,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            useCount: useCount,
            isPinned: isPinned,
            sourceName: sourceName,
            sourceBundleID: sourceBundleID,
            contentHash: contentHash
        )
    }
}
