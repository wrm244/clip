import AppKit

/// 应用入口。
///
/// 菜单栏图标用 AppKit 的 NSStatusItem + NSPopover，而不是 SwiftUI 的 MenuBarExtra(.window)。
/// MenuBarExtra 给的是一个普通窗口，不是真正的 popover：里面的按钮和菜单点击经常失效
/// （窗口一失焦就被收走）。NSPopover 是系统组件，行为可靠，而且 macOS 26 起
/// 会自动采用 Liquid Glass。
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
