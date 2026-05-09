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
            backgroundMode: .color,
            gradientColors: [],
            solidColor: .black,
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
}
