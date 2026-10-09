import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SitePhotoUpload {
    nonisolated static let maximumBytes = 2 * 1024 * 1024

    enum Failure: LocalizedError {
        case unreadable, tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Could not open this photo. Please try choosing it again or choose another picture."
            case .tooLarge:
                return "Could not make this photo small enough to upload. Please choose another picture."
            }
        }
    }

    // Photos can supply HEIC, PNG, or full-resolution camera data. Decode at a
    // bounded size and bake in orientation before sending an actual JPEG.
    nonisolated static func jpeg(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.unreadable
        }
        for dimension in [2048, 1440, 1024] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  let context = CGContext(
                    data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { throw Failure.unreadable }
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.draw(image, in: bounds)
            guard let flattened = context.makeImage() else { throw Failure.unreadable }
            for quality in [0.85, 0.7, 0.55] {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw Failure.unreadable
                }
                CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
                if output.length <= maximumBytes { return output as Data }
            }
        }
        throw Failure.tooLarge
    }
}
