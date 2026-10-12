import AppKit
import Carbon

/// AppKit 生命周期与主菜单。应用以菜单栏代理（LSUIElement）方式运行。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供语言切换时重建主菜单等场景引用当前 delegate。
    static private(set) weak var shared: AppDelegate?

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
        AppDelegate.shared = self
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        MainMenu.install(target: self)
        // 菜单栏图标与「展开界面」面板（NSStatusItem + NSStatusItemExpandedInterfaceDelegate）
        // 由 AppCoordinator 持有并在 start() 里安装——它需要协调器来构建面板内容。
        AppCoordinator.shared.start()
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
            AppCoordinator.shared.menuBar.toggle()
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

    /// 由 MainMenu 的菜单项通过 target/action 调用。
    @objc
    func openSettings() {
        AppCoordinator.shared.openSettings()
    }
}

/// 应用主菜单。
///
/// 菜单标题需要本地化，所以独立成类型：应用启动和切换界面语言时都会调用 `install`。
@MainActor
enum MainMenu {
    static func install(target: AppDelegate?) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Clip")
        appMenu.addItem(
            withTitle: L("关于 Clip"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L("设置…"), action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settingsItem.target = target
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("隐藏 Clip"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("退出 Clip"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L("编辑"))
        editMenu.addItem(withTitle: L("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L("重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
