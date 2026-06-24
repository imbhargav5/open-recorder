import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class CursorOverlaySettingsTests: XCTestCase {
    func testLegacyCursorSettingsDecodeDefaultStyleID() throws {
        let data = try utf8Data("""
        {
          "isVisible": true,
          "loops": false,
          "size": 1.5,
          "smoothing": 0.4
        }
        """)

        let settings = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(settings.styleID, CursorStyleRegistry.defaultStyleID)
        XCTAssertEqual(settings.size, 1.5)
    }

    func testCursorSettingsRoundTripStyleIDAndEffects() throws {
        let settings = CursorOverlaySettings(
            isVisible: true,
            loops: true,
            size: 8,
            smoothing: 0.8,
            styleID: "touch.dot",
            clickEffect: .ripple,
            idleBehavior: .fadeWhenIdle,
            motionEffect: .subtleLean
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testLegacyStyleAndVariantNamesFallBackToDefaultStyleID() throws {
        let data = try utf8Data("""
        {
          "isVisible": true,
          "loops": false,
          "size": 1,
          "smoothing": 0.4,
          "style": "dotPointer",
          "variant": "soft"
        }
        """)

        let settings = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(settings.styleID, CursorStyleRegistry.defaultStyleID)
    }

    func testUnknownStyleIDFallsBackToDefaultStyleID() throws {
        let data = try utf8Data("""
        {
          "isVisible": true,
          "loops": false,
          "size": 1,
          "smoothing": 0.4,
          "styleID": "future.missing"
        }
        """)

        let settings = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(settings.styleID, CursorStyleRegistry.defaultStyleID)
    }

    func testCursorSizeClampsWhenCreatedAndDecoded() throws {
        let tooSmall = CursorOverlaySettings(isVisible: true, loops: false, size: 0.2, smoothing: 0.4)
        XCTAssertEqual(tooSmall.size, 1)

        let data = try utf8Data("""
        {
          "isVisible": true,
          "loops": false,
          "size": 12,
          "smoothing": 0.4,
          "styleID": "system.black"
        }
        """)

        let decoded = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(decoded.size, 8)
        XCTAssertEqual(decoded.styleID, "system.black")
    }

    func testCursorOverlayGeometryUsesSourceSizedDefaultAtFullScale() {
        XCTAssertEqual(
            CursorOverlayGeometry.glyphSize(displayScale: 1, settings: .default),
            20,
            accuracy: 0.001
        )
    }

    func testCursorOverlayGeometryScalesWithPreviewDisplayScale() {
        XCTAssertEqual(
            CursorOverlayGeometry.glyphSize(displayScale: 0.5, settings: .default),
            10,
            accuracy: 0.001
        )
    }

    func testCursorOverlayGeometryAppliesSizeMultiplier() {
        let settings = CursorOverlaySettings(isVisible: true, loops: false, size: 2, smoothing: 0.4)

        XCTAssertEqual(
            CursorOverlayGeometry.glyphSize(displayScale: 1, settings: settings),
            40,
            accuracy: 0.001
        )
    }

    func testCursorOverlayGeometryClampsInvalidDisplayScale() {
        XCTAssertEqual(
            CursorOverlayGeometry.glyphSize(displayScale: .infinity, settings: .default),
            1,
            accuracy: 0.001
        )
    }

    func testCursorOverlayGeometryDerivesScaleFromContentAndCrop() {
        let contentRect = CGRect(x: 0, y: 0, width: 864, height: 558)
        let cropRect = CGRect(x: 0, y: 0, width: 1728, height: 1116)

        XCTAssertEqual(
            CursorOverlayGeometry.displayScale(contentRect: contentRect, cropRect: cropRect),
            0.5,
            accuracy: 0.001
        )
    }

    func testCursorOverlayGeometryStandardizesReversedCropRect() {
        let contentRect = CGRect(x: 0, y: 0, width: 960, height: 540)
        let cropRect = CGRect(x: 1920, y: 1080, width: -1920, height: -1080)

        XCTAssertEqual(
            CursorOverlayGeometry.displayScale(contentRect: contentRect, cropRect: cropRect),
            0.5,
            accuracy: 0.001
        )
    }

    func testCursorOverlayGeometryTreatsEmptyCropRectAsZeroScale() {
        let contentRect = CGRect(x: 0, y: 0, width: 960, height: 540)
        let cropRect = CGRect(x: 0, y: 0, width: 0, height: 540)

        XCTAssertEqual(
            CursorOverlayGeometry.displayScale(contentRect: contentRect, cropRect: cropRect),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CursorOverlayGeometry.glyphSize(contentRect: contentRect, cropRect: cropRect, settings: .default),
            1,
            accuracy: 0.001
        )
    }

    func testProjectVideoStateDecodesLegacyCursorOverlayDefaults() throws {
        let data = try utf8Data("""
        {
          "cursorOverlay": {
            "isVisible": true,
            "loops": true,
            "size": 2,
            "smoothing": 0.7
          }
        }
        """)

        let state = try JSONDecoder().decode(ProjectVideoEditorState.self, from: data)

        XCTAssertEqual(state.cursorOverlay.styleID, CursorStyleRegistry.defaultStyleID)
        XCTAssertEqual(state.cursorOverlay.size, 2)
    }

    func testCursorRendererHotspotsMatchStyleRules() {
        let size: CGFloat = 24
        let arrow = CursorStyleRenderer.drawing(styleID: "system.white", size: size)
        let blackArrow = CursorStyleRenderer.drawing(styleID: "system.black", size: size)
        let hand = CursorStyleRenderer.drawing(styleID: "system.hand", size: size)
        let iBeam = CursorStyleRenderer.drawing(styleID: "system.ibeam", size: size)
        let dot = CursorStyleRenderer.drawing(styleID: "touch.dot", size: size)

        XCTAssertEqual(arrow.hotspot.x, 0, accuracy: 0.001)
        XCTAssertEqual(arrow.hotspot.y, 0, accuracy: 0.001)
        XCTAssertEqual(blackArrow.hotspot.x, 0, accuracy: 0.001)
        XCTAssertEqual(blackArrow.hotspot.y, 0, accuracy: 0.001)
        XCTAssertEqual(hand.hotspot.x, size * 0.54, accuracy: 0.001)
        XCTAssertEqual(hand.hotspot.y, size * 0.02, accuracy: 0.001)
        XCTAssertEqual(iBeam.hotspot.x, size * 0.50, accuracy: 0.001)
        XCTAssertEqual(iBeam.hotspot.y, size * 0.60, accuracy: 0.001)
        XCTAssertEqual(dot.hotspot.x, size * 1.08 * 0.45, accuracy: 0.001)
        XCTAssertEqual(dot.hotspot.y, size * 1.08 * 0.45, accuracy: 0.001)
    }

    func testCursorRegistryHasUniqueRenderableStyles() {
        let ids = CursorStyleRegistry.styles.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)

        for style in CursorStyleRegistry.styles {
            let glyph = CursorStyleRenderer.renderedGlyph(styleID: style.id, size: 24)
            XCTAssertNotNil(glyph, "Expected \(style.id) to render")
            XCTAssertGreaterThan(glyph?.canvasSize.width ?? 0, 0)
            XCTAssertGreaterThan(glyph?.canvasSize.height ?? 0, 0)
        }
    }

    private func utf8Data(_ string: String) throws -> Data {
        try XCTUnwrap(string.data(using: .utf8))
    }
}
