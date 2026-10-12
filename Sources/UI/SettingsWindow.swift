import AppKit
import SwiftUI

/// 独立的设置窗口。
///
/// 不用 SwiftUI 的 Settings scene：它依赖 openSettings 环境值，
/// 而快捷键面板是放在 NSHostingView 里的（不在 SwiftUI 的 scene 层级中），
/// 环境值拿不到，结果菜单栏、面板齿轮、⌘, 全都没反应。
/// 这里自己开一个标准 NSWindow：任何入口都能稳定打开，而且是真正独立的窗口。
///
/// 窗口形态按 HIG 的设置窗口规范：
/// - 标题栏透明 + fullSizeContentView，侧边栏的系统玻璃一直铺到窗口顶边，
///   红绿灯浮在玻璃上（Liquid Glass 属于「导航 / 控件层」）。
/// - 最小化 / 最大化按钮变灰，窗口尺寸跟着当前分栏走。
/// - 标题始终显示当前分栏名。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private static let frameAutosaveName = "ClipSettingsWindow.v4"

    /// 固定的窗口尺寸。设置窗口不应该在切换分栏时跳来跳去。
    private static let contentSize = NSSize(width: 720, height: 640)

    private var window: NSWindow?
    private let model = SettingsUIModel()

    private init() {}

    func show(coordinator: AppCoordinator, pane: SettingsPane? = nil) {
        if let pane { model.pane = pane }
        let window = self.window ?? makeWindow(coordinator: coordinator)
        self.window = window
        apply(pane: model.pane, to: window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(coordinator: AppCoordinator) -> NSWindow {
        let root = SettingsView(onPaneChange: { [weak self] pane in
            guard let self, let window = self.window else { return }
            apply(pane: pane, to: window)
        })
        .environment(model)
        .environment(coordinator)
        .environment(coordinator.store)
        .environment(coordinator.settings)
        .environment(coordinator.paste)

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = model.pane.title
        // 不加 .resizable：README 明确承诺设置窗口尺寸固定 720×640，
        // 只禁掉最大化按钮是挡不住用户拖边框改尺寸的。
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        // 标题栏不画文字：分栏标题写在内容里的固定头部（不会被滚动内容顶到）。
        // window.title 仍然跟着当前分栏更新，供窗口菜单 / 调度中心使用。
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        // HIG：设置窗口要把「最小化」和「最大化」按钮变灰
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        if window.setFrameUsingName(Self.frameAutosaveName) {
            // 位置沿用上次的；尺寸始终保持固定值
            window.setContentSize(Self.contentSize)
        } else {
            window.setContentSize(Self.contentSize)
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }

    /// 切换分栏只更新标题。
    /// 窗口尺寸是固定的：切换分栏时窗口大小和位置都不动，
    /// 内容多出来的部分由表单自己滚动。
    private func apply(pane: SettingsPane, to window: NSWindow) {
        window.title = pane.title
    }
}
