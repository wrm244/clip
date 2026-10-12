import AppKit

/// 缩略图 / 预览图的内存缓存。图片文件本身很小，同步读盘即可，避免每个行视图都做异步状态机。
final class ImageCache {
    static let shared = ImageCache()

    private let thumbnails = NSCache<NSString, NSImage>()
    private let previews = NSCache<NSString, NSImage>()

    private init() {
        thumbnails.countLimit = 400
        previews.countLimit = 4
        // 只限条数是不够的：单张 4096×4096 的原图解到内存里就有 64MB，
        // 4 张预览图最坏能吃掉 256MB。按解码后体积计费 + 上限兜底。
        thumbnails.totalCostLimit = 48 * 1024 * 1024
        previews.totalCostLimit = 96 * 1024 * 1024
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
            set(image, in: cache, key: name)
            return image
        }
        if let fallback, let image = NSImage(contentsOf: ClipStorage.shared.blobURL(named: fallback)) {
            set(image, in: cache, key: name)
            return image
        }
        return nil
    }

    /// 以解码后的**像素**体积作为 cost 入缓存。
    ///
    /// 不能拿 `image.size`（点）来估：Retina 截图的像素尺寸是点的两倍，
    /// 按点算会把一份 4096×4096 的图记成 2048×2048（低估 4 倍），
    /// totalCostLimit 也就形同虚设。优先取位图表示的真实像素尺寸。
    private func set(_ image: NSImage, in cache: NSCache<NSString, NSImage>, key: String) {
        var pixels = 0
        for rep in image.representations {
            pixels = max(pixels, max(rep.pixelsWide, 1) * max(rep.pixelsHigh, 1))
        }
        if pixels == 0 {
            let size = image.size
            pixels = Int(max(size.width, 1) * max(size.height, 1))
        }
        cache.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    func clear() {
        thumbnails.removeAllObjects()
        previews.removeAllObjects()
    }
}
