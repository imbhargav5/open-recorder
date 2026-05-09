import AppKit
import XCTest
@testable import OpenRecorderMac

final class ScreenshotExportRendererTests: XCTestCase {
    func testSuggestedFileNameUsesScreenshotBaseName() {
        let url = URL(fileURLWithPath: "/tmp/open-recorder/screen-shot.png")

        XCTAssertEqual(
            ScreenshotExportRenderer.suggestedFileName(for: url),
            "screen-shot-export.png"
        )
    }

    func testRendererProducesPNGData() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()

        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .solid(SerializableColor(red: 0, green: 0, blue: 0)),
            padding: 2,
            backgroundRoundness: 1,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: image))
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

        XCTAssertTrue(data.starts(with: pngSignature))
    }

    func testRendererSupportsGradientBackground() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()

        let preset = BackgroundPresets.gradients[0]
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .gradient(preset),
            padding: 4,
            backgroundRoundness: 4,
            backgroundShadow: 0,
            imageRoundness: 2,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: image))
        XCTAssertTrue(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    }

    func testRendererSupportsWallpaperBackground() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()

        let wallpaper = try XCTUnwrap(BackgroundPresets.wallpapers.first)
        XCTAssertNotNil(wallpaper.fullURL, "Bundled wallpaper resource should be available in the test bundle.")

        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .wallpaper(wallpaper),
            padding: 6,
            backgroundRoundness: 8,
            backgroundShadow: 0,
            imageRoundness: 4,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: image))
        XCTAssertTrue(data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])))
    }
}
