import AppKit
import ApplicationServices
import Foundation
import Observation

/// 把内容“粘”到前台应用。模拟 ⌘V 需要辅助功能权限，没有权限时只写剪贴板。
@Observable
final class PasteService {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()

    func refreshTrust() {
        isTrusted = AXIsProcessTrusted()
    }

    /// 弹出系统授权提示。
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshTrust()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 模拟一次 ⌘V。
    func sendPaste() {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyV: CGKeyCode = 9
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }
}
