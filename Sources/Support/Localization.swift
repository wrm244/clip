import Foundation
import Observation

/// 应用支持的界面语言（用户偏好）。
///
/// 用 `system` 表示「跟随系统」，其余 case 直接存 BCP-47 标识，
/// 这样 `rawValue` 既能落 UserDefaults，也能直接喂给 Foundation 的 `Locale`。
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case spanish = "es"
    case hindi = "hi"
    case arabic = "ar"
    case bengali = "bn"

    var id: String { rawValue }

    /// 语言选择器里显示的名字。
    ///
    /// 具体语言用它自己的文字书写（endonym，Apple 在多语言选择器里的惯例），
    /// 「跟随系统」用当前界面语言显示。
    var title: String {
        switch self {
        case .system: L("跟随系统语言")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .french: "Français"
        case .spanish: "Español"
        case .hindi: "हिन्दी"
        case .arabic: "العربية"
        case .bengali: "বাংলা"
        }
    }
}

/// 解析后的具体语言。`system` 会被解析成其中之一。
enum ResolvedLanguage: String, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case spanish = "es"
    case hindi = "hi"
    case arabic = "ar"
    case bengali = "bn"

    /// 供 Foundation 格式化（日期、数字、字节数）使用的 locale。
    var locale: Locale { Locale(identifier: rawValue) }
}

/// 运行时本地化。
///
/// 字符串以「中文源文本」作为 key（Apple 的 source-language-as-key 惯例），
/// 切到其他语言时查对应语言的文案表，查不到就回退到中文源文本——中文即源语言，
/// 无需再维护一份中文表。带插值/复数的串用 printf 风格格式串做 key（例如 `"%ld 项"`）。
///
/// `@Observable` 暴露 `resolved`：SwiftUI 视图在 `body` 里调用 `L(...)` 时会读到它，
/// 于是切换语言时所有用到文案的视图都会自动重建；AppKit 侧（主菜单、状态项 tooltip）
/// 则在 `AppCoordinator.applyLanguage()` 里显式刷新。
///
/// 为什么不走 `.lproj` / String Catalog：这套界面几乎全部是代码里拼出来的
/// （模型计算属性、AppKit 菜单、toast），且设置改动要求立即生效。
/// 运行期切换 SwiftUI 的 bundle 需要重建所有 hosting 视图，成本与不确定性都更高。
@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    /// 当前生效的语言。
    private(set) var resolved: ResolvedLanguage = .simplifiedChinese

    private init() {}

    /// 应用一个用户偏好；`.system` 时按系统首选语言解析。
    func apply(_ preference: AppLanguage) {
        switch preference {
        case .system: resolved = Self.systemLanguage()
        case .simplifiedChinese: resolved = .simplifiedChinese
        case .traditionalChinese: resolved = .traditionalChinese
        case .english: resolved = .english
        case .japanese: resolved = .japanese
        case .korean: resolved = .korean
        case .french: resolved = .french
        case .spanish: resolved = .spanish
        case .hindi: resolved = .hindi
        case .arabic: resolved = .arabic
        case .bengali: resolved = .bengali
        }
    }

    /// 取一条字符串；`arguments` 非空时按 printf 风格格式化。
    func string(_ key: String, _ arguments: [CVarArg]) -> String {
        // 读一次 resolved，让 SwiftUI 的观察依赖成立（视图切语言时才能自动刷新）。
        let language = resolved
        let format = Self.table(for: language)[key] ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }

    /// 各语言的文案表。中文是源语言，没有自己的表，回退 key 本身即可。
    private static func table(for language: ResolvedLanguage) -> [String: String] {
        switch language {
        case .simplifiedChinese: [:]
        case .traditionalChinese: LocalizationTraditionalChinese.strings
        case .english: LocalizationEnglish.strings
        case .japanese: LocalizationJapanese.strings
        case .korean: LocalizationKorean.strings
        case .french: LocalizationFrench.strings
        case .spanish: LocalizationSpanish.strings
        case .hindi: LocalizationHindi.strings
        case .arabic: LocalizationArabic.strings
        case .bengali: LocalizationBengali.strings
        }
    }

    /// 系统首选语言里第一个受支持的。不支持的语言一律回退到英文。
    ///
    /// 中文要先分辨繁简：`zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` 走繁体，
    /// 其余 `zh*`（含裸 `zh`）走简体。
    static func systemLanguage() -> ResolvedLanguage {
        guard let code = Locale.preferredLanguages.first else { return .english }
        if code.hasPrefix("zh-Hant") || code.hasPrefix("zh-TW")
            || code.hasPrefix("zh-HK") || code.hasPrefix("zh-MO") {
            return .traditionalChinese
        }
        if code.hasPrefix("zh") { return .simplifiedChinese }
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("ko") { return .korean }
        if code.hasPrefix("fr") { return .french }
        if code.hasPrefix("es") { return .spanish }
        if code.hasPrefix("hi") { return .hindi }
        if code.hasPrefix("ar") { return .arabic }
        if code.hasPrefix("bn") { return .bengali }
        return .english
    }
}

/// 本地化查表 + printf 风格格式化。
///
/// key 用中文源文本；需要插入变量时用 `%ld` / `%@` 等占位符并追加参数，
/// 例如 `L("%ld 项", count)`、`L("版本 %@（%@）", version, build)`。
@MainActor
func L(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.shared.string(key, arguments)
}
