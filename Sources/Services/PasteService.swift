import AppKit
import ApplicationServices
import Foundation
import Observation
import os

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
    ///
    /// `CGEvent.post(tap: .cghidEventTap)` 把按键投给**当前**的前台应用，所以
    /// 调用方必须把目标进程传进来：这里的检查是最后一道闸门——从请求激活到
    /// 真正按键之间，焦点可能已经被别的窗口 / 通知抢走，盲发就会把用户刚选的
    /// 密码送进聊天框或终端。返回是否真的发出了按键。
    @discardableResult
    func sendPaste(to target: pid_t?) -> Bool {
        guard AXIsProcessTrusted(), let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        if let target {
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard frontmost == target else {
                Log.panel.error("前台应用已不是粘贴目标（期望 \(target)，实际 \(frontmost ?? -1)），已取消模拟按键")
                return false
            }
        }
        let keyV: CGKeyCode = 9
        // 两个事件都要建：只发出去按下、没发抬起的话，目标应用会一直以为自己按着 ⌘V。
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            Log.panel.error("无法创建 ⌘V 键盘事件（辅助功能权限可能刚被撤销），已跳过模拟按键")
            return false
        }
        down.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.flags = .maskCommand
        up.post(tap: .cghidEventTap)
        return true
    }
}
