import CoreImage
import XCTest
@testable import OpenRecorderMac

final class VideoStaticBackgroundCacheTests: XCTestCase {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let extent = CGRect(x: 0, y: 0, width: 64, height: 36)
    private var style: BackgroundStyle {
        .gradient(GradientPreset(id: "test", kind: .linear(angleDegrees: 0), stops: [
            GradientStop(color: SerializableColor(hex: "336699"), position: 0),
            GradientStop(color: SerializableColor(hex: "FF8800"), position: 1)
        ]))
    }

    func testRepeatedFramesReuseOneRenderedBackground() {
        let cache = VideoStaticBackgroundCache(context: context)
        var builds = 0
        var first: CIImage?
        for _ in 0..<120 {
            let image = cache.image(style: style, extent: extent, blurRadius: 0) {
                builds += 1
                return CIImage(color: .red).cropped(to: extent)
            }
            if let first { XCTAssertTrue(image === first) } else { first = image }
        }
        XCTAssertEqual(builds, 1)
    }

    func testStyleSizeBlurAndInvalidationRebuildWithoutKeepingOldEntries() {
        let cache = VideoStaticBackgroundCache(context: context)
        var builds = 0
        func read(_ style: BackgroundStyle, _ rect: CGRect, _ blur: Double) {
            _ = cache.image(style: style, extent: rect, blurRadius: blur) {
                builds += 1
                return CIImage(color: .red).cropped(to: rect)
            }
        }
        read(style, extent, 0)
        read(style, extent, 0)
        XCTAssertEqual(builds, 1)
        read(style, extent, 2)
        read(style, CGRect(x: 0, y: 0, width: 80, height: 40), 2)
        let wallpaper = BackgroundPresets.default
        read(wallpaper, extent, 2)
        read(style, extent, 0)
        XCTAssertEqual(builds, 5, "Returning to an old key must rebuild: cache capacity is one")
        cache.invalidate()
        read(style, extent, 0)
        XCTAssertEqual(builds, 6)
    }

    func testReplacingOrInvalidatingCacheReleasesPreviousImage() {
        let cache = VideoStaticBackgroundCache(context: context)
        weak var previous: CIImage?
        autoreleasepool {
            previous = cache.image(style: style, extent: extent, blurRadius: 0) {
                CIImage(color: .red).cropped(to: extent)
            }
        }
        XCTAssertNotNil(previous)
        autoreleasepool {
            _ = cache.image(style: style, extent: extent, blurRadius: 1) {
                CIImage(color: .blue).cropped(to: extent)
            }
        }
        XCTAssertNil(previous, "Changing keys must release the previous cached image")
        autoreleasepool {
            previous = cache.image(style: style, extent: extent, blurRadius: 1) {
                XCTFail("The replacement should already be cached")
                return CIImage.empty()
            }
        }
        cache.invalidate()
        XCTAssertNil(previous)
    }

    func testConstantColorsBypassCacheAndReleaseOldBackground() {
        let cache = VideoStaticBackgroundCache(context: context)
        var builds = 0
        weak var previous: CIImage?
        autoreleasepool {
            previous = cache.image(style: style, extent: extent, blurRadius: 0) {
                CIImage(color: .red).cropped(to: extent)
            }
        }
        for constant in [BackgroundStyle.transparent, .solid(SerializableColor(hex: "123456"))] {
            for _ in 0..<2 {
                _ = cache.image(style: constant, extent: extent, blurRadius: 0) {
                    builds += 1
                    return CIImage(color: .clear).cropped(to: extent)
                }
            }
        }
        XCTAssertEqual(builds, 4)
        XCTAssertNil(previous)
    }

    func testCachedPixelsPreserveGradientBlurAlphaAndExtent() {
        let cache = VideoStaticBackgroundCache(context: context)
        let rect = extent.offsetBy(dx: 11, dy: 7)
        let source = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: rect.minX, y: rect.minY),
            "inputPoint1": CIVector(x: rect.maxX, y: rect.maxY),
            "inputColor0": CIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.3),
            "inputColor1": CIColor(red: 0.9, green: 0.6, blue: 0.1, alpha: 0.9)
        ])!.outputImage!.cropped(to: rect).clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3]).cropped(to: rect)
        let cached = cache.image(style: style, extent: rect, blurRadius: 3) { source }
        XCTAssertEqual(cached.extent, rect)
        let expected = pixels(source, bounds: rect)
        let actual = pixels(cached, bounds: rect)
        let maximumDifference = zip(expected, actual).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(maximumDifference, 2, "Only 8-bit intermediate rounding is expected")
    }

    private func pixels(_ image: CIImage, bounds: CGRect) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Int(bounds.width * bounds.height) * 4)
        bytes.withUnsafeMutableBytes { pointer in
            context.render(image, toBitmap: pointer.baseAddress!, rowBytes: Int(bounds.width) * 4,
                           bounds: bounds, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return bytes
    }
}
