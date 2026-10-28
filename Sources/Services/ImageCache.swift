import AppKit
import ImageIO

/// 后台解码的结果包装。NSImage / CGImage 都不是 Sendable，但这里搬运的是一个已经
/// 解码完成、之后只读的位图，跨线程传引用是安全的。
private struct DecodedImage: @unchecked Sendable {
    let image: NSImage?
}

/// 缩略图 / 预览图的内存缓存。缩略图文件本身很小，同步读盘即可，避免每个行视图都做异步状态机。
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
        if let name = item.thumbBlob {
            // 正常路径：缩略图文件本来就小，同步读盘即可。
            if let cached = thumbnails.object(forKey: name as NSString) { return cached }
            if let url = ClipStorage.shared.blobURL(named: name),
               let image = NSImage(contentsOf: url) {
                set(image, in: thumbnails, key: name)
                return image
            }
        }
        // 兜底：缩略图写盘失败 / 被外部删了，但没有图就只剩一个占位方块，
        // 在列表里完全分不出两张截图。以前这里直接返回全尺寸原图——横 46×34 的
        // 九宫格里画一张 4K 图，解码后 64MB，还不敢入缓存（会把缩略图预算吃穿），
        // 于是每次重绘都重新解一张。现在改成现场降采样出一张小图，可以放心缓存。
        return fallbackThumbnail(for: item)
    }

    /// 从原图现场生成一张 thumbnail 级别的缩略图（带独立缓存 key）。
    private func fallbackThumbnail(for item: ClipItem) -> NSImage? {
        guard let name = item.imageBlob, let url = ClipStorage.shared.blobURL(named: name) else { return nil }
        let key = "fallback:\(name)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = Self.downscaledImage(at: url, maxPixelSize: Self.thumbnailMaxPixelSize) else { return nil }
        set(image, in: thumbnails, key: key as String)
        return image
    }

    /// 列表行按 46×34 pt 显示，2 倍屏下 92×68；留一点余量给 3 倍屏和圆角裁切。
    private nonisolated static let thumbnailMaxPixelSize = 128

    /// 预览面板里的大图（同步）。只给一次性的点击场景用（放大浮层）。
    /// 预览窗格跟着选中项切换，必须走 `previewImage(for:)`。
    func preview(for item: ClipItem) -> NSImage? {
        guard let name = item.imageBlob else { return nil }
        return image(named: name, in: previews, fallback: nil)
    }

    /// 预览窗格用：解码放后台线程。
    ///
    /// 原图动辄 4K（解码后 64MB），在 SwiftUI body 里同步解码会让切换条目、
    /// hover、拖窗口都卡一下；而预览缓存最多只存得下 1~2 张，所以每次换条目
    /// 都会重新解码。这里在后台用 ImageIO 解成 CGImage，再回主线程包成 NSImage。
    func previewImage(for item: ClipItem) async -> NSImage? {
        guard let name = item.imageBlob, let url = ClipStorage.shared.blobURL(named: name) else { return nil }
        if let cached = previews.object(forKey: name as NSString) { return cached }
        let boxed = await Task.detached(priority: .userInitiated) {
            Self.decodeImage(at: url)
        }.value
        guard let image = boxed.image else { return nil }
        set(image, in: previews, key: name)
        return image
    }

    /// 用 ImageIO 降采样解码：只解出需要的那张缩略图，不把原图整张读进内存。
    private nonisolated static func downscaledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// 在后台线程把文件解码成位图并包成 NSImage（不留惰性解码到主线程）。
    private nonisolated static func decodeImage(at url: URL) -> DecodedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return DecodedImage(image: nil) }
        // ShouldCacheImmediately：解码就在这次调用里做完，不让它拖到主线程绘图时。
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return DecodedImage(image: nil)
        }
        return DecodedImage(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        )
    }

    private func image(named name: String, in cache: NSCache<NSString, NSImage>, fallback: String?) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        if let url = ClipStorage.shared.blobURL(named: name),
           let image = NSImage(contentsOf: url) {
            set(image, in: cache, key: name)
            return image
        }
        if let fallback,
           let url = ClipStorage.shared.blobURL(named: fallback),
           let image = NSImage(contentsOf: url) {
            // 兜底图是全尺寸原图：只返回、不按缩略图的 key 入缓存。
            // 按原图像素计费的一条就能把 48MB 的缩略图预算吃穿，把真正的缩略图
            // 全部挤掉，于是整个列表下一帧集体重新解码。
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

    /// 按 blob 文件名移除缓存条目（条目被删除 / 清理时调用）。
    /// 缩略图和预览图都用 blob 文件名作键，所以两个缓存都要清。
    func remove(names: [String]) {
        for name in names {
            let key = name as NSString
            thumbnails.removeObject(forKey: key)
            previews.removeObject(forKey: key)
        }
    }

    func clear() {
        thumbnails.removeAllObjects()
        previews.removeAllObjects()
    }
}
