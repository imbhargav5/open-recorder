import AVFoundation
import CoreImage
import XCTest
@testable import OpenRecorderMac

final class VideoRoundedMaskCacheTests: XCTestCase {
    func testReusesInvariantRasterAcrossPlacement() throws {
        let cache = VideoRoundedMaskCache()
        let first = try XCTUnwrap(cache.mask(size: CGSize(width: 100.2, height: 80.1), cornerRadius: 12, role: .recording))
        let second = try XCTUnwrap(cache.mask(size: CGSize(width: 100.2, height: 80.1), cornerRadius: 12, role: .recording))
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.extent, CGRect(x: 0, y: 0, width: 101, height: 81))
        let placed = second.transformed(by: CGAffineTransform(translationX: 25.5, y: 44.25))
        XCTAssertEqual(placed.extent, first.extent.offsetBy(dx: 25.5, dy: 44.25).integral)
    }

    func testGeometryReplacementDoesNotEvictOtherRole() throws {
        let cache = VideoRoundedMaskCache()
        let size = CGSize(width: 100, height: 80)
        let recording = try XCTUnwrap(cache.mask(size: size, cornerRadius: 8, role: .recording))
        let camera = try XCTUnwrap(cache.mask(size: size, cornerRadius: 20, role: .facecam))
        for width in 101...120 {
            let next = try XCTUnwrap(cache.mask(size: CGSize(width: width, height: 80), cornerRadius: 8, role: .recording))
            XCTAssertFalse(next === recording)
            XCTAssertTrue(camera === cache.mask(size: size, cornerRadius: 20, role: .facecam))
        }
        XCTAssertFalse(recording === cache.mask(size: size, cornerRadius: 8, role: .recording))
        XCTAssertFalse(camera === cache.mask(size: size, cornerRadius: 21, role: .facecam))
    }

    func testEffectiveRadiusIncludesFractionalGeometry() throws {
        let cache = VideoRoundedMaskCache()
        let a = try XCTUnwrap(cache.mask(size: CGSize(width: 20.1, height: 20.1), cornerRadius: 100, role: .recording))
        let b = try XCTUnwrap(cache.mask(size: CGSize(width: 20.9, height: 20.9), cornerRadius: 100, role: .recording))
        XCTAssertFalse(a === b) // Same pixel dimensions, different clamped radius.
    }

    func testCancellationAndContextChangeDiscardBothRoles() throws {
        let compositor = VideoBackgroundCompositor()
        let size = CGSize(width: 64, height: 48)
        for contextChange in [false, true] {
            let recording = try XCTUnwrap(compositor.roundedMaskCache.mask(size: size, cornerRadius: 8, role: .recording))
            let camera = try XCTUnwrap(compositor.roundedMaskCache.mask(size: size, cornerRadius: 12, role: .facecam))
            if contextChange { compositor.renderContextChanged(AVVideoCompositionRenderContext()) }
            else { compositor.cancelAllPendingVideoCompositionRequests() }
            XCTAssertFalse(recording === compositor.roundedMaskCache.mask(size: size, cornerRadius: 8, role: .recording))
            XCTAssertFalse(camera === compositor.roundedMaskCache.mask(size: size, cornerRadius: 12, role: .facecam))
        }
    }

    func testAlphaFidelityAndRadiusZero() throws {
        let cache = VideoRoundedMaskCache()
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let size = CGSize(width: 32, height: 24)
        for radius in [CGFloat(0), 7.25, 100] {
            let cached = try XCTUnwrap(cache.mask(size: size, cornerRadius: radius, role: .recording))
            let uncached = try XCTUnwrap(VideoRoundedMaskCache.makeMask(size: size, cornerRadius: radius))
            func pixels(_ image: CIImage) -> [UInt8] {
                var data = [UInt8](repeating: 0, count: 32 * 24 * 4)
                context.render(image, toBitmap: &data, rowBytes: 32 * 4, bounds: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                return data
            }
            let actual = pixels(cached)
            XCTAssertEqual(actual, pixels(uncached))
            let alpha = stride(from: 3, to: actual.count, by: 4).map { actual[$0] }
            if radius == 0 { XCTAssertTrue(alpha.allSatisfy { $0 == 255 }) }
            else {
                XCTAssertEqual(alpha.first, 0)
                XCTAssertEqual(alpha[12 * 32 + 16], 255)
                XCTAssertTrue(alpha.contains { $0 > 0 && $0 < 255 }, "Antialiased edges must remain")
            }
        }
    }
}
