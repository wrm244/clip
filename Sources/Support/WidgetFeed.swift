import Darwin
import Foundation

/// 主 App 写给桌面小组件的只读快照。
///
/// 桌面小组件是独立沙盒进程，不能直接打开主 App 的 SwiftData 库；
/// 又因为本项目是免签（ad-hoc）构建，App Group 权限会被系统直接忽略
/// （实测 trustd 报 `invalid application signature`），所以两条常规共享通道都走不通。
///
/// 这里改用第三个办法：主 App（未沙盒）把「最近若干条历史」预渲染成
/// 一份 JSON + 缩略图，写进自己数据目录下的 `Widget/`；小组件在 entitlements 里
/// 声明 `com.apple.security.temporary-exception.files.home-relative-path.read-only`
/// 只读该目录——临时例外权限在免签构建下依然会被沙盒承认。
///
/// 快照只导出展示所需的最小信息，且字符串按主 App 当前界面语言预先渲染好，
/// 这样小组件不必依赖 App 的本地化表，也不必把 SwiftData 模型搬进扩展。
/// 语言码也一并带上，供小组件格式化「相对时间」和自带的少量文案。
nonisolated struct WidgetFeed: Codable, Sendable {
    /// 主 App 生成快照时的界面语言（BCP-47）。
    var language: String
    var generatedAt: Date
    var items: [WidgetFeedItem]
}

/// 快照里的一条历史。字段与 `ClipItem` 对应，但都是小组件直接可用的展示值。
nonisolated struct WidgetFeedItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// `ClipKind` 的 rawValue（text / link / color / image / file）。
    var kind: String
    /// 已按主 App 语言渲染好的主行文本。
    var title: String
    /// 已按主 App 语言渲染好的副行文本。
    var detail: String
    var isPinned: Bool
    var lastUsedAt: Date
    /// 缩略图文件名（位于快照目录的 Thumbs/ 下），仅图片类型有。
    var thumb: String?

    /// 缩略图的绝对路径。小组件在沙盒里用真实 home 拼出来。
    var thumbURL: URL? {
        guard let thumb else { return nil }
        return WidgetFeed.thumbsDirectoryURL().appending(path: thumb)
    }

    var symbolName: String {
        switch kind {
        case "link": "link"
        case "color": "paintpalette.fill"
        case "image": "photo.fill"
        case "file": "folder.fill"
        default: "text.alignleft"
        }
    }
}

// MARK: - 磁盘位置

extension WidgetFeed {
    /// 快照目录名（位于主 App 数据目录下）。
    nonisolated static let folderName = "Widget"
    nonisolated static let fileName = "feed.json"
    nonisolated static let thumbsFolderName = "Thumbs"

    /// 真实用户 home。
    ///
    /// 沙盒进程里 `NSHomeDirectory()` / `FileManager.homeDirectoryForCurrentUser`
    /// 都会指向 `~/Library/Containers/<bundle-id>/Data`，拼不出主 App 的路径；
    /// `getpwuid` 读的是目录服务，返回的始终是真实 home（实测在沙盒内成立）。
    nonisolated static func homeDirectory() -> URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// 快照根目录：`~/Library/Application Support/Clip/Widget`。
    nonisolated static func directoryURL() -> URL {
        homeDirectory()
            .appending(path: "Library/Application Support/Clip", directoryHint: .isDirectory)
            .appending(path: folderName, directoryHint: .isDirectory)
    }

    nonisolated static func fileURL() -> URL {
        directoryURL().appending(path: fileName)
    }

    nonisolated static func thumbsDirectoryURL() -> URL {
        directoryURL().appending(path: thumbsFolderName, directoryHint: .isDirectory)
    }

    /// 读快照。失败（首次运行还没写过、权限异常等）返回 nil，由调用方显示占位。
    nonisolated static func load() -> WidgetFeed? {
        guard let data = try? Data(contentsOf: fileURL()) else { return nil }
        return try? JSONDecoder.widget.decode(WidgetFeed.self, from: data)
    }
}

// MARK: - 编解码

extension JSONEncoder {
    /// 快照统一用它编码：ISO-8601 时间，主 App / 小组件两侧一致。
    nonisolated static let widget: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    nonisolated static let widget: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
