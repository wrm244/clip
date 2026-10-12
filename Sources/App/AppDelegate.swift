import AppKit
import Carbon
import SwiftUI

/// AppKit 生命周期与主菜单。应用以菜单栏代理（LSUIElement）方式运行。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 同一份数据目录只能有一个写入者：如果磁盘上存在另一份 Clip 副本已经在跑，
        // 就直接让它接管，避免两个进程互相写坏同一个 SwiftData 数据库。
        let me = ProcessInfo.processInfo.processIdentifier
        // 只有「另一份副本」（bundle 路径不同）才需要让位：快速重启时
        // LaunchServices 可能还留着刚退出实例的记录，那种情况必须继续启动。
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.river.Clip")
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        if let existing = others.first(where: { $0.bundleURL != Bundle.main.bundleURL }) {
            existing.activate()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        installMainMenu()
        AppCoordinator.shared.start()
        installStatusItem()
    }

    // MARK: 菜单栏图标（NSStatusItem + NSPopover）

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// 菜单栏图标 + 下拉面板。
    ///
    /// 用 AppKit 而不是 SwiftUI 的 MenuBarExtra(.window)：后者给的是普通窗口，
    /// 一失焦就被收走，里面的按钮和菜单点不动。NSPopover 是系统组件，
    /// 行为可靠（.transient 点外面自动关），并且会自动使用 Liquid Glass。
    private func installStatusItem() {
        let coordinator = AppCoordinator.shared

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clip")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggleMenuBarPanel(_:))
            button.toolTip = "Clip 剪贴板历史"
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = MenuBarView.size
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environment(coordinator)
                .environment(coordinator.store)
                .environment(coordinator.settings)
        )
        self.popover = popover
        MenuBarPanel.dismiss = { [weak popover] in popover?.performClose(nil) }
    }

    @objc
    private func toggleMenuBarPanel(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        // NSPopover 的窗口不跟随 NSApp.appearance：App 设成深色时它仍然是浅色的
        // （实测深色外观下面板背景 235、深色文字）。必须在显示前显式同步一次外观。
        popover.appearance = AppCoordinator.shared.settings.appearance.nsAppearance
        // 先记住当前最前的「别的 App」：从菜单栏面板粘贴时要把焦点还回去
        AppCoordinator.shared.rememberFrontmostApp()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // SwiftData 每笔写操作都已显式 save()，退出时没有需要补写的数据。
        AppCoordinator.shared.monitor.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: URL Scheme（clip://show / clip://toggle / clip://settings）

    @objc
    private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else { return }
        switch url.host() {
        case "show":
            AppCoordinator.shared.showPanel()
        case "menu":
            toggleMenuBarPanel(nil)
        case "preview":
            // 直接切换右侧预览面板，方便用快捷指令 / 脚本驱动
            AppCoordinator.shared.panel.setPreview(!AppCoordinator.shared.store.previewVisible)
        case "settings":
            // clip://settings/appearance 可以直接定位到某一栏
            let pane = url.pathComponents.dropFirst().first.flatMap(SettingsPane.init(rawValue:))
            AppCoordinator.shared.openSettings(pane: pane)
        default:
            AppCoordinator.shared.togglePanel()
        }
    }

    // MARK: 主菜单

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Clip")
        appMenu.addItem(
            withTitle: "关于 Clip",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Clip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Clip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc
    private func openSettings() {
        AppCoordinator.shared.openSettings()
    }
}
