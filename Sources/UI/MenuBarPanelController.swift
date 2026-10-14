import AppKit
import SwiftUI

/// 菜单栏下拉面板的窗口。
final class MenuBarPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 菜单栏图标 + 「展开界面」（expanded interface）控制器。
///
/// macOS 27 起，不使用 `NSMenu` 的状态项不再靠 button 的 target/action 自己 toggle，
/// 而是把面板的显示 / 收起交给系统会话（`NSStatusItemExpandedInterfaceSession`）：
///
/// - 用户点击状态项 → 系统建立会话并回调 `statusItem(_:didBegin:)` → 我们显示面板；
/// - 会话结束（再次点击状态项、按 Esc、点别处，或我们主动 cancel）→
///   系统回调 `statusItemDidEndExpandedInterfaceSession(_:animated:)` → 我们收起面板。
///
/// 这样状态项才能“参与键盘导航与菜单跟踪行为”（Apple 文档原话）。
///
/// 三条硬性约束（来自 SDK 头文件 `NSStatusItem.h` 与 Apple 官方文档）：
/// 1. **绝不能**给 `statusItem.menu` 赋值——一旦有 menu，系统按菜单处理，本代理收不到任何回调；
/// 2. 不要再给 button 设 target/action 去手动 toggle，会话模型会接管点击；
/// 3. 我们自己收起面板（点面板里的动作）时必须调用 `expandedInterfaceSession.cancel()`，
///    否则系统仍认为会话处于展开状态。注意 `didEnd` 回调里该属性已被置 nil
///    （系统在调用 `didEnd` 之前就清了它），所以收起动作只能靠 cancel 或直接 orderOut。
///
/// 参考：Apple 文档 NSStatusItemExpandedInterfaceDelegate / NSStatusItem.expandedInterfaceDelegate、
/// `NSStatusItem.h` 中 didBegin/didEnd/cancel 的说明；SDK 里 Swift 方法名为
/// `statusItem(_:didBegin:)`（`didBeginExpandedInterfaceSession:` 已被 Swift 改名）。
@MainActor
final class MenuBarPanelController: NSObject, @MainActor NSStatusItemExpandedInterfaceDelegate {

    /// 面板圆角。与窗口容器、玻璃容器共用同一个值。
    static let cornerRadius: CGFloat = 13

    private weak var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanelWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private(set) var isShown = false

