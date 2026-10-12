import AppKit
import SwiftUI

/// 菜单栏下拉面板的关闭入口。
/// MenuBarPanelController 安装状态项时赋值；面板里的动作可以先把面板收起来，再执行真正的操作。
/// 实现上会去 `cancel()` 当前展开界面会话，由系统回调后统一收起。
@MainActor
enum MenuBarPanel {
    static var dismiss: (() -> Void)?
}

extension NSColor {
    /// 生成 SwiftUI Color 代码，方便直接粘进工程。
    var clipSwiftUIColorCode: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "Color.black" }
        let red = (rgb.redComponent * 1000).rounded() / 1000
        let green = (rgb.greenComponent * 1000).rounded() / 1000
        let blue = (rgb.blueComponent * 1000).rounded() / 1000
        let alpha = (rgb.alphaComponent * 1000).rounded() / 1000
        return "Color(red: \(red), green: \(green), blue: \(blue), opacity: \(alpha))"
    }

    var clipRGBDescription: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "-" }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return "rgb(\(red), \(green), \(blue))"
    }
}
