import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 一次图片转码的结果。
struct TranscodedImage: Sendable {
    var png: Data
    var thumbnail: Data?
    var width: Int
    var height: Int
    var hash: String
}

/// 图片解码/缩放/编码。放在独立 actor 上执行，避免阻塞主线程。
actor ImageTranscoder {
    static let shared = ImageTranscoder()

    /// - Parameters:
    ///   - data: 剪贴板里拿到的原始图片数据（PNG/TIFF/JPEG 均可）。
    ///   - maxBytes: 编码后体积上限。超限不会直接丢弃，而是继续缩小最长边重试
    ///     （README 承诺的「超限图片自动降采样」）；实在降不下去才放弃。
    ///   - maxPixel: 最长边上限，超大截图会被等比缩小。
    func transcode(_ data: Data, maxBytes: Int, maxPixel: Int = 4096, thumbnailPixel: Int = 720) -> TranscodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        // PNG 是无损格式，截图 / 照片重新编码后常常比原始数据大好几倍——
        // 只按像素上限缩一次是不够的（例如 4096px 的 PNG 仍可能有十几 MB）。
        // 这里按「面积换体积」逐轮收缩最长边，最多 4 轮，每轮按实测比例估算下一档，
        // 保证既不会无限编码，也不会把一张本来能存的图直接丢掉。
        var limit = maxPixel
        var image: CGImage?
        var png: Data?
        for _ in 0..<4 {
            guard let decoded = decode(source, maxPixel: limit, originalWidth: pixelWidth, originalHeight: pixelHeight),
                  let encoded = encode(decoded, type: UTType.png.identifier as CFString) else { return nil }
            image = decoded
            png = encoded
            if encoded.count <= maxBytes { break }
            let ratio = sqrt(Double(maxBytes) / Double(encoded.count)) * 0.9
            let next = max(256, Int(Double(limit) * min(ratio, 0.8)))
            if next >= limit { break }   // 已经缩到下限，再缩也不会更小
            limit = next
        }
        guard let image, let png, png.count <= maxBytes else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        var thumbnail: Data?
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            thumbnail = encode(thumb, type: UTType.jpeg.identifier as CFString,
                               properties: [kCGImageDestinationLossyCompressionQuality: 0.8])
        }

        return TranscodedImage(
            png: png,
            thumbnail: thumbnail,
            width: image.width,
            height: image.height,
            hash: ContentHash.sha256(png)
        )
    }

    /// 解码到指定最长边以内。原图本来就小于上限时直接全量解码，避免多余的缩放开销。
    private func decode(_ source: CGImageSource, maxPixel: Int, originalWidth: Int, originalHeight: Int) -> CGImage? {
        if max(originalWidth, originalHeight) > maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func encode(_ image: CGImage, type: CFString, properties: [CFString: Any] = [:]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
