import AppKit
import QuickLookUI

/// 交给 Quick Look 的预览项：`previewItemURL` 指向磁盘上的文件，
/// 标题用界面文案而不是文件名（否则标题栏会显示一长串 UUID）。
private nonisolated final class ClipPreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}

/// 用系统 Quick Look 预览当前选中的剪贴板条目（空格键）。
///
/// 不走 SwiftUI 的 `.quickLookPreview(_:)`：那个修饰符只接受 `URL`，
/// 而剪贴板条目大多不是磁盘上的文件（文本、链接、颜色都在内存里）。
/// 这里直接驱动 AppKit 的 `QLPreviewPanel`——它接受任意 `QLPreviewItem`，
/// 文本类条目就先按需落成临时文件再交给系统渲染。
///
/// 面板是「非激活」浮层的搭档：QL 面板会成为 key window 接收按键，
/// 所以这里自带一个只在预览期间生效的按键监听，处理关闭与上下切换。
@MainActor
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    @ObservationIgnored private weak var coordinator: AppCoordinator?
    /// 当前交给 QL 渲染的条目（这里一次只放一条）。
    @ObservationIgnored private var previewItems: [any QLPreviewItem] = []
    @ObservationIgnored private var monitor: Any?

    /// 是否愿意接管 QL 面板。
    /// QL 面板是沿响应链找 controller 的（见 QLPreviewPanel.h），
    /// 呼出面板 `ClipPanel` 在链上，它会先问这里要不要接管。
    var wantsControl = false

    /// 临时预览文件的目录。条目内容不可变，同一 id 只需写一次。
    private static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "ClipQuickLook", directoryHint: .isDirectory)
    }

    func attach(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    // MARK: 开关

    /// 空格键入口：开着就关，关着就开。
    func toggle(for item: ClipItem?) {
        if isVisible {
            close()
        } else {
            present(item)
        }
    }

    func present(_ item: ClipItem?) {
        guard let item, let previewItem = previewItem(for: item),
              let panel = QLPreviewPanel.shared() else { return }
        previewItems = [previewItem]
        // 先表态愿意接管，再 makeKeyAndOrderFront：面板由此沿响应链找到 ClipPanel，
        // 进而回调 beginControl 把 dataSource / delegate 挂上。
        wantsControl = true
        panel.makeKeyAndOrderFront(nil)
        installMonitor()
    }

    /// 响应链回调：正式接管面板。
    func beginControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    /// 响应链回调：交还控制权。
    func endControl(_ panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        // 用户直接点了 QL 面板的关闭按钮（不是空格/⎋ 那条路径）时，
        // 清掉监听与预览项，并把焦点还给呼出面板。
        // 两个前提：dismiss() 会先把 wantsControl 置 false（不走这里）；
        // 面板确实已经收起（避免只是失焦时误清按键监听）。
        guard wantsControl, !panel.isVisible else { return }
        wantsControl = false
        removeMonitor()
        previewItems = []
        coordinator?.panel.refocus()
    }

    /// 选中项变化时刷新预览（预览没开就什么都不做）。
    func update(for item: ClipItem?) {
        guard isVisible, let item, let previewItem = previewItem(for: item),
              let panel = QLPreviewPanel.shared() else { return }
        previewItems = [previewItem]
        panel.reloadData()
    }

    /// 关闭预览，不抢焦点。收起呼出面板时用它。
    func dismiss() {
        removeMonitor()
        wantsControl = false
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        previewItems = []
    }

    /// 关闭预览并让呼出面板重新拿回焦点。
    func close() {
        dismiss()
        coordinator?.panel.refocus()
    }

    // MARK: 按键

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
    private func handle(_ event: NSEvent) -> Bool {
        guard let coordinator else { return false }
        switch event.keyCode {
        case 49, 53: // 空格 / ⎋ 关闭
            close()
            return true
        case 125: // ↓ 下一条并刷新预览
            coordinator.store.moveSelection(by: 1)
            update(for: coordinator.store.selectedItem)
            return true
        case 126: // ↑ 上一条并刷新预览
            coordinator.store.moveSelection(by: -1)
            update(for: coordinator.store.selectedItem)
            return true
        case 36, 76: // ↩ 先收起预览，再粘贴：没有辅助功能权限时提示条要能看见
            close()
            coordinator.pasteSelected(plainText: false)
            return true
        default:
            return false
        }
    }

    // MARK: 为条目准备可预览的文件

    private func previewItem(for item: ClipItem) -> ClipPreviewItem? {
        guard let url = previewURL(for: item) else { return nil }
        return ClipPreviewItem(url: url, title: item.title)
    }

    private func previewURL(for item: ClipItem) -> URL? {
        switch item.kind {
        case .image:
            guard let blob = item.imageBlob else { return nil }
            let url = ClipStorage.shared.blobURL(named: blob)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil

        case .file:
            return (item.filePaths ?? [])
                .first { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }

        case .color:
            return colorPreviewURL(for: item) ?? textPreviewURL(for: item)

        case .text, .link:
            // 有 RTF 就优先给带格式的版本，Quick Look 能直接渲染富文本。
            if let blob = item.rtfBlob {
                let url = ClipStorage.shared.blobURL(named: blob)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
            return textPreviewURL(for: item)
        }
    }

    private func textPreviewURL(for item: ClipItem) -> URL? {
        let url = temporaryURL(named: item.id.uuidString + ".txt")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = (item.text ?? "").data(using: .utf8) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// 颜色条目给一块纯色色卡，比一串 hex 直观得多。
    private func colorPreviewURL(for item: ClipItem) -> URL? {
        guard let hex = item.text, let color = NSColor(clipHex: hex) else { return nil }
        let url = temporaryURL(named: item.id.uuidString + ".png")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let size = NSSize(width: 600, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()

        // 色卡上的文字颜色按背景亮度二选一，保证可读。
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.299 * srgb.redComponent + 0.587 * srgb.greenComponent + 0.114 * srgb.blueComponent
        let label = (item.text ?? "").uppercased() as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: luminance > 0.6 ? NSColor.black : NSColor.white,
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: (size.width - labelSize.width) / 2, y: (size.height - labelSize.height) / 2),
            withAttributes: attributes
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: url, options: .atomic)
        return url
    }

    private func temporaryURL(named name: String) -> URL {
        try? FileManager.default.createDirectory(at: Self.temporaryDirectory, withIntermediateDirectories: true)
        return Self.temporaryDirectory.appending(path: name)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewItems[index]
    }
}
