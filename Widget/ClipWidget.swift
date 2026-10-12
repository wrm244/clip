import AppKit
import SwiftUI
import WidgetKit

// MARK: - 时间线条目

/// 小组件渲染用的时间线条目：一份快照 + 出发时间。
struct ClipEntry: TimelineEntry {
    let date: Date
    let language: String
    let items: [WidgetFeedItem]

    /// 快照里没有相对时间的实时值，小组件按语言自己算。
    var isChinese: Bool { language.hasPrefix("zh") }
}

// MARK: - Provider

struct ClipProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipEntry {
        ClipEntry(date: .now, language: "zh-Hans", items: WidgetFeedItem.placeholders)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ClipEntry) -> Void) {
        // 画廊 / 快照场景给样例数据，避免空态看起来像坏了。
        if context.isPreview {
            completion(ClipEntry(date: .now, language: "zh-Hans", items: WidgetFeedItem.placeholders))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ClipEntry>) -> Void) {
        let entry = currentEntry()
        // 主 App 有变化时会主动 reload；这里再兜一个 5 分钟的兜底刷新，
        // 让「相对时间」不至于长期停留在旧值。
        let policy: TimelineReloadPolicy = .after(.now.addingTimeInterval(300))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func currentEntry() -> ClipEntry {
        let feed = WidgetFeed.load()
        return ClipEntry(
            date: .now,
            language: feed?.language ?? "zh-Hans",
            items: feed?.items ?? []
        )
    }
}

// MARK: - Widget

struct ClipWidget: Widget {
    /// 主 App 用 `WidgetCenter.reloadTimelines(ofKind:)` 时的标识。
    static let kind = "ClipWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ClipProvider()) { entry in
            ClipWidgetView(entry: entry)
        }
        .configurationDisplayName("Clip")
        .description(Text(verbatim: WidgetText.galleryDescription))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - 视图

struct ClipWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClipEntry

    /// 每个尺寸能容纳的行数（大号留一行做头部）。
    private var rowLimit: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        case .systemLarge: 6
        default: 9
        }
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color(nsColor: .controlBackgroundColor)
            }
            // 点空白处打开呼出面板。
            .widgetURL(URL(string: "clip://show"))
    }

    @ViewBuilder
    private var content: some View {
        if entry.items.isEmpty {
            emptyState
        } else if family == .systemSmall {
            smallContent
        } else {
            listContent
        }
    }

    // MARK: 小尺寸：突出最近一条

    private var smallContent: some View {
        let item = entry.items[0]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(WidgetText.kindName(item.kind, chinese: entry.isChinese))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if item.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
            thumbnail(item)
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(thumbLines)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(relativeTime(item.lastUsedAt))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var thumbLines: Int { entry.items[0].thumb != nil ? 1 : 2 }

    // MARK: 中 / 大尺寸：列表

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Clip")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(WidgetText.countLabel(entry.items.count, chinese: entry.isChinese))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(entry.items.prefix(rowLimit)) { item in
                    Link(destination: copyURL(item)) {
                        ClipWidgetRow(item: item, chinese: entry.isChinese) { thumbnail(item) }
                    }
                    .buttonStyle(.plain)
                    if item.id != entry.items.prefix(rowLimit).last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 空态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "clipboard")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tint)
            Text(WidgetText.emptyTitle(entry.isChinese))
                .font(.system(size: 13, weight: .semibold))
            Text(WidgetText.emptyHint(entry.isChinese))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 工具

    @ViewBuilder
    private func thumbnail(_ item: WidgetFeedItem) -> some View {
        if item.kind == "image", let url = item.thumbURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: family == .systemSmall ? 72 : 26)
                .frame(width: family == .systemSmall ? nil : 26)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 45 { return WidgetText.justNow(entry.isChinese) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: entry.language)
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func copyURL(_ item: WidgetFeedItem) -> URL {
        URL(string: "clip://copy/\(item.id.uuidString)") ?? URL(string: "clip://show")!
    }
}

/// 列表里的一行：图标 / 标题 + 副标题 / 时间。
private struct ClipWidgetRow<Thumb: View>: View {
    let item: WidgetFeedItem
    let chinese: Bool
    @ViewBuilder let thumb: () -> Thumb

    var body: some View {
        HStack(spacing: 8) {
            if item.kind == "image" {
                thumb()
            } else {
                Image(systemName: item.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

// MARK: - 自带文案

/// 小组件只用到极少量文案，不值得搬整套本地化表进来；
/// 语言跟随主 App 写进快照的 `language`。
enum WidgetText {
    static var galleryDescription: String {
        let chinese = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        return chinese ? "查看最近的剪贴板历史" : "Your recent clipboard history"
    }

    static func kindName(_ kind: String, chinese: Bool) -> String {
        switch kind {
        case "link": chinese ? "链接" : "Link"
        case "color": chinese ? "颜色" : "Color"
        case "image": chinese ? "图片" : "Image"
        case "file": chinese ? "文件" : "File"
        default: chinese ? "文本" : "Text"
        }
    }

    static func countLabel(_ count: Int, chinese: Bool) -> String {
        chinese ? "\(count) 项" : (count == 1 ? "1 item" : "\(count) items")
    }

    static func justNow(_ chinese: Bool) -> String { chinese ? "刚刚" : "Just now" }
    static func emptyTitle(_ chinese: Bool) -> String { chinese ? "暂无剪贴板历史" : "No clipboard history" }
    static func emptyHint(_ chinese: Bool) -> String {
        chinese ? "复制任意内容后，它会出现在这里" : "Copy something and it’ll show up here"
    }
}

// MARK: - 预览样例

extension WidgetFeedItem {
    static let placeholders: [WidgetFeedItem] = [
        WidgetFeedItem(id: UUID(), kind: "text", title: "会议纪要：下周迭代排期", detail: "128 字符 · 4 行", isPinned: true, lastUsedAt: .now, thumb: nil),
        WidgetFeedItem(id: UUID(), kind: "link", title: "developer.apple.com/design", detail: "developer.apple.com", isPinned: false, lastUsedAt: .now.addingTimeInterval(-600), thumb: nil),
        WidgetFeedItem(id: UUID(), kind: "image", title: "图片 · 2560 × 1600", detail: "1.2 MB", isPinned: false, lastUsedAt: .now.addingTimeInterval(-1800), thumb: nil),
        WidgetFeedItem(id: UUID(), kind: "color", title: "#3B82F6", detail: "颜色值", isPinned: false, lastUsedAt: .now.addingTimeInterval(-3600), thumb: nil),
    ]
}
