import AppKit
import QuartzCore
import SwiftUI

/// 图片放大浮层（lightbox）的窗口。
///
/// 和快速呼出面板同款：无边框、非激活面板、可以成为 key window。
/// 成为 key 是为了让浮层自己拿到键盘事件（关闭用的 esc），打开时 App 已经是前台，
/// 不需要激活流程。
///
/// 除了控制器的本地事件监视器，这里再挂一层响应链兜底：监视器没兜住的 esc
/// 最终会沿响应链走到 keyDown。关闭动作必须永不落空，这是这个类最重要的性质。
final class ImageLightboxWindow: NSPanel {
    /// 关闭请求（esc 等）。
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // ⎋
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// 浮层的内容视图（窗口 contentView），同时是整块浮层的**唯一命中视图**。
///
/// 「点击 / esc 一定能关掉」这件事真正的关键就在这里，三个覆写各有官方文档依据：
///
/// 1. `needsPanelToBecomeKey` → true。官方文档 NSPanel.becomesKeyOnlyIfNeeded 原文：
///    「If the panel is a non-activating panel, then it becomes key only if the hit view
///    returns true from `needsPanelToBecomeKey`.」浮层是 `.nonactivatingPanel`，
///    而原来的命中视图是 NSHostingView（该属性默认 false）——于是浮层**永远当不上
///    key window**，而 esc 这类键盘事件只发给 key window，怎么按都没人接。
///    文档同时要求这样的子类把 `acceptsFirstResponder` 也覆写成 true。
///
/// 2. `acceptsFirstMouse` → true。官方文档 NSView.acceptsFirstMouse(for:)：
///    默认实现在非 key 窗口里返回 false——「the event simply activates the window」，
///    即第一次点击只用来激活窗口、事件被丢弃。表现就是「点一下只闪一下、关不掉」。
///    返回 true 才会让窗口「make the window key immediately and act upon the mouse-down」。
///
/// 3. `hitTest` 不往下钻，直接返回自己。浮层里没有任何可交互控件，整块玻璃就是关闭热区；
///    但也正因为 AppKit 只询问**命中视图**上面那两个属性，必须让命中视图中转到这里，
///    问的是 NSHostingView 就前功尽弃了。
///
/// 关闭取 `mouseUp` 而不是 `mouseDown`：在 mouseDown 里 orderOut，这次点击的 mouseUp
/// 会落到浮层下面的窗口上（面板里那个「点击放大」的按钮），看起来就是关了又弹回来。
final class LightboxContentView: PanelContainerView {
    /// 点击关闭请求。用点击类关闭而不是 esc：双击的第二下会被宽限期滤掉。
    var onClickDismiss: (() -> Void)?
    /// esc 关闭请求。
    var onDismiss: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var needsPanelToBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 认领这次点击，等 mouseUp 再关（见类型注释最后一段）。
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        onClickDismiss?()
    }

