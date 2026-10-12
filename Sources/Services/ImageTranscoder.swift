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
    ///   - maxBytes: 超过该体积直接放弃，避免历史库膨胀。
    ///   - maxPixel: 最长边上限，超大截图会被等比缩小。
    func transcode(_ data: Data, maxBytes: Int, maxPixel: Int = 4096, thumbnailPixel: Int = 720) -> TranscodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let image: CGImage?
        if max(pixelWidth, pixelHeight) > maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }

        guard let png = encode(image, type: UTType.png.identifier as CFString) else { return nil }
        guard png.count <= maxBytes else { return nil }

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

    private func encode(_ image: CGImage, type: CFString, properties: [CFString: Any] = [:]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
