import Foundation

// MARK: - 条目类型

/// 剪贴板条目的内容类型。
enum ClipKind: String, Codable, CaseIterable, Hashable, Sendable {
    case text
    case link
    case color
    case image
    case file

    var title: String {
        switch self {
        case .text: L("文本")
        case .link: L("链接")
        case .color: L("颜色")
        case .image: L("图片")
        case .file: L("文件")
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .color: "paintpalette.fill"
        case .image: "photo.fill"
        case .file: "folder.fill"
        }
    }
}

// MARK: - 分类过滤器

/// 面板顶部的分类过滤器。
enum ClipFilter: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all
    case text
    case image
    case file
    case link
    case color
    case pinned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("全部")
        case .text: L("文本")
        case .image: L("图片")
        case .file: L("文件")
        case .link: L("链接")
        case .color: L("颜色")
        case .pinned: L("已固定")
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "folder"
        case .link: "link"
        case .color: "paintpalette"
        case .pinned: "pin"
        }
    }

    /// 标为 nonisolated：后台线程批量匹配时会调用它。
    nonisolated func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: true
        case .text: item.kind == .text
        case .image: item.kind == .image
        case .file: item.kind == .file
        case .link: item.kind == .link
        case .color: item.kind == .color
        case .pinned: item.isPinned
        }
    }
}

// MARK: - 条目

/// 一条剪贴板历史记录。对象本身很轻，图片等大负载以文件形式存放在磁盘上，这里只保存文件名。
struct ClipItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var kind: ClipKind = .text

    /// 纯文本内容（文件类型时为换行分隔的路径，颜色类型时为 hex 字符串）。
    var text: String?
    /// 富文本（RTF）在 Blobs 目录中的文件名。
    var rtfBlob: String?
    /// 原始图片（PNG）在 Blobs 目录中的文件名。
    var imageBlob: String?
    /// 缩略图（JPEG）在 Blobs 目录中的文件名。
    var thumbBlob: String?

    var pixelWidth: Int?
    var pixelHeight: Int?

    /// 文件类型条目携带的路径列表。
    var filePaths: [String]?

    var byteCount: Int = 0
    var createdAt: Date = .now
    var lastUsedAt: Date = .now
    var useCount: Int = 1
    var isPinned: Bool = false

    var sourceName: String?
    var sourceBundleID: String?

    /// 用于去重的稳定哈希。
    var contentHash: String = ""

    var blobNames: [String] {
        [rtfBlob, imageBlob, thumbBlob].compactMap { $0 }
    }
}

// MARK: - 展示

extension ClipItem {
    /// 列表主行显示的标题。
    var title: String {
        switch kind {
        case .image:
            if let w = pixelWidth, let h = pixelHeight {
                return L("图片 · %ld × %ld", w, h)
            }
            return L("图片")
        case .file:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            switch names.count {
            case 0: return L("文件")
            case 1: return names[0]
            default: return L("%@ 等 %ld 个文件", names[0], names.count)
            }
        case .color:
            return text ?? L("颜色")
        case .link, .text:
            return Self.collapse(text ?? "")
        }
    }

    /// 列表次行显示的补充信息。
    var detail: String {
        switch kind {
        case .image:
            return Self.byteText(byteCount)
        case .file:
            guard let first = filePaths?.first else { return L("文件") }
            let parent = (first as NSString).deletingLastPathComponent
            return parent.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        case .link:
            if let host = URL(string: text ?? "")?.host() { return host }
            return L("链接")
        case .color:
            return L("颜色值")
        case .text:
            // 行数直接数 UTF-8 里的换行字节：\n 在 UTF-8 中恒为单字节 0x0A
            // （UTF-8 自同步，0x0A 不会出现在任何多字节序列中），
            // 比按字素簇 split 快一个数量级，且与 split("\n") 的语义一致。
            let body = text ?? ""
            let lineCount = body.utf8.lazy.filter { $0 == 0x0A }.count + 1
            let count = body.count
            return lineCount > 1 ? L("%ld 字符 · %ld 行", count, lineCount) : L("%ld 字符", count)
        }
    }

    /// 相对时间描述。
    ///
    /// 45 秒内显示「刚刚」；一周内用 Foundation 的 `RelativeDateTimeFormatter`，
    /// 它按传入的 locale 自动处理单复数与语序（“1 minute ago” / “5 minutes ago”）；
    /// 更早的条目直接显示按当前语言格式化的日期。
    var relativeTime: String {
        let seconds = Date.now.timeIntervalSince(lastUsedAt)
        if seconds < 45 { return L("刚刚") }
        let language = Localization.shared.resolved
        if seconds >= 86_400 * 7 {
            let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(language.locale)
            return lastUsedAt.formatted(style)
        }
        let formatter = Self.relativeFormatter
        formatter.locale = language.locale
        return formatter.localizedString(for: lastUsedAt, relativeTo: .now)
    }

    /// 是否命中搜索关键词（空格分词，全部命中才算匹配）。
    ///
    /// 搜索时每敲一个字会对全部条目各匹配一次，分词和文本拼接必须由调用方
    /// （ClipStore）提前做好、缓存复用，不能在这里重复做。
    /// 标为 nonisolated：批量匹配会放到后台线程执行（见 ClipStore.performSearchRebuild）。
    nonisolated func matches(keywords: some Sequence<Substring>, haystack: String) -> Bool {
        var iterator = keywords.makeIterator()
        guard let first = iterator.next() else { return true }
        if !haystack.contains(first) { return false }
        while let keyword = iterator.next() {
            if !haystack.contains(keyword) { return false }
        }
        return true
    }

    /// 条目的全文检索文本：类型标题 + 文本 + 文件路径 + 来源，已小写化。
    ///
    /// 供批量搜索专用：ClipStore 按 id 缓存后复用。比较逻辑走上面的
    /// matches(keywords:haystack:)。
    var searchHaystack: String {
        let body = searchableBody
        let title = kind.title.lowercased()
        return body.isEmpty ? title : title + "\n" + body
    }

    /// 检索文本里**不含本地化类型标题**的部分（文本 + 文件路径 + 来源），已小写化。
    ///
    /// 单独拆出来是为了能在后台线程构建搜索索引：类型标题要走 `L()`（MainActor），
    /// 只能在主线程先取好再带进后台；这里只碰纯数据，标为 nonisolated 后可随便调。
    nonisolated var searchableBody: String {
        var parts: [String] = []
        if let text { parts.append(text) }
        if let filePaths { parts.append(contentsOf: filePaths) }
        if let sourceName { parts.append(sourceName) }
        return parts.joined(separator: "\n").lowercased()
    }

    /// 把多行文本压成一行，便于列表展示。
    ///
    /// 输出上限 400 字符，只做单行摘要；先截取前 4KB 再按行合并，
    /// 避免对超长文本（单条上限 120KB）整段做字素簇扫描——
    /// 这个函数在列表每次滚动 / 选中时都会被调用。
    static func collapse(_ raw: String) -> String {
        let collapsed = raw.prefix(4_000)
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
        if collapsed.isEmpty {
            return String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        }
        return collapsed.count > 400 ? String(collapsed.prefix(400)) + "…" : collapsed
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func byteText(_ bytes: Int) -> String {
        // Formatter 的构造成本远高于一次格式化，全局缓存复用。
        // ByteCountFormatter 在 Swift 里不暴露 locale，字节单位各语言基本一致，跟随系统即可；
        // 这里仍读一下 resolved，保证只依赖该文案的视图切语言时也能刷新。
        _ = Localization.shared.resolved
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }
}
