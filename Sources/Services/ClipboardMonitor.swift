import AppKit
import Foundation
import os

/// 轮询系统剪贴板。macOS 没有剪贴板变更通知，只能比较 changeCount；
/// 0.4s 的间隔加上 0.2s 的容差，空闲时几乎不占 CPU。
@MainActor
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    /// 前台应用是 Clip 自己时的重试计数，避免误判导致漏采。
    private var deferralCount = 0
    private let store: ClipStore
    private let settings: ClipSettings

    private(set) var isRunning = false

    init(store: ClipStore, settings: ClipSettings) {
        self.store = store
        self.settings = settings
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// 面板里发生了粘贴，跳过这一轮变化。
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let hasMarker = pasteboard.string(forType: PasteboardReader.markerType) != nil
        let concealed = settings.ignoreConcealed && PasteboardReader.isConcealed(pasteboard)
        let clipIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier

        if settings.isMonitoringEnabled, !hasMarker, !concealed {
            // 面板打开时前台应用是 Clip 自己，这一刻的内容通常是我们自己写的；
            // 但这是临时状态，稍后重试几次，避免把真正来自其他应用的内容漏掉。
            if clipIsFrontmost {
                deferralCount += 1
                if deferralCount < 25 { return }
            }
            if let draft = PasteboardReader.read(pasteboard, maxItemBytes: settings.maxItemBytes) {
                lastChangeCount = changeCount
                deferralCount = 0
                Log.monitor.debug("采集到 \(draft.kind.rawValue, privacy: .public) 内容，\(draft.byteCount) 字节")
                Task { await store.ingest(draft) }
                return
            }
            Log.monitor.debug("剪贴板内容无法识别，已跳过")
        } else if hasMarker {
            Log.monitor.debug("内容来自 Clip 自身的粘贴动作，已跳过")
        }

        deferralCount = 0
        lastChangeCount = changeCount
    }
}
