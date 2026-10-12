import AppKit

/// 缩略图 / 预览图的内存缓存。图片文件本身很小，同步读盘即可，避免每个行视图都做异步状态机。
final class ImageCache {
    static let shared = ImageCache()

    private let thumbnails = NSCache<NSString, NSImage>()
    private let previews = NSCache<NSString, NSImage>()

    private init() {
        thumbnails.countLimit = 400
        previews.countLimit = 4
    }

    /// 列表里的小图。
    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let name = item.thumbBlob else { return nil }
        return image(named: name, in: thumbnails, fallback: item.imageBlob)
    }

    /// 预览面板里的大图。
    func preview(for item: ClipItem) -> NSImage? {
        guard let name = item.imageBlob else { return nil }
        return image(named: name, in: previews, fallback: nil)
    }

    private func image(named name: String, in cache: NSCache<NSString, NSImage>, fallback: String?) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        if let image = NSImage(contentsOf: ClipStorage.shared.blobURL(named: name)) {
            cache.setObject(image, forKey: name as NSString)
            return image
        }
        if let fallback, let image = NSImage(contentsOf: ClipStorage.shared.blobURL(named: fallback)) {
            cache.setObject(image, forKey: name as NSString)
            return image
        }
        return nil
    }

    func clear() {
        thumbnails.removeAllObjects()
        previews.removeAllObjects()
    }
}
