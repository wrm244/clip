import AppKit
import Foundation

/// 把历史条目写回系统剪贴板。
enum PasteboardWriter {
    /// 写回一条历史记录。plainText 为 true 时只写纯文本（⌥↩）。
    static func write(_ item: ClipItem, plainText: Bool) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .image where !plainText:
            guard let name = item.imageBlob,
                  let data = await ClipStorage.shared.readBlob(named: name) else { return }
            let itemBox = NSPasteboardItem()
            itemBox.setData(data, forType: .png)
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                itemBox.setData(tiff, forType: .tiff)
            }
            itemBox.setString(item.id.uuidString, forType: PasteboardReader.markerType)
            pasteboard.writeObjects([itemBox])

        case .file where !plainText:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return }
            pasteboard.writeObjects(urls)

        default:
            guard let text = item.text else { return }
            let itemBox = NSPasteboardItem()
            itemBox.setString(text, forType: .string)
            if !plainText, let name = item.rtfBlob,
               let rtf = await ClipStorage.shared.readBlob(named: name) {
                itemBox.setData(rtf, forType: .rtf)
            }
            itemBox.setString(item.id.uuidString, forType: PasteboardReader.markerType)
            pasteboard.writeObjects([itemBox])
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
}
