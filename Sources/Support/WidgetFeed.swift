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
        // 文件名来自 feed.json。虽然是我们自己写的，仍然按「一个普通文件名」校验：
        // 带 `/` 或 `..` 的名字会给沙盒拼出授权范围之外的路径，多一层判断不亏。
        guard let thumb, WidgetFeed.isSafeThumbName(thumb) else { return nil }
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

    /// `clip://` 动作的校验令牌文件名（放在快照目录下，小组件有只读权限）。
    nonisolated static let urlTokenFileName = "url-token"

    /// 小组件 kind（`StaticConfiguration` 的标识）。
    /// 主 App 刷新时间线时要用它，所以放在双方共用的文件里避免拼错。
    nonisolated static let widgetKind = "ClipWidget"

    /// 真实用户 home。
    ///
    /// 沙盒进程里 `NSHomeDirectory()` / `FileManager.homeDirectoryForCurrentUser`
    /// 都会指向 `~/Library/Containers/<bundle-id>/Data`，拼不出主 App 的路径；
    /// `getpwuid` 读的是目录服务，返回的始终是真实 home（实测在沙盒内成立）。
    ///
    /// 结果缓存成静态常量：`getpwuid` 不可重入，且 `thumbURL` 每行都会调一次，
    /// 不能每次都去查目录服务。
    nonisolated static func homeDirectory() -> URL {
        cachedHome
    }

    private nonisolated static let cachedHome: URL = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

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
        return try? JSONDecoder.makeWidget().decode(WidgetFeed.self, from: data)
    }

    /// 缩略图名是否安全（只能是一个单纯的文件名）。
    nonisolated static func isSafeThumbName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }
}

// MARK: - clip:// 令牌

extension WidgetFeed {
    /// 令牌文件：`~/Library/Application Support/Clip/Widget/url-token`。
    ///
    /// 为什么需要它：`clip://` 对任何本地进程、任何网页都开放（LaunchServices 不告诉
    /// 我们调用方是谁），仅凭「有人打开了这个 URL」无法判断请求是否可信。
    /// 令牌由主 App 写在本地文件里，小组件读同一份文件拼进 URL；网页读不到本地文件，
    /// 因而无法伪造带令牌的请求。
    nonisolated static func urlTokenFileURL() -> URL {
        directoryURL().appending(path: urlTokenFileName)
    }

    /// 读令牌。小组件用；每次构造 URL 都读一次（文件很小，不缓存以免主 App 重置后旧值残留）。
    nonisolated static func readURLToken() -> String? {
        guard let data = try? Data(contentsOf: urlTokenFileURL()),
              let token = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              token.count >= 32 else { return nil }
        return token
    }

    /// 确保令牌存在（主 App 启动时调用），返回当前令牌。
    @discardableResult
    nonisolated static func ensureURLToken() -> String? {
        if let existing = readURLToken() { return existing }
        // UUID 的随机源是系统 CSPRNG，拼两次得到 64 个十六进制字符，足够当本地凭据。
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        do {
            try FileManager.default.createDirectory(at: directoryURL(), withIntermediateDirectories: true)
            try Data(token.utf8).write(to: urlTokenFileURL(), options: .atomic)
            // 0600：令牌决定「能不能驱动这个 App」，不该顺便给别的账号看。
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: urlTokenFileURL().path)
            return token
        } catch {
            // 不引 Log：这个文件同时编进主 App 和小组件，日志类型只在主 App 里。
            return nil
        }
    }
}

// MARK: - 编解码

extension JSONEncoder {
    /// 快照统一使用 ISO-8601 时间。每次返回新实例：JSONEncoder 不是 Sendable，
    /// 共享单例会在并发时间线刷新/防抖写盘时产生数据竞争。
    nonisolated static func makeWidget() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// 与编码端保持同一套时间格式。同样不共享可变解码器。
    nonisolated static func makeWidget() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
