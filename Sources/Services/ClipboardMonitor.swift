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
    /// 延后重试期间已解析好的草稿，配它对应的 changeCount。
    ///
    /// 重试每 0.4s 一次、最多 25 次；以前每轮都重新 `PasteboardReader.read`，
    /// 而一次大图解析就是几百 MB 的拷贝（最多 25 遍，全在主线程）。changeCount
    /// 没变就说明内容没变，解析一次留住就够。
    private var deferredDraft: ClipDraft?
    private var deferredChangeCount: Int?
    /// 采集任务队列。多个 changeCount 事件必须按观察到顺序提交，否则两个内容的
    /// 哈希任务完成顺序不同，会让旧内容反而成为“最近使用”。
    private var ingestTask: Task<Void, Never>?
    private var ingestGeneration: UInt64 = 0
    private let store: ClipStore
    private let settings: ClipSettings

    init(store: ClipStore, settings: ClipSettings) {
        self.store = store
        self.settings = settings
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        // 不在这里重置 `lastChangeCount`：`start()` 是在 `store.load()` 之后调用的，
        // 历史越大这个窗口越长；如果此刻把当前值记成「已处理」，用户在这段时间里
        // 复制的东西就会被当成没有变化而永远漏采。`init` 里已经拍过一次快照，
        // 从那时到现在的内容变化就该补采。
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

    /// 等待已经排队的采集任务结束（退出前调用）。
    /// 不取消任务：最后一个剪贴板内容可能还在后台做哈希或图片转码，取消会把
    /// 用户刚复制的内容直接丢掉。
    func drain() async {
        while true {
            let generation = ingestGeneration
            guard let task = ingestTask else { return }
            await task.value
            if ingestGeneration == generation { return }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        // 注意：这里先不把 lastChangeCount 更新为 changeCount。
        // 面板是前台时要延后重试——如果此刻就记下新值，下一轮的
        // guard 会因为「没有变化」直接短路，重试永远不会发生，
        // 面板打开期间外部复制的内容就会被整段漏掉。
        // 只认本次启动生成的令牌，别人打上同名类型不算（否则采集可被任意压制）。
        let hasMarker = PasteboardReader.hasOwnMarker(pasteboard)
        let concealed = settings.ignoreConcealed && PasteboardReader.isConcealed(pasteboard)
        let clipIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier

        if settings.isMonitoringEnabled, !hasMarker, !concealed {
            // 面板打开时前台应用是 Clip 自己，这一刻的内容通常是我们自己写的；
            // 但这是临时状态，稍后重试几次，避免把真正来自其他应用的内容漏掉。
            if clipIsFrontmost {
                deferralCount += 1
                if deferralCount < 25 {
                    // 只解析一次：changeCount 没变，内容就是同一份。
                    if deferredChangeCount != changeCount {
                        deferredDraft = PasteboardReader.read(pasteboard, maxItemBytes: settings.maxItemBytes)
                        deferredChangeCount = changeCount
                    }
                    return
                }
            }
            // 重试到最后一轮（或面板已收起）：有同 changeCount 的现成草稿就直接用。
            let draft = deferredChangeCount == changeCount
                ? deferredDraft
                : PasteboardReader.read(pasteboard, maxItemBytes: settings.maxItemBytes)
            if let draft {
                lastChangeCount = changeCount
                deferralCount = 0
                deferredDraft = nil
                deferredChangeCount = nil
                Log.monitor.debug("采集到 \(draft.kind.rawValue, privacy: .public) 内容，\(draft.byteCount) 字节")
                enqueueIngest(draft)
                return
            }
            Log.monitor.debug("剪贴板内容无法识别，已跳过")
        } else if hasMarker {
            Log.monitor.debug("内容来自 Clip 自身的粘贴动作，已跳过")
        }

        deferralCount = 0
        deferredDraft = nil
        deferredChangeCount = nil
        lastChangeCount = changeCount
    }

    /// 将采集串行成一条链：哈希/图片转码可以并行准备，但真正进入 store
    /// 的顺序必须和 poll 观察到的顺序一致。
    private func enqueueIngest(_ draft: ClipDraft) {
        let previous = ingestTask
        ingestGeneration &+= 1
        let generation = ingestGeneration
        ingestTask = Task { @MainActor [weak self] in
            // 先等上一笔完全提交，避免两条内容互相覆盖/乱序 bump。
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            // 哈希是 O(内容长度) 的。传值 draft 到 detached task，避免占用主线程。
            let finalized = await Task.detached(priority: .utility) {
                PasteboardReader.finalizeHash(draft)
            }.value
            guard !Task.isCancelled else { return }
            await self.store.ingest(finalized)
            // 只有队尾任务可以清空引用；否则会把后来排入的任务误置 nil。
            if self.ingestGeneration == generation {
                self.ingestTask = nil
            }
        }
    }
}