    func attach(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: - 安装

    /// 创建状态项并把展开界面委托给自己。
    /// 刻意不设置 `menu`、也不设置 button 的 target/action——否则系统不会走会话回调。
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clip")
            image?.isTemplate = true
            button.image = image
            button.toolTip = L("Clip 剪贴板历史")
        }
        item.expandedInterfaceDelegate = self
        statusItem = item
        MenuBarPanel.dismiss = { [weak self] in self?.dismiss() }
    }

    // MARK: - NSStatusItemExpandedInterfaceDelegate

    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        show()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        hide()
    }

    // MARK: - 会话

    /// 由面板内的动作调用：请求系统结束当前会话，随后会收到 `didEnd` 并真正收起面板。
    func dismiss() {
        if let session = statusItem?.expandedInterfaceSession {
            session.cancel()
        } else {
            // 没有活动会话（例如 clip://menu 直接展示的兜底路径）时直接收起。
            hide()
        }
    }

    /// `clip://menu` / 快捷指令用。
    /// 会话只能由系统在用户点击状态项时开启，所以这里主要用来“关”；
    /// 未展开时直接展示一次作为兜底（此时没有会话，靠监视器收起）。
    func toggle() {
        if statusItem?.expandedInterfaceSession != nil || isShown {
            dismiss()
        } else {
            show()
        }
    }

    func syncAppearance() {
        panel?.appearance = coordinator?.settings.appearance.nsAppearance
    }

    /// 界面语言变化时刷新 AppKit 侧文案（状态项 tooltip）。
    /// 面板内容是 SwiftUI，靠对 Localization 的观察自动刷新。
    func refreshLocalization() {
        statusItem?.button?.toolTip = L("Clip 剪贴板历史")
    }

    // MARK: - 显示 / 收起

    private func show() {
        guard !isShown, let coordinator else { return }
        let panel = ensurePanel(coordinator: coordinator)
        panel.appearance = coordinator.settings.appearance.nsAppearance
        // 记下当前最前的“别的 App”，面板里的粘贴要把焦点还回去。
        coordinator.rememberFrontmostApp()
        position(panel)
        // 用 .nonactivatingPanel + makeKey：会话已由系统接管菜单栏语义，
        // 这里只让面板成为 key 以便控件可交互，不主动 activate() 抢前台应用。
        panel.makeKeyAndOrderFront(nil)
        isShown = true
        installMonitors()
    }

    private func hide() {
        guard isShown else { return }
        removeMonitors()
        panel?.orderOut(nil)
        isShown = false
    }

    // MARK: - 窗口

    private func ensurePanel(coordinator: AppCoordinator) -> MenuBarPanelWindow {
        if let panel { return panel }

        let size = MenuBarView.size
        let panel = MenuBarPanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.appearance = coordinator.settings.appearance.nsAppearance
        // 不用 .transient：它会在失活时把窗口收起来但不结束会话，
        // 之后 isShown 仍为 true，再点状态项就再也显示不出来了。收起统一交给会话与监视器。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // 与快速呼出面板一致的液态玻璃容器；圆角由外层容器裁切，去掉玻璃自带的方角阴影。
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = Self.cornerRadius
        glass.effectIsInteractive = true
        glass.frame = NSRect(origin: .zero, size: size)
        glass.autoresizingMask = [.width, .height]

        let root = MenuBarView()
            .background(PanelBackdrop())
            .environment(coordinator)
            .environment(coordinator.store)
            .environment(coordinator.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting

        let container = PanelContainerView(frame: NSRect(origin: .zero, size: size))
        container.cornerRadius = Self.cornerRadius
        container.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        panel.contentView = container

        self.panel = panel
        return panel
    }

    /// 贴着状态项正下方弹出、右对齐；越界时夹回屏幕可视区域。
    ///
    /// 状态项刚创建、系统还没完成布局时 `button.window` 可能给出一个无效矩形
    /// （曾经测到 (8, -15)），因此这里对无效锚点回退到主屏右上角。
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        let gap: CGFloat = 6

        var anchorMaxX: CGFloat?
        var anchorMinY: CGFloat?
        var anchorScreen: NSScreen?
        if let button = statusItem?.button, let buttonWindow = button.window {
            let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let isValid = rect.width > 0 && rect.height > 0
                && NSScreen.screens.contains { $0.frame.intersects(rect) }
            if isValid {
                anchorMaxX = rect.maxX
                anchorMinY = rect.minY
                anchorScreen = buttonWindow.screen
            }
        }

        let visible = (anchorScreen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(
            x: (anchorMaxX ?? visible.maxX) - size.width,
            y: (anchorMinY ?? visible.maxY) - gap - size.height
        )
        let minX = visible.minX + 8
        let minY = visible.minY + 8
        origin.x = min(max(origin.x, minX), max(minX, visible.maxX - size.width - 8))
        origin.y = min(max(origin.y, minY), max(minY, visible.maxY - size.height - 8))
        panel.setFrameOrigin(origin)
    }

    // MARK: - 点击别处收起

    private func installMonitors() {
        removeMonitors()
        // 本应用内的其它窗口（例如设置窗口）被点击时，系统不会结束会话，需要我们自己 cancel。
        // 这正是头文件里建议的 `addLocalMonitorForEventsMatchingMask:handler:` 用法。
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleLocalMouseDown(event) }
            return event
        }
        // 其它应用被点击：系统通常会结束会话，这里只是兜底（会话已结束时 cancel 是空操作）。
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        guard let window = event.window else { return }
        if window === panel { return }                              // 面板内部
        if window === statusItem?.button?.window { return }         // 状态项：交给系统 toggle
        // 比面板层级更高的窗口是菜单（SwiftUI Menu / NSMenu 弹层），属于面板内部交互，不要收起。
        if window.level.rawValue > (panel?.level.rawValue ?? 0) { return }
        dismiss()
    }
}
