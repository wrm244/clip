import AppKit

/// 应用入口。
///
/// 菜单栏图标用 AppKit 的 NSStatusItem，下拉面板走 macOS 27 的
/// NSStatusItemExpandedInterfaceDelegate 会话（见 MenuBarPanelController），
/// 而不是 SwiftUI 的 MenuBarExtra(.window)。
/// MenuBarExtra 给的是一个普通窗口，不是真正的菜单栏面板：里面的按钮和菜单点击经常失效
/// （窗口一失焦就被收走）。会话模型让状态项参与系统的键盘导航与菜单跟踪行为，
/// 面板本体用 NSGlassEffectView 呈现。
@main
enum ClipApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
