import AppKit
import Foundation
import Observation
import ServiceManagement

/// 用户偏好设置，直接落到 UserDefaults，改动即持久化。
@Observable
final class ClipSettings {
    enum Density: String, Codable, CaseIterable, Identifiable, Sendable {
        case compact
        case comfortable

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compact: "紧凑"
            case .comfortable: "宽松"
            }
        }

        var rowHeight: CGFloat {
            switch self {
            case .compact: 40
            case .comfortable: 52
            }
        }
    }

    enum Appearance: String, Codable, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "跟随系统"
            case .light: "浅色"
            case .dark: "深色"
            }
        }

        var nsAppearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    private enum Key {
        static let monitoring = "clip.monitoring.enabled"
        static let maxItems = "clip.history.maxItems"
        static let retentionDays = "clip.history.retentionDays"
        static let maxItemBytes = "clip.history.maxItemBytes"
        static let autoPaste = "clip.paste.automatic"
        static let playSound = "clip.paste.sound"
        static let ignoreConcealed = "clip.capture.ignoreConcealed"
        static let showPreview = "clip.ui.preview.v2"
        static let popupAtMouse = "clip.ui.popupAtMouse"
        static let showSourceApp = "clip.ui.sourceApp"
        static let density = "clip.ui.density"
        static let appearance = "clip.ui.appearance"
        static let panelWidth = "clip.ui.panelWidth.v2"
        static let panelHeight = "clip.ui.panelHeight.v2"
        static let hotkey = "clip.hotkey"
    }

    private let defaults = UserDefaults.standard

    /// 快捷键变化后需要重新注册全局热键。
    /// 回调不需要参与观察（设置它本身不该触发任何视图更新），与 onAppearanceChange 保持一致。
    @ObservationIgnored var onHotKeyChange: (() -> Void)?

    // MARK: 采集

    var isMonitoringEnabled: Bool = true {
        didSet { defaults.set(isMonitoringEnabled, forKey: Key.monitoring) }
    }

    var ignoreConcealed: Bool = true {
        didSet { defaults.set(ignoreConcealed, forKey: Key.ignoreConcealed) }
    }

    /// 保留策略（条数 / 天数）变化后的回调：需要立即按新策略清理已有历史。
    /// 否则用户把上限从 1000 调到 100 后，列表要等到下次复制新内容才会收缩。
    @ObservationIgnored var onRetentionChange: (() -> Void)?

    var maxItems: Int = 300 {
        didSet {
            defaults.set(maxItems, forKey: Key.maxItems)
            if maxItems != oldValue { onRetentionChange?() }
        }
    }

    /// 保留天数，0 表示永久保留。
    var retentionDays: Int = 0 {
        didSet {
            defaults.set(retentionDays, forKey: Key.retentionDays)
            if retentionDays != oldValue { onRetentionChange?() }
        }
    }

    /// 单条内容体积上限（字节）。图片编码后仍超限时会自动降采样再试，
    /// 降到下限还是超限才忽略这条内容。
    var maxItemBytes: Int = 8 * 1024 * 1024 {
        didSet { defaults.set(maxItemBytes, forKey: Key.maxItemBytes) }
    }

    // MARK: 粘贴

    var autoPaste: Bool = true {
        didSet { defaults.set(autoPaste, forKey: Key.autoPaste) }
    }

    var playSound: Bool = false {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }

    // MARK: 外观

    var density: Density = .comfortable {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }

    /// 预览面板默认关闭，保持弹窗紧凑。
    var showPreview: Bool = false {
        didSet { defaults.set(showPreview, forKey: Key.showPreview) }
    }

    var showSourceApp: Bool = true {
        didSet { defaults.set(showSourceApp, forKey: Key.showSourceApp) }
    }

    /// 弹窗贴着鼠标出现（类似 Maccy），关闭时回到屏幕上方居中。
    var popupAtMouse: Bool = true {
        didSet { defaults.set(popupAtMouse, forKey: Key.popupAtMouse) }
    }

    var appearance: Appearance = .system {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
            onAppearanceChange?()
        }
    }

    /// 外观变化后的回调：浮层窗口（呼出面板 / 菜单栏 popover）需要显式重新同步。
    @ObservationIgnored var onAppearanceChange: (() -> Void)?

    var panelWidth: Double = 460 {
        didSet { defaults.set(panelWidth, forKey: Key.panelWidth) }
    }

    /// 弹窗高度。固定值：不随条目数收缩，避免窗口上下跳动。
    var panelHeight: Double = 520 {
        didSet { defaults.set(panelHeight, forKey: Key.panelHeight) }
    }

    // MARK: 快捷键

    var hotkey: Shortcut = .panelDefault {
        didSet {
            guard hotkey != oldValue else { return }
            if let data = try? JSONEncoder().encode(hotkey) {
                defaults.set(data, forKey: Key.hotkey)
            }
            onHotKeyChange?()
        }
    }

    // MARK: 生命周期

    init() {
        let defaults = UserDefaults.standard
        isMonitoringEnabled = defaults.object(forKey: Key.monitoring) as? Bool ?? true
        ignoreConcealed = defaults.object(forKey: Key.ignoreConcealed) as? Bool ?? true
        maxItems = defaults.object(forKey: Key.maxItems) as? Int ?? 300
        retentionDays = defaults.object(forKey: Key.retentionDays) as? Int ?? 0
        maxItemBytes = defaults.object(forKey: Key.maxItemBytes) as? Int ?? 8 * 1024 * 1024
        autoPaste = defaults.object(forKey: Key.autoPaste) as? Bool ?? true
        playSound = defaults.object(forKey: Key.playSound) as? Bool ?? false
        density = Density(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .comfortable
        showPreview = defaults.object(forKey: Key.showPreview) as? Bool ?? false
        showSourceApp = defaults.object(forKey: Key.showSourceApp) as? Bool ?? true
        popupAtMouse = defaults.object(forKey: Key.popupAtMouse) as? Bool ?? true
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        panelWidth = defaults.object(forKey: Key.panelWidth) as? Double ?? 460
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? 520
        if let data = defaults.data(forKey: Key.hotkey),
           let stored = try? JSONDecoder().decode(Shortcut.self, from: data) {
            hotkey = stored
        } else {
            hotkey = .panelDefault
        }
    }

    func applyAppearance() {
        // 注意：@Observable 的属性观察器在 init 里也会触发，
        // 那时 NSApp 还没有创建，这里必须做空值保护。
        NSApp?.appearance = appearance.nsAppearance
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 设置开机自启，成功返回 nil，失败返回错误描述。
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
