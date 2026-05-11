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

    func testBundledWallpaperResourcesResolveImagesAndThumbnails() throws {
        for wallpaper in BackgroundPresets.wallpapers {
            XCTAssertNotNil(wallpaper.fullURL, "Missing full wallpaper resource for \(wallpaper.id).")
            XCTAssertNotNil(wallpaper.thumbURL, "Missing thumbnail wallpaper resource for \(wallpaper.id).")
        }
    }
}

final class ScreenshotEditorHistoryTests: XCTestCase {
    func testDefaultBackgroundUsesFirstWallpaper() {
        let wallpaper = BackgroundPresets.wallpapers[0]

        XCTAssertEqual(ScreenshotEditorState.default.background, .wallpaper(wallpaper))
        XCTAssertEqual(BackgroundPresets.default.presetKind, .wallpaper)
    }

    @MainActor
    func testUndoRedoBackgroundStyleChange() {
        let editor = ScreenshotEditorController()
        let background = BackgroundStyle.solid(BackgroundPresets.solidColors[1])

        editor.update(\.background, to: background)

        XCTAssertEqual(editor.state.background, background)
        XCTAssertTrue(editor.canUndo)

        editor.undo()

        XCTAssertEqual(editor.state.background, ScreenshotEditorState.default.background)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)

        editor.redo()

        XCTAssertEqual(editor.state.background, background)
    }

    @MainActor
    func testSliderTransactionCollapsesScreenshotStyleChanges() {
        let editor = ScreenshotEditorController()

        editor.beginUndoTransaction()
        editor.update(\.padding, to: 72)
        editor.update(\.padding, to: 96)
        editor.endUndoTransaction()

        XCTAssertEqual(editor.state.padding, 96)
        XCTAssertTrue(editor.canUndo)

        editor.undo()

        XCTAssertEqual(editor.state.padding, ScreenshotEditorState.default.padding)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
    }

    @MainActor
    func testRedoIsClearedAfterNewScreenshotStyleChange() {
        let editor = ScreenshotEditorController()

        editor.update(\.padding, to: 72)
        editor.undo()
        XCTAssertTrue(editor.canRedo)

        editor.update(\.imageShadow, to: 0.2)

        XCTAssertFalse(editor.canRedo)
        XCTAssertEqual(editor.state.imageShadow, 0.2, accuracy: 0.001)
    }

    @MainActor
    func testResetHistoryKeepsScreenshotStyleButClearsUndo() {
        let editor = ScreenshotEditorController()

        editor.update(\.imageRoundness, to: 24)
        XCTAssertTrue(editor.canUndo)

        editor.resetHistory()

        XCTAssertEqual(editor.state.imageRoundness, 24, accuracy: 0.001)
        XCTAssertFalse(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
    }
}
