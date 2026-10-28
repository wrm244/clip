import AppKit

/// 来源应用图标缓存。
///
/// 列表行给每条记录标出来源应用（`ClipItem.sourceName`），只有文字时要靠读名字才能
/// 分辨「这条是从浏览器来的还是从终端来的」。图标比文字更快被认出来，所以行副标题里
/// 在应用名前面加一个 12pt 的小图标。
///
/// 图标不能每帧现取：`NSWorkspace.urlForApplication(withBundleIdentifier:)` 会走
/// LaunchServices，一屏十几行、每次悬停/选中都重绘一遍，代价立刻就能感觉到。
/// 这里按 bundle id 缓存，取不到（应用已卸载、系统进程没有 bundle id）时记进
/// `missing`，避免对同一个无效 id 反复查询。
@MainActor
enum SourceAppIcon {
    private static let cache = NSCache<NSString, NSImage>()
    /// 已经查过、确认当前机器上没有对应应用的 bundle id。
    private static var missing: Set<String> = []

    /// 取来源应用图标；取不到时返回 nil，调用方回退到纯文字。
    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if missing.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        // 12pt 的行内图标按 2 倍图准备，缩放交给 SwiftUI；直接改 size 不会重画位图。
        icon.size = NSSize(width: 24, height: 24)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// 界面语言 / 主题变化后可以调一次（图标本身与应用名无关，实际很少需要）。
    static func clear() {
        cache.removeAllObjects()
        missing.removeAll()
    }
}
