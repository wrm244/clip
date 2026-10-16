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
        guard maxBytes > 0, maxPixel > 0, thumbnailPixel > 0 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1

        // PNG 是无损格式，截图 / 照片重新编码后常常比原始数据大好几倍——
        // 只按像素上限缩一次是不够的（例如 4096px 的 PNG 仍可能有十几 MB）。
        // 这里按「面积换体积」逐轮收缩最长边，最多 4 轮，每轮按实测比例估算下一档，
        // 保证既不会无限编码，也不会把一张本来能存的图直接丢掉。
        //
        // 关键：只在第一轮从源图解码，之后直接在内存里缩小已解码的位图，
        // 不再回源图重复解码（旧实现每轮都重新解出一张最长边 4096px 的位图，
        // 既白费 CPU，峰值内存也叠加）。
        guard var image = decode(
            source,
            maxPixel: maxPixel,
            originalWidth: pixelWidth,
            originalHeight: pixelHeight,
            orientation: orientation
        ) else {
            return nil
        }
        var png: Data?
        for _ in 0..<4 {
            guard let encoded = encode(image, type: UTType.png.identifier as CFString) else { return nil }
            png = encoded
            if encoded.count <= maxBytes { break }
            let longest = max(image.width, image.height)
            let ratio = sqrt(Double(maxBytes) / Double(encoded.count)) * 0.9
            let next = max(256, Int(Double(longest) * min(ratio, 0.8)))
            if next >= longest { break }   // 已经缩到下限，再缩也不会更小
            guard let scaled = downscale(image, maxPixel: next) else { break }
            image = scaled
        }
        guard let png, png.count <= maxBytes else { return nil }

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
    private func decode(
        _ source: CGImageSource,
        maxPixel: Int,
        originalWidth: Int,
        originalHeight: Int,
        orientation: Int
    ) -> CGImage? {
        if max(originalWidth, originalHeight) > maxPixel || orientation != 1 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 在内存里等比缩小已解码的位图（不再回源图解码）。
    private func downscale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixel else { return image }
        let scale = Double(maxPixel) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func encode(_ image: CGImage, type: CFString, properties: [CFString: Any] = [:]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