    override func rightMouseUp(with event: NSEvent) {
        onClickDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // ⎋
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

/// 图片放大浮层的排版常量。和其它面板一样集中定义：
/// 窗口尺寸（AppKit 侧）与内容布局（SwiftUI 侧）共用同一组数值，两边不会各算各的。
private enum LightboxMetrics {
    /// 玻璃边缘到图片 / 提示条的内边距
    static let padding: CGFloat = 12
    /// 图片与提示条之间的间距
    static let gap: CGFloat = 10
    static let pillHeight: CGFloat = 24
    /// 浮层距屏幕可视区边缘的留白
    static let screenMargin: CGFloat = 32
    /// 窗口最小尺寸：太小的图片（例如复制的图标）也要放得下底部提示条
    static let minSize = CGSize(width: 280, height: 140)
    /// 图片之外的高度开销：上下内边距 + 图片与提示条的间距 + 提示条
    static var chromeHeight: CGFloat { padding * 2 + gap + pillHeight }
}

/// 图片放大浮层：点击预览面板里的图片 → 屏幕中央弹出一张等比放大的大图。
///
/// 关闭是这个类最要紧的事——打开容易，**关不掉会把人卡死**。因此关闭做成
/// 「多通道冗余 + 幂等瞬收」，任何单一机制失灵都还有别的路可走：
///
/// 1. 命中视图（LightboxContentView）：整块浮层的点击 / esc。它同时覆写了
///    `needsPanelToBecomeKey` 与 `acceptsFirstMouse`——这是 AppKit 对
///    「非激活面板」和「非 key 窗口里的第一次点击」的两条硬性要求，
///    不满足的话浮层根本收不到点击、也当不上 key window（细节见该类型注释）；
/// 2. 本地事件监视器（installMonitor）：事件派发给窗口之前拦截，兜住 esc
///    以及「浮层开着时点了别的窗口」；
/// 3. 窗口自己的 keyDown / cancelOperation：监视器没兜住时的响应链兜底；
/// 4. 主面板一侧：点面板、面板收起（⇧⌘V、点别处、粘贴、开设置……）、菜单栏面板弹出
///    都会顺带把浮层收掉，不留孤儿窗口；面板持有 key 时按 esc 也优先关浮层、面板留着。
///
/// `dismiss()` 没有前置状态判断，也不走"淡出动画结束后再 orderOut"的延时任务——
/// 那种结构一旦被下一轮打开取消/交叠，就会留下「窗口还在、监视器已摘」的死局，
/// 表现正是图片关不掉、esc 也没反应。现在收起是瞬时的，和主面板的 hide() 一致。
@MainActor
final class ImageLightboxController {
    private weak var coordinator: AppCoordinator?
    private var window: ImageLightboxWindow?
    private var localMonitor: Any?
    /// App 失活（Cmd-Tab / 点到别的 App）时收掉浮层，避免它悬在别的 App 上。
    private var deactivationObserver: NSObjectProtocol?
    /// 打开时刻：点击关闭的宽限期以它为基准。
    private var openedAt: Date = .distantPast
    private(set) var isVisible = false

    func attach(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        guard deactivationObserver == nil else { return }
        // 浮层是独立窗口且 hidesOnDeactivate = false，App 失活不会自动收。
        // 只收浮层，主面板保持既有的"失活后仍可见"行为。
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    // MARK: - 显示

    func show(_ item: ClipItem) {
        guard item.kind == .image, let coordinator else { return }
        guard let image = ImageCache.shared.preview(for: item) else { return }

        let screen = coordinator.panel.currentScreen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = displaySize(
            for: item,
            image: image,
            within: visible,
            backingScale: screen?.backingScaleFactor ?? 1
        )

        let window = ensureWindow()
        window.appearance = coordinator.settings.appearance.nsAppearance
        window.contentView = makeContent(item: item, image: image, displaySize: size.image, windowSize: size.window)

        // 居中于面板所在的屏幕。尺寸由上面的适配保证不会越界，这里再取整一次让像素对齐。
        let origin = NSPoint(
            x: (visible.midX - size.window.width / 2).rounded(),
            y: (visible.midY - size.window.height / 2).rounded()
        )
        window.setFrame(NSRect(origin: origin, size: size.window), display: isVisible)

        // 已经开着（例如双击图片时第二下又命中按钮）只换内容、不重播淡入：
        // 既避免"关了又开"式的闪烁，也不刷新 openedAt（否则关闭宽限期会被连点无限延长）。
        guard !isVisible else { return }

        installMonitor()
        isVisible = true
        openedAt = .now

        // 和面板一样：出现给一次淡入（大块玻璃硬切太突兀），跟随「减弱动态效果」直接切换。
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = reduceMotion ? 1 : 0
        window.makeKeyAndOrderFront(nil)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }

        // 打开动作发生在主面板的鼠标事件里，makeKeyAndOrderFront 偶尔会抢不到 key。
        // 下一轮 runloop 兜底确认一次，让 esc / 点击两条关闭通道立即可用。
        Task { [weak self] in
            guard let self, self.isVisible,
                  let window = self.window, window.isVisible, !window.isKeyWindow else { return }
            window.makeKey()
        }
    }

    /// 图片展示尺寸与窗口尺寸。
    ///
    /// 规则和访达 / 预览的约定一致：**大图缩到屏幕内，小图保持原始大小**——
    /// 放大只负责"看得清"，不负责"把 32×32 的图标吹成 4K"，否则只会得到一张糊图。
    /// 窗口比图片多出的部分是上下内边距和底部提示条（LightboxMetrics.chromeHeight）。
    ///
    /// `backingScale` 是屏幕的 backingScaleFactor：`item.pixelWidth` 是**物理像素**，
    /// 而窗口 / SwiftUI 的尺寸是**点**，必须除以它才能 1 图像像素对 1 物理像素。
    /// 不除的话 Retina 上会把 bitmap 放大到 2 倍物理像素——越放大越糊。
    private func displaySize(
        for item: ClipItem,
        image: NSImage,
        within visible: NSRect,
        backingScale: CGFloat
    ) -> (image: CGSize, window: CGSize) {
        let natural: CGSize = {
            if let width = item.pixelWidth, let height = item.pixelHeight, width > 0, height > 0 {
                let backing = max(backingScale, 1)
                return CGSize(width: CGFloat(width) / backing, height: CGFloat(height) / backing)
            }
            // 没有像素尺寸时退回 NSImage 的"点"尺寸（已包含 DPI），不再除。
            return image.size
        }()

        let maxImage = CGSize(
            width: max(160, visible.width - LightboxMetrics.screenMargin * 2),
            height: max(160, visible.height - LightboxMetrics.screenMargin * 2 - LightboxMetrics.chromeHeight)
        )
        let scale = min(1, maxImage.width / natural.width, maxImage.height / natural.height)
        let display = CGSize(
            width: max(1, (natural.width * scale).rounded(.down)),
            height: max(1, (natural.height * scale).rounded(.down))
        )
        let window = CGSize(
            width: max(display.width + LightboxMetrics.padding * 2, LightboxMetrics.minSize.width),
            height: max(display.height + LightboxMetrics.chromeHeight, LightboxMetrics.minSize.height)
        )
        return (display, window)
    }

    // MARK: - 关闭

    /// 关闭浮层。刻意不判断前置状态、瞬收：多调几次、在任意阶段调都没有副作用，
    /// 唯一不能接受的结果是"没关掉"。
    func dismiss() {
        let wasVisible = isVisible
        isVisible = false
        removeMonitor()
        if let window {
            window.orderOut(nil)
            // 释放上一张大图：窗口被强持有且 isReleasedWhenClosed = false，
            // 不清 contentView 的话最后一张预览图会一直挂在窗口上（最大可达几十 MB）。
            window.contentView = nil
            window.alphaValue = 1   // 复位，下一次 show() 从 0 重新淡入
        }
        if wasVisible {
            // 焦点还给呼出面板：用户通常接着就要 ↑↓ / ↵。
            coordinator?.panel.restoreKeyFocus()
        }
    }

    /// 点击触发的关闭：双击图片时第二次点击会落在刚弹出的浮层上，不算"点任意处关闭"，
    /// 不然"双击放大"看起来就像闪了一下就没了。宽限期用系统双击间隔，
    /// 用户在「键盘」设置里把双击速度调慢也兜得住。
    func dismissByClick() {
        guard Date.now.timeIntervalSince(openedAt) > NSEvent.doubleClickInterval else { return }
        dismiss()
    }

    // MARK: - 事件

    /// 本地监视器：浮层可见期间兜住两条通道。
    ///
    /// 监视器在事件派发**之前**拿到它，所以它不依赖窗口是不是 key、也不依赖命中测试，
    /// 是命中视图之外的一道保险：
    /// - esc：一律收浮层——浮层就在屏幕上，esc 的意思只可能是关掉它，
    ///   不必判断这一刻 key 落在浮层还是面板上（面板那条链也是这么想的）；
    /// - 落在浮层上的点击：**原样放行**，交给 LightboxContentView 在 mouseUp 里关
    ///   （在 mouseDown 就 orderOut，这次点击的 mouseUp 会甩到下面那个窗口上，
    ///   面板里「点击放大」的按钮可能因此再收一次点击，表现就是关了又弹回来）；
    /// - 落在别的窗口上的点击：那是用户把注意力移开了，顺手收掉浮层，事件照常往下发。
    private func installMonitor() {
        removeMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                guard event.keyCode == 53 else { return event }
                self.dismiss()
                return nil
            }
            guard event.window !== self.window else { return event }
            self.dismissByClick()
            return event
        }
    }

