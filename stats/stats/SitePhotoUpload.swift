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
        try jpeg(from: preview(from: data, maximumDimension: 2048))
    }

    nonisolated static func preview(from data: Data, maximumDimension: Int = 4096) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        return image
    }

    // Use the same upright pixels shown in the editor. Clamp and round once so
    // an edge crop never gains an empty border or becomes a non-square image.
    nonisolated static func croppedJPEG(from image: CGImage, rect: CGRect) throws -> Data {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width >= 1, rect.height >= 1 else { throw Failure.unreadable }
        let side = min(rect.width, rect.height, CGFloat(image.width), CGFloat(image.height)).rounded(.down)
        let x = min(max(rect.midX - side / 2, 0), CGFloat(image.width) - side).rounded(.down)
        let y = min(max(rect.midY - side / 2, 0), CGFloat(image.height) - side).rounded(.down)
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else {
            throw Failure.unreadable
        }
        return try jpeg(from: cropped)
    }

    nonisolated static func jpeg(from image: CGImage) throws -> Data {
        for dimension in [2048, 1440, 1024] {
            let scale = min(1, CGFloat(dimension) / CGFloat(max(image.width, image.height)))
            let width = max(1, Int(CGFloat(image.width) * scale))
            let height = max(1, Int(CGFloat(image.height) * scale))
            guard let context = CGContext(
                    data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { throw Failure.unreadable }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            context.interpolationQuality = .high
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
