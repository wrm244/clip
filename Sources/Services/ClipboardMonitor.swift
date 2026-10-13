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

    init(store: ClipStore, settings: ClipSettings) {
        self.store = store
        self.settings = settings
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        // 用未调度的 Timer 再手动加入 .common 模式：
        // 之前是 scheduledTimer（已加入 .default）又 add(.common)，同一个定时器
        // 被登记两次；改为只登记一次，意图也更清楚（.common 能在菜单追踪 /
        // 滚动时继续触发）。
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        // 注意：这里先不把 lastChangeCount 更新为 changeCount。
        // 面板是前台时要延后重试——如果此刻就记下新值，下一轮的
        // guard 会因为「没有变化」直接短路，重试永远不会发生，
        // 面板打开期间外部复制的内容就会被整段漏掉。
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
                // 哈希是 O(内容长度) 的，放到后台算；主线程只负责把剪贴板负载拷出来
                // （NSPasteboard 只能在主线程访问，这一步没法挪）。
                Task {
                    let finalized = await Task.detached(priority: .utility) {
                        PasteboardReader.finalizeHash(draft)
                    }.value
                    await store.ingest(finalized)
                }
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
