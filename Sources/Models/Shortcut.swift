import AppKit
import Carbon.HIToolbox

/// 一个全局快捷键（Carbon 键码 + 修饰键）。
struct Shortcut: Hashable, Codable, Sendable {
    struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        let rawValue: UInt8
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    var keyCode: UInt16
    var modifiers: Modifiers

    /// 默认呼出快捷键：⇧⌘V
    static let panelDefault = Shortcut(keyCode: 9, modifiers: [.command, .shift])

    /// 纯修饰键，不能单独作为快捷键。
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 从键盘事件创建，必须至少包含一个修饰键。
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        guard !mods.isEmpty, !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }
        self.init(keyCode: event.keyCode, modifiers: mods)
    }

    /// 能否注册为全局热键（需要至少一个修饰键）。
    var isValid: Bool { !modifiers.isEmpty && !Self.modifierKeyCodes.contains(keyCode) }

    /// Carbon 的修饰键掩码。
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// 形如 ⇧⌘V 的展示文本。
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 50: "\u{60}", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 114: "Help", 115: "↖", 116: "⇞",
        117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1", 123: "←", 124: "→",
        125: "↓", 126: "↑",
    ]

    static func keyName(for keyCode: UInt16) -> String {
        // 空格键的名字需要随界面语言变化，不能放进静态字典（字典在启动时只求值一次）。
        if keyCode == 49 { return L("空格") }
        if let name = keyNames[keyCode] { return name }
        return L("键 %ld", keyCode)
    }
}
