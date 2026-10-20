import AppKit
import Carbon
import os

/// AppKit 生命周期与主菜单。应用以菜单栏代理（LSUIElement）方式运行。
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供语言切换时重建主菜单等场景引用当前 delegate。
    static private(set) weak var shared: AppDelegate?
    /// `applicationShouldTerminate` 可能被重复调用；只允许一个 drain 任务，
    /// 否则会重复 reply，甚至让 AppKit 在最后一次写入前退出。
    private var isDrainingForTermination = false

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
        // clip:// 的校验令牌放在小组件快照目录里，启动时就位：
        // 小组件拼 URL 时读同一份文件，网页读不到本地文件，所以伪造不出带令牌的请求。
        WidgetFeed.ensureURLToken()
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

    /// 退出前把排队中的数据库写入全部落盘。
    ///
    /// `ClipStore.enqueueSave` 是异步写入队列，队列若还没执行完，直接退出会丢掉最后一次复制。
    /// `applicationWillTerminate` 是同步的，塞不下 `await`，所以这里返回 `.terminateLater`，
    /// 等 drain 完再 `reply`。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isDrainingForTermination else { return .terminateLater }
        isDrainingForTermination = true
        // 先停采集，避免 drain 期间又插进新的写入。
        AppCoordinator.shared.monitor.stop()
        // 面板尺寸是去抖落盘的，退出前补一笔。
        AppCoordinator.shared.settings.persistPanelMetrics()
        Task { @MainActor in
            // 采集任务可能还在后台做哈希/转码；先等它把最后一次内容提交给 store，
            // 再 drain 数据库写入，避免退出时丢掉最后复制的一条。
            await AppCoordinator.shared.monitor.drain()
            await AppCoordinator.shared.store.drainSavesForTermination()
            await WidgetFeedWriter.shared.flush()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 正常路径已在 applicationShouldTerminate 里 drain 过；这里兜底再停一次计时器。
        AppCoordinator.shared.monitor.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: URL Scheme（clip://show / clip://copy/<id> / clip://menu / clip://settings）

    @objc
    private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value),
              url.scheme?.lowercased() == "clip" else { return }
        // 令牌校验：URL Scheme 对任何本地进程 / 网页都开放，LaunchServices 也不告诉我们
        // 调用方是谁。没有令牌就执行，意味着一个网页就能让面板弹出来抢焦点、
        // 静默改写剪贴板或打开设置窗。令牌由主 App 写在小组件目录，
        // 小组件拼进 URL；网页无法读本地文件，因而伪造不了。
        // （脚本 / 快捷指令要用这些 URL 时，从 ~/Library/Application Support/Clip/Widget/url-token 取令牌）
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value
        guard let token,
              let expected = WidgetFeed.readURLToken(),
              token == expected else {
            Log.panel.error("clip:// 请求缺少或携带了错误的令牌，已忽略：\(url.absoluteString, privacy: .public)")
            return
        }
        switch url.host()?.lowercased() {
        case "show":
            AppCoordinator.shared.showPanel()
        case "copy":
            // 桌面小组件点某一条：clip://copy/<uuid>
            if let raw = url.pathComponents.dropFirst().first, let id = UUID(uuidString: raw) {
                AppCoordinator.shared.copyFromWidget(id: id)
            } else {
                AppCoordinator.shared.showPanel()
            }
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
