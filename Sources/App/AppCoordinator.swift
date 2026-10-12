import AppKit
import Foundation
import Observation

/// 应用级协调者：持有各服务，串起采集、存储、面板与粘贴。
@Observable
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let settings: ClipSettings
    let store: ClipStore
    let monitor: ClipboardMonitor
    let paste: PasteService
    let panel: PanelController
    let menuBar: MenuBarPanelController

    private init() {
        let settings = ClipSettings()
        let store = ClipStore(settings: settings)
        self.settings = settings
        self.store = store
        self.monitor = ClipboardMonitor(store: store, settings: settings)
        self.paste = PasteService()
        self.panel = PanelController()
        self.menuBar = MenuBarPanelController()
    }

    // MARK: 启动

    func start() {
        settings.applyAppearance()
        settings.onHotKeyChange = { [weak self] in
            self?.applyHotKey()
        }
        settings.onAppearanceChange = { [weak self] in
            self?.panel.syncAppearance()
            self?.menuBar.syncAppearance()
        }
        settings.onRetentionChange = { [weak self] in
            self?.store.applyRetentionNow()
        }
        panel.attach(coordinator: self)
        menuBar.attach(coordinator: self)
        menuBar.install()
        HotKeyCenter.shared.onTrigger = { [weak self] in
            self?.togglePanel()
        }
        applyHotKey()
        // 历史加载完成后再开始采集：load 会用数据库内容整体覆盖内存列表，
        // 采集先跑的话，刚采集的条目会在 load 返回时被顶掉
        // （库里还在、列表里消失，重启才恢复）。
        Task {
            await store.load()
            monitor.start()
        }
    }

    /// 注册全局热键。
    func applyHotKey() {
        let registered = HotKeyCenter.shared.register(settings.hotkey)
        guard !registered else { return }
        store.showToast("快捷键 \(settings.hotkey.displayString) 注册失败", symbol: "exclamationmark.triangle.fill")
    }

    // MARK: 面板

    func togglePanel() {
        panel.toggle()
    }

    func showPanel() {
        paste.refreshTrust()
        panel.show()
    }

    func hidePanel() {
        panel.hide()
    }

    /// 记下当前最前的非 Clip 应用（菜单栏面板粘贴时要把焦点还回去）。
    func rememberFrontmostApp() {
        panel.rememberFrontmostApp()
    }

    func openSettings(pane: SettingsPane? = nil) {
        panel.hide(restoreFocus: false)
        SettingsWindowController.shared.show(coordinator: self, pane: pane)
    }

    // MARK: 粘贴

    /// 粘贴：写回剪贴板，关闭面板，必要时模拟 ⌘V。
    func paste(_ item: ClipItem, plainText: Bool = false) {
        Task {
            guard await PasteboardWriter.write(item, plainText: plainText) else {
                store.showToast("内容已不存在，无法粘贴", symbol: "exclamationmark.triangle.fill")
                return
            }
            if settings.playSound {
                NSSound(named: "Pop")?.play()
            }
            store.markUsed(item.id)
            finishPaste()
        }
    }

    func pasteSelected(plainText: Bool) {
        guard let item = store.selectedItem else { return }
        paste(item, plainText: plainText)
    }

    func pasteVisibleItem(at index: Int) {
        guard store.visibleItems.indices.contains(index) else { return }
        paste(store.visibleItems[index])
    }

    /// 只复制，不自动粘贴。
    func copy(_ item: ClipItem, plainText: Bool = false) {
        Task {
            guard await PasteboardWriter.write(item, plainText: plainText) else {
                store.showToast("内容已不存在，无法复制", symbol: "exclamationmark.triangle.fill")
                return
            }
            store.markUsed(item.id)
            store.showToast(plainText ? "已复制为纯文本" : "已复制", symbol: "doc.on.doc.fill")
        }
    }

    func copyString(_ text: String) {
        PasteboardWriter.writeString(text)
        store.showToast("已复制", symbol: "doc.on.doc.fill")
    }

    private func finishPaste() {
        guard settings.autoPaste else {
            // 用户主动选了「只复制」，关掉面板本身就是反馈（提示条会跟着面板一起消失）
            panel.hide()
            return
        }
        guard paste.isTrusted else {
            // 面板先不关：提示条是画在面板里的，关掉面板就什么都看不到了，
            // 用户只会觉得“按了回车没反应”。
            store.showToast(
                "已复制。自动粘贴需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能",
                symbol: "exclamationmark.triangle.fill",
                seconds: 6
            )
            return
        }
        // 必须在 hide() 之前取，关闭面板后 previousApp 可能已经不可用。
        let target = panel.previousApp
        panel.hide()
        Task { @MainActor in
            await activate(target)
            paste.sendPaste()
        }
    }

    /// 把目标应用真正切到前台，拿到键盘焦点后再发按键。
    ///
    /// 只 sleep 一个固定时长是不可靠的：激活是异步的，⌘V 常常打到了
    /// 还没失去焦点的 Clip 自己身上，用户就会觉得“粘贴没进输入框”。
    private func activate(_ app: NSRunningApplication?) async {
        guard let app, !app.isTerminated else { return }
        // Clip 是 LSUIElement 代理应用，不会自动把前台让出去，
        // 不主动 hide 的话后面发的 ⌘V 会打回 Clip 自己。
        NSApp.hide(nil)
        // 协作激活：activate 只是请求，活动应用先把激活状态让渡给目标，
        // 请求才能稳定成功（activate(options:) 自 macOS 14 起已弃用）。
        if NSApp.isActive {
            NSApp.yieldActivation(to: app)
        }
        app.activate()
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        // 目标窗口拿到键盘焦点还需要一点点时间
        try? await Task.sleep(for: .milliseconds(80))
    }

    // MARK: 其他

    func clearHistory(keepingPinned: Bool) {
        store.removeAll(keepingPinned: keepingPinned)
    }
}