    private func removeMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    // MARK: - 窗口搭建

    private func ensureWindow() -> ImageLightboxWindow {
        if let window { return window }

        let panel = ImageLightboxWindow(
            contentRect: NSRect(origin: .zero, size: LightboxMetrics.minSize),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // 外观逐次在 show() 里跟随设置钉好（和其它面板同一个理由：独立窗口不继承 NSApp.appearance）。
        panel.onDismiss = { [weak self] in self?.dismiss() }

        self.window = panel
        return panel
    }

    private func makeContent(item: ClipItem, image: NSImage, displaySize: CGSize, windowSize: CGSize) -> NSView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = PanelMetrics.cornerRadius
        glass.effectIsInteractive = true
        glass.frame = NSRect(origin: .zero, size: windowSize)
        glass.autoresizingMask = [.width, .height]

        let root = ImageLightboxView(item: item, image: image, displaySize: displaySize)
            .frame(width: windowSize.width, height: windowSize.height)
            .background(PanelBackdrop())
        let hosting = NSHostingView(rootView: root)
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting

        // 和快速面板同一套形状处理：外层容器按原生圆角裁掉玻璃自带的方角阴影。
        // 这里用 LightboxContentView：它除了形状，还是浮层唯一的命中视图与关闭热区
        // （needsPanelToBecomeKey / acceptsFirstMouse 两个关键覆写都在它身上）。
        let container = LightboxContentView(frame: NSRect(origin: .zero, size: windowSize))
        container.cornerRadius = PanelMetrics.cornerRadius
        container.autoresizingMask = [.width, .height]
        container.onDismiss = { [weak self] in self?.dismiss() }
        container.onClickDismiss = { [weak self] in self?.dismissByClick() }
        container.addSubview(glass)
        return container
    }
}

