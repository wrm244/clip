import Foundation
import Observation

/// 应用支持的界面语言（用户偏好）。
///
/// 用 `system` 表示「跟随系统」，其余 case 直接存 BCP-47 标识，
/// 这样 `rawValue` 既能落 UserDefaults，也能直接喂给 Foundation 的 `Locale`。
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// 语言选择器里显示的名字。
    ///
    /// 具体语言用它自己的文字书写（endonym，Apple 在多语言选择器里的惯例），
    /// 「跟随系统」用当前界面语言显示。
    var title: String {
        switch self {
        case .system: L("跟随系统语言")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }
}

/// 解析后的具体语言。`system` 会被解析成其中之一。
enum ResolvedLanguage: String, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    /// 供 Foundation 格式化（日期、数字、字节数）使用的 locale。
    var locale: Locale { Locale(identifier: rawValue) }
}

/// 运行时本地化。
///
/// 字符串以「中文源文本」作为 key（Apple 的 source-language-as-key 惯例），
/// 切到英文时查英文表，查不到就回退到中文源文本——中文即源语言，无需再维护一份中文表。
/// 带插值/复数的串用 printf 风格格式串做 key（例如 `"%ld 项"`）。
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
        case .english: resolved = .english
        }
    }

    /// 取一条字符串；`arguments` 非空时按 printf 风格格式化。
    func string(_ key: String, _ arguments: [CVarArg]) -> String {
        // 读一次 resolved，让 SwiftUI 的观察依赖成立（视图切语言时才能自动刷新）。
        let language = resolved
        let format = language == .english ? (LocalizationEnglish.strings[key] ?? key) : key
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }

    /// 系统首选语言里第一个受支持的。非中文一律回退到英文。
    static func systemLanguage() -> ResolvedLanguage {
        guard let code = Locale.preferredLanguages.first else { return .english }
        return code.hasPrefix("zh") ? .simplifiedChinese : .english
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
