import AppKit
import Carbon.HIToolbox
import Foundation

/// 基于 Carbon 的全局热键。不依赖辅助功能权限，也不需要第三方库。
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var registeredShortcut: Shortcut?

    /// 热键触发时的回调。
    var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x434C4950 // 'CLIP'

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        guard shortcut.isValid else { return false }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), clipHotKeyCallback, 1, &eventType, context, &eventHandler)

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else {
            NSLog("[Clip] 注册全局热键失败：\(shortcut.displayString) (OSStatus \(status))")
            unregister()
            return false
        }
        hotKeyRef = reference
        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        registeredShortcut = nil
    }

    fileprivate func fire() {
        onTrigger?()
    }
}

/// Carbon 的 C 回调。事件在应用事件目标上派发，始终位于主线程。
private let clipHotKeyCallback: EventHandlerUPP = { _, event, context in
    guard let context, let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { center.fire() }
    return noErr
}
