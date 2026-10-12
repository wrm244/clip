import AppKit
import Observation
import QuartzCore
import QuickLookUI
import SwiftUI

/// 无边框、可成为 key window 的浮层窗口。
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Quick Look 面板沿响应链找 controller（见 QLPreviewPanel.h），
    // 窗口本身就在链上，所以在这里接下请求再转交给 QuickLookPresenter。
    // 必须写在类体里，Swift 不允许在 extension 里 override。
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { AppCoordinator.shared.quickLook.wantsControl }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { AppCoordinator.shared.quickLook.beginControl(panel) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { AppCoordinator.shared.quickLook.endControl(panel) }
    }
}

/// 管理快速呼出面板的显示、定位与键盘交互。
@Observable
@MainActor
final class PanelController {
    private(set) var isVisible = false
    /// 呼出面板前的前台应用，用于粘贴后把焦点还回去。
    private(set) var previousApp: NSRunningApplication?

    @ObservationIgnored private var panel: ClipPanel?
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private weak var coordinator: AppCoordinator?

    func attach(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// 把 App 选定的外观显式钉到面板窗口上。
    /// 无边框浮层不保证可靠继承 NSApp.appearance，而 AppKit 绘制的部分
    /// （TextField 文字色、插入点、选中高亮）是按窗口/视图外观取的，
    /// 不钉住就可能和 SwiftUI 那套环境色对不上。
    func syncAppearance() {
        panel?.appearance = coordinator?.settings.appearance.nsAppearance
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: 显示 / 隐藏

    /// 记住当前最前的「非 Clip」应用：面板 / 菜单栏面板显示时 Clip 会变成前台应用，
    /// 如果把它记下来，之后 ⌘V 就粘贴到 Clip 自己身上了（看不到任何效果）。
    func rememberFrontmostApp() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApp = front
    }

    func show() {
        guard let coordinator else { return }
        let panel = ensurePanel(coordinator: coordinator)
        syncAppearance()
        rememberFrontmostApp()

        coordinator.paste.refreshTrust()
        coordinator.store.searchText = ""
        coordinator.store.previewVisible = coordinator.settings.showPreview
        coordinator.store.selectFirst()

        let size = preferredSize(coordinator)
        if panel.frame.size != size {
            panel.setContentSize(size)
        }
        position(panel, atMouse: coordinator.settings.popupAtMouse)

        NSApp.activate()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        installMonitors()
    }

    func hide(restoreFocus: Bool = true) {
        guard let panel else { return }
        removeMonitors()
        // 一并收起 Quick Look，否则它会留在屏幕上并继续持有按键。
        coordinator?.quickLook.dismiss()
        panel.orderOut(nil)
        if isVisible {
            isVisible = false
            if restoreFocus, let app = previousApp, !app.isTerminated {
                // 协作激活：面板是 key window 时 Clip 还是活动应用，
                // 先把激活状态让渡给目标，activate 请求才能稳定成功
                if NSApp.isActive {
                    NSApp.yieldActivation(to: app)
                }
                app.activate()
            }
        }
    }

    /// 让呼出面板重新成为 key window。
    /// 给 Quick Look 关闭后用：QL 面板是独立的 key window，关掉后焦点要还回来。
    func refocus() {
        guard isVisible, let panel else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: 窗口搭建

    private func ensurePanel(coordinator: AppCoordinator) -> ClipPanel {
        if let panel { return panel }

        let size = NSSize(width: coordinator.settings.panelWidth, height: coordinator.settings.panelHeight)
        let panel = ClipPanel(   // 首次创建用设定尺寸，show() 里会按内容收紧
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
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.appearance = coordinator.settings.appearance.nsAppearance
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        // macOS 26 引入的 Liquid Glass 容器，macOS 27 起支持交互反馈
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = PanelMetrics.cornerRadius
        glass.effectIsInteractive = true
        // 这里刻意不设 tintColor：
        // 玻璃的通透程度由系统「外观 → 液态玻璃（通透/色调）」统一决定
        // （全局偏好里的 NSGlassTintAmount 就是它），NSGlassEffectView 会自动跟随。
        // tintColor 是用来把玻璃往某个色相上染的（比如品牌色），
        // 拿它去压明度等于覆盖用户自己的选择，属于用错 API。
        // 文字对比度改用系统语义色 + 玻璃自带的 vibrancy 来保证。
        glass.frame = NSRect(origin: .zero, size: size)
        glass.autoresizingMask = [.width, .height]

        let root = ClipPanelView()
            .background(PanelBackdrop())
            .environment(coordinator)
            .environment(coordinator.store)
            .environment(coordinator.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        // 注意：不要动 hosting.sizingOptions。设成 [] 会让 hosting view 不再给
        // 内容分配尺寸，整个面板就只剩一块空白玻璃（实测过）。
        // 内容"顶高窗口"的问题改用 ClipPanelView 根节点的固定 frame 解决。
        glass.contentView = hosting

        // 外层容器定义窗口形状：原生圆角 + 裁掉玻璃自带的那圈柔和阴影，
        // 否则那圈阴影会落在窗口四角，看起来就是圆角外的方形边框。
        let container = PanelContainerView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        panel.contentView = container

        self.panel = panel
        return panel
    }

    /// 弹窗尺寸：**高度固定**为设定值，展开预览时只向右加宽。
    ///
    /// 之前高度按条目数收缩（min(上限, max(200, 内容))），再加下一条说的
    /// Auto Layout 顶高，呼出/收起/预览开合时窗口会上下跳。高度是用户设定的，
    /// 就该由设定说了算，内容多少只影响列表内部滚动。
    private func preferredSize(_ coordinator: AppCoordinator) -> NSSize {
        let settings = coordinator.settings
        return NSSize(
            width: PanelMetrics.panelWidth(
                listWidth: settings.panelWidth,
                previewing: coordinator.store.previewVisible
            ),
            height: settings.panelHeight
        )
    }

    /// 展开 / 收起预览：给窗口宽度做一次动画。
    ///
    /// 动效只做在窗口上，内容不自己跑动画：ClipPanelView 从窗口的**实时宽度**
    /// 反推展开进度，所以动画的每一帧内容和窗口都是同一个宽度。
    /// 旧版是「内容跑弹簧动画 + 窗口瞬间变宽」，两者不同步才会看起来像列表在回弹，
    /// 当时干脆把动效整个去掉了；现在两边天然同帧，可以放心加回来。
    /// → / ⌘Y 是高频操作，时长按面板的节奏取短一点（PanelMetrics.previewToggleDuration）。
    func setPreview(_ visible: Bool) {
        guard let coordinator, coordinator.store.previewVisible != visible else { return }
        coordinator.store.previewVisible = visible
        resizeForCurrentState(animated: true)
    }

    /// 展开 / 收起预览时调整窗口大小。
    /// 关键：保持左上角不动，只向右、向下扩展，这样列表内容不会跳动。
    func resizeForCurrentState(animated: Bool = false) {
        guard let coordinator, let panel else { return }
        let size = preferredSize(coordinator)
        guard panel.frame.size != size else { return }

        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size = size
        frame.origin.y = topEdge - size.height
        let target = clampedToScreen(frame, on: panel.screen)

        // 打开「减弱动态效果」时直接切换，和视图里其它动效的处理保持一致。
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelMetrics.previewToggleDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// 把窗口矩形夹在屏幕可视区域内。
    private func clampedToScreen(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var result = frame
        let minX = visible.minX + 8
        let minY = visible.minY + 8
        result.origin.x = min(max(result.origin.x, minX), max(minX, visible.maxX - result.width - 8))
        result.origin.y = min(max(result.origin.y, minY), max(minY, visible.maxY - result.height - 8))
        return result
    }

    /// 默认贴着鼠标弹出（类似 Maccy）；也可以回到屏幕上方居中的位置。
    private func position(_ panel: NSPanel, atMouse: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let gap: CGFloat = 8
        var origin = NSPoint.zero

        if atMouse {
            // 优先落在光标右下方：光标在面板左上角外侧，不会挡住第一行
            origin.x = mouse.x + gap
            origin.y = mouse.y - gap - size.height
            if origin.x + size.width > visible.maxX {       // 右边放不下就翻到光标左侧
                origin.x = mouse.x - gap - size.width
            }
            if origin.y < visible.minY {                    // 下方放不下就放到光标上方
                origin.y = mouse.y + gap
            }
        } else {
            origin.x = visible.midX - size.width / 2
            origin.y = visible.maxY - size.height - max(60, visible.height * 0.14)
        }

        // 兜底：无论如何都不越出屏幕可视区域
        let target = clampedToScreen(
            NSRect(origin: NSPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size),
            on: screen
        )
        panel.setFrameOrigin(target.origin)
    }

    // MARK: 键盘与鼠标监视器

    private func installMonitors() {
        removeMonitors()
        // keyDown 走键盘操作；leftMouseDown 只是顺手按落点更新「背景拖动窗口」的开关
        // （见 updateDragPolicy），事件本身照常往下发。
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.type == .leftMouseDown {
                self.updateDragPolicy(at: event.locationInWindow)
                return event
            }
            return self.handle(event) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                // 点面板外面 = 用户想去点别的 App。这里绝不能 restoreFocus：
                // 那会把焦点强行抢回「呼出面板前的 App」，和用户刚点的窗口打架。
                // 只把面板收起来，焦点交给这次点击自己决定。
                self?.hide(restoreFocus: false)
            }
        }
    }

    /// 预览窗格是「选文字」的区域，不是「拖窗口」的区域。
    ///
    /// 面板开着 `isMovableByWindowBackground`，而 SwiftUI 的文字选择视图
    /// （`AppKitTextInteractionView`）和普通 NSView 一样返回 `mouseDownCanMoveWindow == true`
    /// ——按钮、文本框、滚动视图这些真正的 AppKit 控件都是 false，所以只有它中招。
    /// 结果就是拖拽被 AppKit 当成「拖动窗口背景」吃掉，预览里的文字永远选不中。
    ///
    /// 不能靠悬停判断：面板可能正好出现在光标底下，不产生 hover 事件。
    /// 改成在 leftMouseDown 的本地监视器里按落点决定——监视器早于窗口处理这个事件
    /// （实测：窗口读到的一定是刚设好的值），所以这一拖就是文字选择。
    private func updateDragPolicy(at point: NSPoint) {
        guard let panel, let coordinator else { return }
        let listWidth = PanelMetrics.listWidth(
            at: PanelMetrics.previewProgress(
                windowWidth: panel.frame.width,
                listWidth: coordinator.settings.panelWidth
            ),
            listWidth: coordinator.settings.panelWidth
        )
        // 预览窗格（含它左侧那条分隔线）里不拖动窗口，其余地方保持「拖背景移动面板」。
        panel.isMovableByWindowBackground = point.x < listWidth
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

    /// 返回 true 表示事件已被消费。
    private func handle(_ event: NSEvent) -> Bool {
        guard let coordinator else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let isReturn = event.keyCode == 36 || event.keyCode == 76

        if option, !command, isReturn {
            coordinator.pasteSelected(plainText: true)
            return true
        }
        if !command, !option {
            switch event.keyCode {
            case 53: // ⎋
                hide()
                return true
            case 125: // ↓
                coordinator.store.moveSelection(by: 1)
                return true
            case 126: // ↑
                coordinator.store.moveSelection(by: -1)
                return true
            case 49: // 空格：Quick Look 预览
                // 搜索框里有内容时把空格留给文本输入
                guard coordinator.store.searchText.isEmpty else { return false }
                coordinator.toggleQuickLook()
                return true
            case 124, 123: // → 展开预览 / ← 收起预览
                // 搜索框里有内容时把左右键留给光标编辑
                guard coordinator.store.searchText.isEmpty else { return false }
                setPreview(event.keyCode == 124)
                return true
            case 36, 76: // ↩
                coordinator.pasteSelected(plainText: false)
                return true
            default:
                return false
            }
        }
        guard command else { return false }
        switch event.keyCode {
        case 35: // ⌘P
            coordinator.store.togglePinSelected()
            return true
        case 16: // ⌘Y
            setPreview(!coordinator.store.previewVisible)
            return true
        case 51: // ⌘⌫
            coordinator.store.removeSelected()
            return true
        case 43: // ⌘,
            coordinator.openSettings()
            return true
        default:
            break
        }
        if let characters = event.charactersIgnoringModifiers, let index = Int(characters), (1...9).contains(index) {
            coordinator.pasteVisibleItem(at: index - 1)
            return true
        }
        return false
    }
}
