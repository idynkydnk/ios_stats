import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run with swiftc stats/stats/SitePhotoUpload.swift tests/PhotoUploadTests.swift
// -o /tmp/stats-photo-tests && /tmp/stats-photo-tests
@main
struct PhotoUploadTests {
    static func fixture(width: Int, height: Int, type: UTType, orientation: Int = 1) -> Data {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Leave half transparent to verify flattening against white.
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest), "Could not create test fixture")
        return data as Data
    }

    static func decoded(_ data: Data) throws -> CGImage {
        let jpeg = try SitePhotoUpload.jpeg(from: data)
        return decodeJPEG(jpeg)
    }

    static func decodeJPEG(_ jpeg: Data) -> CGImage {
        precondition(jpeg.count <= SitePhotoUpload.maximumBytes)
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        precondition(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    static func color(atX x: Int, y: Int, in image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: pixels + offset, count: 3))
    }

    static func checkCrops() throws {
        let original = fixture(width: 400, height: 200, type: .png)
        let preview = try SitePhotoUpload.preview(from: original)
        let left = decodeJPEG(try SitePhotoUpload.croppedJPEG(
            from: preview, rect: CGRect(x: 10, y: 30, width: 100, height: 100)
        ))
        precondition(left.width == 100 && left.height == 100)
        let red = color(atX: 50, y: 50, in: left)
        let previewRed = color(atX: 50, y: 50, in: preview)
        precondition(red[0] > 200 && red[1] < 80 && red[2] < 80)
        precondition(zip(previewRed, red).allSatisfy { abs(Int($0) - Int($1)) < 12 },
                     "Crop must use the selected region and preserve its color")
        let right = decodeJPEG(try SitePhotoUpload.croppedJPEG(
            from: preview, rect: CGRect(x: 280, y: 30, width: 100, height: 100)
        ))
        precondition(color(atX: 50, y: 50, in: right).allSatisfy { $0 > 245 }, "Panning must change saved pixels")

        for rect in [CGRect(x: -20, y: -10, width: 99.8, height: 99.8),
                     CGRect(x: 390, y: 190, width: 99.8, height: 99.8),
                     CGRect(x: -100, y: -100, width: 900, height: 900)] {
            let result = decodeJPEG(try SitePhotoUpload.croppedJPEG(from: preview, rect: rect))
            precondition(result.width == result.height && result.width <= preview.height,
                         "Edge crops must stay square and within the photo")
        }
        for rect in [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)] {
            do {
                _ = try SitePhotoUpload.croppedJPEG(from: preview, rect: rect)
                preconditionFailure("Invalid crop was accepted")
            } catch SitePhotoUpload.Failure.unreadable {}
        }

        // All camera orientations, including mirrored selfies, must be baked
        // into the preview before its crop coordinates are used for export.
        for orientation in 1...8 {
            let rotated = try SitePhotoUpload.preview(from: fixture(width: 400, height: 200, type: .jpeg, orientation: orientation))
            precondition(rotated.width == (orientation <= 4 ? 400 : 200))
            precondition(rotated.height == (orientation <= 4 ? 200 : 400))
            let rect = CGRect(x: 25, y: 35, width: 100, height: 100)
            let selected = rotated.cropping(to: rect)!
            let saved = decodeJPEG(try SitePhotoUpload.croppedJPEG(from: rotated, rect: rect))
            let expected = color(atX: 50, y: 50, in: selected)
            let actual = color(atX: 50, y: 50, in: saved)
            precondition(zip(expected, actual).allSatisfy { abs(Int($0) - Int($1)) < 12 },
                         "Saved crop must match the oriented preview")
        }
        let large = try SitePhotoUpload.preview(from: fixture(width: 5000, height: 2500, type: .png))
        precondition(large.width == 4096 && large.height == 2048, "Preview must have bounded memory use")
        let zoomed = decodeJPEG(try SitePhotoUpload.croppedJPEG(from: large, rect: CGRect(x: 1100, y: 100, width: 300, height: 300)))
        precondition(zoomed.width == 300 && zoomed.height == 300, "Zoomed crops must not be upscaled")
    }

    static func main() throws {
        for data in [Data(), Data("not a photo".utf8)] {
            do {
                _ = try SitePhotoUpload.jpeg(from: data)
                preconditionFailure("Invalid data was accepted")
            } catch SitePhotoUpload.Failure.unreadable {}
        }
        let large = try decoded(fixture(width: 4032, height: 3024, type: .png))
        precondition(large.width == 2048 && large.height == 1536)
        let portrait = try decoded(fixture(width: 120, height: 80, type: .jpeg, orientation: 6))
        precondition(portrait.width == 80 && portrait.height == 120)
        let heic = try decoded(fixture(width: 160, height: 120, type: .heic))
        precondition(heic.width == 160 && heic.height == 120)
        let transparent = try decoded(fixture(width: 100, height: 100, type: .png))
        let context = CGContext(data: nil, width: 100, height: 100,
                                bitsPerComponent: 8, bytesPerRow: 400,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(transparent, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = (50 * 100 + 90) * 4
        precondition(pixels[offset] > 245 && pixels[offset + 1] > 245 && pixels[offset + 2] > 245)
        try checkCrops()
        print("Photo upload tests passed: formats, all orientations, resizing, transparency, crop selection, crop edges, preview size, and invalid data.")
    }
}
