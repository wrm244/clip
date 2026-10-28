import AppKit
import SwiftUI
import WidgetKit

// MARK: - 时间线条目

/// 小组件渲染用的时间线条目：一份快照 + 出发时间。
struct ClipEntry: TimelineEntry {
    let date: Date
    /// 主 App 生成快照时的界面语言（BCP-47）。自带文案与相对时间都按它渲染。
    let language: String
    let items: [WidgetFeedItem]
    /// `clip://` 动作的校验令牌（主 App 写在快照目录里）。
    /// 主 App 只执行带这个令牌的 URL，网页读不到本地文件，因而伪造不了。
    let linkToken: String?
}

// MARK: - Provider

struct ClipProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipEntry {
        ClipEntry(date: .now, language: WidgetText.systemLanguage, items: WidgetFeedItem.placeholders, linkToken: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ClipEntry) -> Void) {
        // 画廊 / 快照场景给样例数据，避免空态看起来像坏了。
        if context.isPreview {
            completion(ClipEntry(date: .now, language: WidgetText.systemLanguage, items: WidgetFeedItem.placeholders, linkToken: nil))
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
            // 主 App 还没写过快照（首次添加小组件 / 刚升级）时按系统语言显示，
            // 别让非中文用户先看到一屏中文。
            language: feed?.language ?? WidgetText.systemLanguage,
            items: feed?.items ?? [],
            linkToken: WidgetFeed.readURLToken()
        )
    }
}

// MARK: - Widget

