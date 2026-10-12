import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把历史条目写回系统剪贴板。
///
/// NSPasteboard 不是线程安全的（Apple 已确认只能在主线程使用），
/// 所以剪贴板本身的读写全部留在主线程；唯一的大开销——图片的 TIFF
/// 兼容转码（解码整张 PNG 再编码）——放到后台用 ImageIO 完成，
/// 否则粘贴大图时主线程会阻塞几百毫秒，面板明显延迟才关闭。
///
/// 顺序上先在后台取齐所有数据，最后再 clearContents + write：
/// 如果先清空剪贴板再去 await 读盘，等待窗口内剪贴板是空的，
/// 用户此刻复制的内容会被吞掉。
enum PasteboardWriter {
    /// 写回一条历史记录。plainText 为 true 时只写纯文本（⌥↩）。
    /// 图片没有「纯文本形态」，⌥↩ 对图片仍按图片写回，避免出现
    /// 「按了回车、面板关了、剪贴板却没变」的静默失败。
    ///
    /// 返回是否真的写入了内容。文件缺失（例如 Blobs 被外部清理）时返回 false，
    /// 调用方据此取消后续的 ⌘V，否则会把剪贴板里的**旧内容**粘出去。
    @discardableResult
    static func write(_ item: ClipItem, plainText: Bool) async -> Bool {
        switch item.kind {
        case .image:
            guard let name = item.imageBlob,
                  let png = await ClipStorage.shared.readBlob(named: name) else { return false }
            // PNG → TIFF 只为兼容少数只认 TIFF 的老应用；解码与编码都在后台
            let tiff = await Task.detached(priority: .userInitiated) {
                Self.makeTIFFData(from: png)
            }.value
            let itemBox = NSPasteboardItem()
            itemBox.setData(png, forType: .png)
            if let tiff {
                itemBox.setData(tiff, forType: .tiff)
            }
            itemBox.setString(item.id.uuidString, forType: PasteboardReader.markerType)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([itemBox])
            return true

        case .file where !plainText:
            let paths = item.filePaths ?? []
            guard !paths.isEmpty else { return false }
            // 与访达的多文件复制结构一致：每个文件一个 pasteboard item。
            // 每个 item 都必须打 marker，否则这次写回会被 monitor
            // 当成新内容再采集一遍（条目被莫名 bump 一次）。
            let boxes: [NSPasteboardItem] = paths.map { path in
                let box = NSPasteboardItem()
                box.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                box.setString(item.id.uuidString, forType: PasteboardReader.markerType)
                return box
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(boxes)
            return true

        default:
            guard let text = item.text else { return false }
            let itemBox = NSPasteboardItem()
            itemBox.setString(text, forType: .string)
            if !plainText, let name = item.rtfBlob,
               let rtf = await ClipStorage.shared.readBlob(named: name) {
                itemBox.setData(rtf, forType: .rtf)
            }
            itemBox.setString(item.id.uuidString, forType: PasteboardReader.markerType)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([itemBox])
            return true
        }
    }

    /// 写入一段自定义文本（例如换算出来的颜色代码）。
    static func writeString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let itemBox = NSPasteboardItem()
        itemBox.setString(text, forType: .string)
        itemBox.setString("external", forType: PasteboardReader.markerType)
        pasteboard.writeObjects([itemBox])
    }

    /// 用 ImageIO 把 PNG 解码后编码成 TIFF。
    /// nonisolated：纯函数、无共享状态，明确允许在后台线程执行（项目默认隔离是 MainActor）。
    nonisolated private static func makeTIFFData(from png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.tiff.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
