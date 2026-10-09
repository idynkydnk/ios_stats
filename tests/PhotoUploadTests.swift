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
        precondition(jpeg.count <= SitePhotoUpload.maximumBytes)
        let source = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        precondition(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
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
        print("Photo upload tests passed: HEIC, PNG, JPEG, orientation, resizing, transparency, and invalid data.")
    }
}
