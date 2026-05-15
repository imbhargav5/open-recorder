import CoreGraphics
import XCTest
@testable import OpenRecorderMac

final class CursorOverlaySettingsTests: XCTestCase {
    func testLegacyCursorSettingsDecodeDefaultStyleAndVariant() throws {
        let data = """
        {
          "isVisible": true,
          "loops": false,
          "size": 1.5,
          "smoothing": 0.4
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(settings.style, .arrow)
        XCTAssertEqual(settings.variant, .standard)
        XCTAssertEqual(settings.size, 1.5)
    }

    func testCursorSettingsRoundTripStyleAndVariant() throws {
        let settings = CursorOverlaySettings(
            isVisible: true,
            loops: true,
            size: 8,
            smoothing: 0.8,
            style: .outlineArrow,
            variant: .bold
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testLegacyColorVariantNamesMapToShapeVariants() throws {
        let data = """
        {
          "isVisible": true,
          "loops": false,
          "size": 1,
          "smoothing": 0.4,
          "style": "handPointer",
          "variant": "highContrast"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(settings.style, .handPointer)
        XCTAssertEqual(settings.variant, .bold)
    }

    func testCursorSizeClampsWhenCreatedAndDecoded() throws {
        let tooSmall = CursorOverlaySettings(isVisible: true, loops: false, size: 0.2, smoothing: 0.4)
        XCTAssertEqual(tooSmall.size, 1)

        let data = """
        {
          "isVisible": true,
          "loops": false,
          "size": 12,
          "smoothing": 0.4,
          "style": "arrow",
          "variant": "dark"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CursorOverlaySettings.self, from: data)

        XCTAssertEqual(decoded.size, 8)
        XCTAssertEqual(decoded.variant, .slim)
    }

    func testProjectVideoStateDecodesLegacyCursorOverlayDefaults() throws {
        let data = """
        {
          "cursorOverlay": {
            "isVisible": true,
            "loops": true,
            "size": 2,
            "smoothing": 0.7
          }
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ProjectVideoEditorState.self, from: data)

        XCTAssertEqual(state.cursorOverlay.style, .arrow)
        XCTAssertEqual(state.cursorOverlay.variant, .standard)
        XCTAssertEqual(state.cursorOverlay.size, 2)
    }

    func testCursorRendererHotspotsMatchStyleRules() {
        let size: CGFloat = 24
        let arrow = CursorPresetRenderer.drawing(style: .arrow, size: size)
        let macOSBlack = CursorPresetRenderer.drawing(style: .macOSBlackArrow, size: size)
        let outline = CursorPresetRenderer.drawing(style: .outlineArrow, size: size)
        let hand = CursorPresetRenderer.drawing(style: .handPointer, size: size)
        let iBeam = CursorPresetRenderer.drawing(style: .iBeam, size: size)
        let dot = CursorPresetRenderer.drawing(style: .dotPointer, size: size)

        XCTAssertEqual(arrow.hotspot.x, 0, accuracy: 0.001)
        XCTAssertEqual(arrow.hotspot.y, 0, accuracy: 0.001)
        XCTAssertEqual(macOSBlack.hotspot.x, 0, accuracy: 0.001)
        XCTAssertEqual(macOSBlack.hotspot.y, 0, accuracy: 0.001)
        XCTAssertEqual(outline.hotspot.x, 0, accuracy: 0.001)
        XCTAssertEqual(outline.hotspot.y, 0, accuracy: 0.001)
        XCTAssertEqual(hand.hotspot.x, size * 0.54, accuracy: 0.001)
        XCTAssertEqual(hand.hotspot.y, size * 0.02, accuracy: 0.001)
        XCTAssertEqual(iBeam.hotspot.x, size * 0.50, accuracy: 0.001)
        XCTAssertEqual(iBeam.hotspot.y, size * 0.60, accuracy: 0.001)
        XCTAssertEqual(dot.hotspot.x, size * 0.45, accuracy: 0.001)
        XCTAssertEqual(dot.hotspot.y, size * 0.45, accuracy: 0.001)
    }

    func testCursorVariantsChangeShapeGeometryWithoutChangingPalette() {
        let size: CGFloat = 24
        let standardArrow = CursorPresetRenderer.drawing(style: .arrow, size: size, variant: .standard)
        let slimArrow = CursorPresetRenderer.drawing(style: .arrow, size: size, variant: .slim)
        let boldArrow = CursorPresetRenderer.drawing(style: .arrow, size: size, variant: .bold)
        let softDot = CursorPresetRenderer.drawing(style: .dotPointer, size: size, variant: .soft)

        XCTAssertLessThan(slimArrow.canvasSize.width, standardArrow.canvasSize.width)
        XCTAssertGreaterThan(boldArrow.canvasSize.width, standardArrow.canvasSize.width)
        XCTAssertEqual(CursorPresetRenderer.palette.fill.hexString, "#FFFFFF")
        XCTAssertFalse(softDot.fillsShape)
    }

    func testMacOSBlackCursorStyleUsesArrowGeometryWithOwnPalette() {
        let size: CGFloat = 24
        let arrow = CursorPresetRenderer.drawing(style: .arrow, size: size, variant: .standard)
        let macOSBlack = CursorPresetRenderer.drawing(style: .macOSBlackArrow, size: size, variant: .standard)
        let slimMacOSBlack = CursorPresetRenderer.drawing(style: .macOSBlackArrow, size: size, variant: .slim)
        let standardPalette = CursorPresetRenderer.palette(for: .macOSBlackArrow)

        XCTAssertEqual(macOSBlack.canvasSize.width, arrow.canvasSize.width, accuracy: 0.001)
        XCTAssertEqual(macOSBlack.canvasSize.height, arrow.canvasSize.height, accuracy: 0.001)
        XCTAssertEqual(macOSBlack.hotspot.x, 0, accuracy: 0.001)
        XCTAssertEqual(macOSBlack.hotspot.y, 0, accuracy: 0.001)
        XCTAssertLessThan(slimMacOSBlack.canvasSize.width, macOSBlack.canvasSize.width)
        XCTAssertEqual(standardPalette.fill.hexString, "#1F2023")
        XCTAssertNotEqual(standardPalette.fill.hexString, CursorPresetRenderer.palette.fill.hexString)
    }
}