struct ClipWidget: Widget {
    /// 主 App 用 `WidgetCenter.reloadTimelines(ofKind:)` 时的标识。
    /// 常量与主 App 共用，避免两边写错导致刷新不了。
    static let kind = WidgetFeed.widgetKind

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
            .widgetURL(showURL)
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
                Text(WidgetText.kindName(item.kind, language: entry.language))
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
        // 先算一次行列表：在 ForEach 内反复求值 `prefix(rowLimit)` 既啰嗦又白算。
        let rows = Array(entry.items.prefix(rowLimit))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "clipboard")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Clip")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(WidgetText.countLabel(entry.items.count, language: entry.language))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(rows) { item in
                    rowLink(item)
                    if item.id != rows.last?.id {
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
            Text(WidgetText.emptyTitle(entry.language))
                .font(.system(size: 13, weight: .semibold))
            Text(WidgetText.emptyHint(entry.language))
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

    /// 按语言缓存的相对时间格式化器。
    /// 每行每次重绘都 new 一个 `RelativeDateTimeFormatter` 很浪费（构造成本远高于一次格式化）。
    private static let timeFormatters = NSCache<NSString, RelativeDateTimeFormatter>()

    private func relativeTime(_ date: Date) -> String {
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 45 { return WidgetText.justNow(entry.language) }
        let key = entry.language as NSString
        let formatter: RelativeDateTimeFormatter
        if let cached = Self.timeFormatters.object(forKey: key) {
            formatter = cached
        } else {
            let created = RelativeDateTimeFormatter()
            created.locale = Locale(identifier: entry.language)
            created.dateTimeStyle = .named
            created.unitsStyle = .abbreviated
            Self.timeFormatters.setObject(created, forKey: key)
            formatter = created
        }
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func copyURL(_ item: WidgetFeedItem) -> URL? {
        clipURL(host: "copy", pathComponent: item.id.uuidString)
    }

    /// 点空白处打开的 URL。
    private var showURL: URL? {
        clipURL(host: "show")
    }

    /// 拼带令牌的 `clip://` 地址。
    /// 没有令牌（快照还没写过）时返回 nil：宁可不响应，
    /// 也不能留下一个「谁都能驱动 App」的入口。
    private func clipURL(host: String, pathComponent: String? = nil) -> URL? {
        guard let token = entry.linkToken, !token.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "clip"
        components.host = host
        if let pathComponent {
            components.path = "/" + pathComponent
        }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    /// 一条可点击的历史。没有令牌时退化成不可点的普通行，
    /// 不做一个「点了没反应」的 Link。
    @ViewBuilder
    private func rowLink(_ item: WidgetFeedItem) -> some View {
        if let url = copyURL(item) {
            Link(destination: url) {
                ClipWidgetRow(item: item) { thumbnail(item) }
            }
            .buttonStyle(.plain)
        } else {
            ClipWidgetRow(item: item) { thumbnail(item) }
        }
    }
}

/// 列表里的一行：图标 / 标题 + 副标题 / 时间。
private struct ClipWidgetRow<Thumb: View>: View {
    let item: WidgetFeedItem
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
/// 语言跟随主 App 写进快照的 `language`（BCP-47）。
/// 语言码归一化与主 App 的 `Localization.systemLanguage()` 保持同一套规则，
/// 认识的语言之外回退英文。
enum WidgetText {
    /// 系统首选语言（BCP-47）。主 App 还没写快照时用它兜底。
    static let systemLanguage: String = Locale.preferredLanguages.first ?? "en"

    /// 把快照里的 BCP-47 语言码归一化成文案表的 key。
    private static func code(_ language: String) -> String {
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW")
            || language.hasPrefix("zh-HK") || language.hasPrefix("zh-MO") { return "zh-Hant" }
        if language.hasPrefix("zh") { return "zh-Hans" }
        if language.hasPrefix("ja") { return "ja" }
        if language.hasPrefix("ko") { return "ko" }
        if language.hasPrefix("fr") { return "fr" }
        if language.hasPrefix("es") { return "es" }
        if language.hasPrefix("hi") { return "hi" }
        if language.hasPrefix("ar") { return "ar" }
        if language.hasPrefix("bn") { return "bn" }
        return "en"
    }

    private static func text(_ language: String, _ table: [String: String]) -> String {
        table[code(language)] ?? table["en"] ?? ""
    }

    static var galleryDescription: String {
        // 画廊描述是静态文案，拿不到快照语言，按系统偏好语言显示。
        let system = Locale.preferredLanguages.first ?? "en"
        return text(system, [
            "zh-Hans": "查看最近的剪贴板历史",
            "zh-Hant": "查看最近的剪貼板歷史",
            "en": "Your recent clipboard history",
            "ja": "最近のクリップボード履歴を表示",
            "ko": "최근 클립보드 기록 보기",
            "fr": "Votre historique de presse-papiers récent",
            "es": "Tu historial reciente del portapapeles",
            "hi": "आपका हालिया क्लिपबोर्ड इतिहास",
            "ar": "سجل الحافظة الأخير",
            "bn": "আপনার সাম্প্রতিক ক্লিপবোর্ড ইতিহাস",
        ])
    }

    static func kindName(_ kind: String, language: String) -> String {
        switch kind {
        case "link": text(language, [
            "zh-Hans": "链接", "zh-Hant": "連結", "en": "Link", "ja": "リンク", "ko": "링크",
            "fr": "Lien", "es": "Enlace", "hi": "लिंक", "ar": "رابط", "bn": "লিংক",
        ])
        case "color": text(language, [
            "zh-Hans": "颜色", "zh-Hant": "顏色", "en": "Color", "ja": "カラー", "ko": "색상",
            "fr": "Couleur", "es": "Color", "hi": "रंग", "ar": "لون", "bn": "রঙ",
        ])
        case "image": text(language, [
            "zh-Hans": "图片", "zh-Hant": "圖片", "en": "Image", "ja": "画像", "ko": "이미지",
            "fr": "Image", "es": "Imagen", "hi": "चित्र", "ar": "صورة", "bn": "ছবি",
        ])
        case "file": text(language, [
            "zh-Hans": "文件", "zh-Hant": "檔案", "en": "File", "ja": "ファイル", "ko": "파일",
            "fr": "Fichier", "es": "Archivo", "hi": "फ़ाइल", "ar": "ملف", "bn": "ফাইল",
        ])
        default: text(language, [
            "zh-Hans": "文本", "zh-Hant": "文字", "en": "Text", "ja": "テキスト", "ko": "텍스트",
            "fr": "Texte", "es": "Texto", "hi": "टेक्स्ट", "ar": "نص", "bn": "টেক্সট",
        ])
        }
    }

    static func countLabel(_ count: Int, language: String) -> String {
        switch code(language) {
        case "zh-Hans": return "\(count) 项"
        case "zh-Hant": return "\(count) 項"
        case "ja": return "\(count) 件"
        case "ko": return "\(count)개"
        case "fr": return count == 1 ? "1 élément" : "\(count) éléments"
        case "es": return count == 1 ? "1 elemento" : "\(count) elementos"
        case "hi": return "\(count) आइटम"
        case "ar": return count == 1 ? "عنصر واحد" : (count == 2 ? "عنصران" : "\(count) عناصر")
        case "bn": return count == 1 ? "1টি আইটেম" : "\(count)টি আইটেম"
        default: return count == 1 ? "1 item" : "\(count) items"
        }
    }

    static func justNow(_ language: String) -> String {
        text(language, [
            "zh-Hans": "刚刚", "zh-Hant": "剛剛", "en": "Just now", "ja": "たった今", "ko": "방금",
            "fr": "À l’instant", "es": "Ahora mismo", "hi": "अभी", "ar": "الآن", "bn": "এইমাত্র",
        ])
    }

    static func emptyTitle(_ language: String) -> String {
        text(language, [
            "zh-Hans": "暂无剪贴板历史", "zh-Hant": "尚無剪貼板記錄", "en": "No clipboard history",
            "ja": "クリップボード履歴はまだありません", "ko": "클립보드 기록이 없습니다", "fr": "Aucun historique",
            "es": "Sin historial", "hi": "कोई क्लिपबोर्ड इतिहास नहीं", "ar": "لا يوجد سجل",
            "bn": "কোনো ক্লিপবোর্ড ইতিহাস নেই",
        ])
    }

    static func emptyHint(_ language: String) -> String {
        text(language, [
            "zh-Hans": "复制任意内容后，它会出现在这里",
            "zh-Hant": "複製任何內容後，它會出現在這裡",
            "en": "Copy something and it’ll show up here",
            "ja": "コピーするとここに表示されます",
            "ko": "무언가를 복사하면 여기에 표시됩니다",
            "fr": "Copiez quelque chose et il apparaîtra ici",
            "es": "Copia algo y aparecerá aquí",
            "hi": "कुछ भी कॉपी करें, यहाँ दिख जाएगा",
            "ar": "انسخ شيئًا ما وسيظهر هنا",
            "bn": "যেকোনো কিছু কপি করুন, এখানে দেখা যাবে",
        ])
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