// MARK: - 内容视图

/// 浮层内容：固定展示尺寸的图片 + 底部提示胶囊。
/// 尺寸由控制器算好传进来，视图只负责摆，不再自己做适配——窗口和内容必须用同一个数，
/// 两边各算一次就会出现"图没铺满 / 玻璃多出一圈"的错位。
private struct ImageLightboxView: View {
    let item: ClipItem
    let image: NSImage
    let displaySize: CGSize

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        VStack(spacing: LightboxMetrics.gap) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: displaySize.width, height: displaySize.height)
                .clipShape(shape)
                .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                // 窗口被最小尺寸兜底撑大（或者图片很扁）时，把图居中放。
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            hintPill
        }
        .padding(LightboxMetrics.padding)
    }

    /// 底部提示：像素尺寸 + 关闭方式。放在图片下方的内边距区域里，不遮挡内容本身。
    private var hintPill: some View {
        HStack(spacing: 6) {
            Text(dimensionText)
                .monospacedDigit()
            Text("·")
                .foregroundStyle(.tertiary)
            Text(L("点击或按 esc 关闭"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: LightboxMetrics.pillHeight)
        .clipGlass(.capsule)
    }

    private var dimensionText: String {
        let width = item.pixelWidth ?? Int(image.size.width.rounded())
        let height = item.pixelHeight ?? Int(image.size.height.rounded())
        return "\(width) × \(height)"
    }
}
