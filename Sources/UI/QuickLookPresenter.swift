import AppKit
import QuickLookUI

/// 交给 Quick Look 的预览项：`previewItemURL` 指向磁盘上的原图，
/// 标题用界面文案而不是文件名（否则标题栏会显示一长串 UUID）。
private nonisolated final class ClipPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}

/// 用系统 Quick Look 预览图片（点击预览面板里的图片触发）。
///
/// 不自己画大图浮层：Quick Look 自带缩放与 Live Text，能直接选中 / 复制图中文字。
///
/// 直接用 AppKit 的 `QLPreviewPanel`，而不是 SwiftUI 的 `.quickLookPreview`：
/// 后者在我们这种无边框非激活面板里不会沿响应链接管 dataSource，预览会停在
/// "No items selected" 且关不掉。
///
/// `QLPreviewPanel` 沿响应链找 controller（window / AppDelegate 各有一份转交，
/// 见 `PanelController` 与 `AppDelegate`）；它的控制权会在两者之间“移交”，
/// 所以本类里的 `present` / `endControl` 都刻意避开在移交过程中动 dataSource。
@MainActor
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private weak var coordinator: AppCoordinator?
    /// 当前交给 QL 渲染的条目（一次只放一条）。
    private var previewItems: [any QLPreviewItem] = []
    private var monitor: Any?

    /// 是否愿意接管 QL 面板。QL 面板沿响应链问过来时用它表态。
    var wantsControl = false

    func attach(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    // MARK: - 开关

    /// 预览一张图片。已经开着就刷新内容。
    func present(_ item: ClipItem?) {
        guard let item, let previewItem = previewItem(for: item),
              let panel = QLPreviewPanel.shared() else { return }
        previewItems = [previewItem]
        wantsControl = true

        // 先把面板显示出来，再挂 dataSource：
        // QLPreviewPanel 会在 key window 变化时沿响应链重找 controller，期间会调用
        // endControl/beginControl 做“移交”。如果在显示之前就把自己设成 dataSource，
        // 移交时触发的 endControl 会把内容清掉，预览就变成 "No items selected"。
        if !isVisible {
            panel.makeKeyAndOrderFront(nil)
            installMonitor()
        }
        // 显示以后再显式挂上：无论响应链有没有回调 beginControl（面板不是 key
        // window 时就不会），内容都在。
        if panel.dataSource !== self { panel.dataSource = self }
        if panel.delegate !== self { panel.delegate = self }
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    /// 关闭预览，不抢焦点（收起呼出面板时用它）。
    func dismiss() {
        removeMonitor()
        wantsControl = false
        previewItems = []
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
    }

    /// 关闭预览并把焦点还给呼出面板。
    func close() {
        dismiss()
        coordinator?.panel.refocus()
    }

    // MARK: - 响应链回调

    /// 正式接管面板。
    func beginControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    /// 交还控制权。
    ///
    /// 注意：控制权会在窗口 ↔ AppDelegate 之间“移交”，中途会调 endControl。
    /// 移交时面板仍在屏幕上，**绝不能在这里清 previewItems / 拆 dataSource**，
    /// 否则紧接着的 beginControl 拿到空数据就是 "No items selected"。
    /// 只有面板真的收起（isVisible == false）才做收尾。
    func endControl(_ panel: QLPreviewPanel) {
        guard !panel.isVisible else { return }
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        // 用户点了 QL 面板自带的关闭按钮（不走 esc / 空格那条路径）时收尾。
        // dismiss() 会先把 wantsControl 置 false，那种情况不用重复收。
        guard wantsControl else { return }
        wantsControl = false
        removeMonitor()
        coordinator?.panel.refocus()
    }

    // MARK: - 按键

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.window === QLPreviewPanel.shared() else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// 返回 true 表示事件已被消费。
    /// 只接管关闭键：⌘C 等要留给 Quick Look 的 Live Text（选中文字后复制）。
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command) else { return false }
        switch event.keyCode {
        case 49, 53: // 空格 / ⎋ 关闭
            close()
            return true
        default:
            return false
        }
    }

    // MARK: - 预览项

    private func previewItem(for item: ClipItem) -> ClipPreviewItem? {
        guard item.kind == .image, let blob = item.imageBlob else { return nil }
        let url = ClipStorage.shared.blobURL(named: blob)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return ClipPreviewItem(url: url, title: item.title)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        return previewItems.indices.contains(index) ? previewItems[index] : nil
    }
}
