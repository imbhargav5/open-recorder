import AppKit
import XCTest
@testable import OpenRecorderMac

@MainActor
final class ScreenshotExportRendererTests: XCTestCase {
    private typealias BackgroundOrientationFixture = (name: String, style: BackgroundStyle)

    private let orientationProbeRows: [String] = ["RGB", "CYM"]

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

    func testRendererPreservesScreenshotPixelOrientation() throws {
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .transparent,
            padding: 0,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(rows: orientationProbeRows)))

        XCTAssertEqual(try pixelSymbols(from: data), orientationProbeRows)
    }

    func testCopiedTIFFRepresentationPreservesRenderedOrientation() throws {
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .transparent,
            padding: 0,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let pngData = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(rows: orientationProbeRows)))
        let image = try XCTUnwrap(NSImage(data: pngData))
        let tiffData = try XCTUnwrap(image.tiffRepresentation)

        XCTAssertEqual(try pixelSymbols(from: tiffData), orientationProbeRows)
    }

    func testRendererPreservesScreenshotOrientationAcrossBackgroundStyles() throws {
        let wallpaper = try XCTUnwrap(BackgroundPresets.wallpapers.first)
        let backgrounds: [BackgroundOrientationFixture] = [
            ("transparent", .transparent),
            ("solid", .solid(SerializableColor(red: 0, green: 0, blue: 0))),
            ("gradient", .gradient(BackgroundPresets.gradients[0])),
            ("wallpaper", .wallpaper(wallpaper))
        ]

        for (name, background) in backgrounds {
            let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
                background: background,
                padding: 0,
                backgroundRoundness: 0,
                backgroundShadow: 0,
                imageRoundness: 0,
                imageShadow: 0
            ))

            let data = try XCTUnwrap(
                renderer.renderPNG(from: makeProbeImage(rows: orientationProbeRows)),
                "Failed to render \(name) background"
            )

            XCTAssertEqual(try pixelSymbols(from: data), orientationProbeRows, name)
        }
    }

    func testRendererKeepsScreenshotOrientationInsidePadding() throws {
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .solid(SerializableColor(red: 0, green: 0, blue: 0)),
            padding: 2,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(rows: orientationProbeRows)))

        XCTAssertEqual(try pixelSymbols(from: data), [
            "KKKKKKK",
            "KKKKKKK",
            "KKRGBKK",
            "KKCYMKK",
            "KKKKKKK",
            "KKKKKKK"
        ])
    }

    func testRendererDrawsSelectedBackgroundInsidePadding() throws {
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .solid(SerializableColor(red: 1, green: 0, blue: 0)),
            padding: 1,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(rows: ["WW", "WW"])))

        XCTAssertEqual(try pixelSymbols(from: data), [
            "RRRR",
            "RWWR",
            "RWWR",
            "RRRR"
        ])
    }

    func testRendererKeepsTransparentBackgroundTransparent() throws {
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .transparent,
            padding: 1,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(rows: ["WW", "WW"])))

        XCTAssertEqual(try pixelSymbols(from: data), [
            "....",
            ".WW.",
            ".WW.",
            "...."
        ])
    }

    func testRendererScalesStylingForHighDPIImages() throws {
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .solid(SerializableColor(red: 1, green: 0, blue: 0)),
            padding: 2,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(
            rows: ["WW", "WW"],
            displaySize: NSSize(width: 1, height: 1)
        )))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(bitmap.pixelsWide, 10)
        XCTAssertEqual(bitmap.pixelsHigh, 10)
        XCTAssertEqual(
            try pixelSymbols(from: data, x: 4, y: 4, width: 2, height: 2),
            ["WW", "WW"]
        )
        XCTAssertEqual(
            try pixelSymbols(from: data, x: 0, y: 0, width: 3, height: 3),
            ["RRR", "RRR", "RRR"]
        )
    }

    func testCompositionLayoutKeepsPreviewPaddingProportionalToExport() {
        let configuration = ScreenshotExportConfiguration(
            background: .solid(SerializableColor(red: 1, green: 0, blue: 0)),
            padding: 80,
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: 0
        )

        let layout = ScreenshotCompositionLayout(
            configuration: configuration,
            imageSize: CGSize(width: 420, height: 260),
            styleScale: 1
        )
        let previewScale = layout.displayScale(toFit: CGSize(width: 812, height: 604))
        let previewBackgroundWidth = layout.backgroundRect.width * previewScale
        let previewImageWidth = layout.imageRect.width * previewScale
        let previewHorizontalPadding = (previewBackgroundWidth - previewImageWidth) / 2

        XCTAssertEqual(layout.backgroundRect.width, 580)
        XCTAssertEqual(layout.backgroundRect.height, 420)
        XCTAssertEqual(layout.imageRect.minX - layout.backgroundRect.minX, 80)
        XCTAssertEqual(layout.imageRect.minY - layout.backgroundRect.minY, 80)
        XCTAssertEqual(previewHorizontalPadding, 80 * previewScale, accuracy: 0.001)
    }

    func testRendererKeepsScreenshotOrientationInsideShadowMargin() throws {
        let imageShadow: Double = 0.25
        let padding: Int = 3
        let shadowMargin = Int(ceil(imageShadow * 56))
        let renderer = ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(
            background: .transparent,
            padding: Double(padding),
            backgroundRoundness: 0,
            backgroundShadow: 0,
            imageRoundness: 0,
            imageShadow: imageShadow
        ))

        let data = try XCTUnwrap(renderer.renderPNG(from: makeProbeImage(rows: orientationProbeRows)))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let expectedWidth = orientationProbeRows[0].count + padding * 2 + shadowMargin * 2
        let expectedHeight = orientationProbeRows.count + padding * 2 + shadowMargin * 2

        XCTAssertEqual(bitmap.pixelsWide, expectedWidth)
        XCTAssertEqual(bitmap.pixelsHigh, expectedHeight)
        XCTAssertEqual(
            try pixelSymbols(
                from: data,
                x: shadowMargin + padding,
                y: shadowMargin + padding,
                width: orientationProbeRows[0].count,
                height: orientationProbeRows.count
            ),
            orientationProbeRows
        )
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

    private func makeProbeImage(rows: [String], displaySize: NSSize? = nil) throws -> NSImage {
        let width = try XCTUnwrap(rows.first?.count)
        let height = rows.count
        XCTAssertTrue(rows.allSatisfy { $0.count == width })

        let pixels = try rows.flatMap { row in
            try row.flatMap { symbol in
                try rgbaComponents(for: symbol)
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let cgImage = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        return NSImage(cgImage: cgImage, size: displaySize ?? NSSize(width: width, height: height))
    }

    private func rgbaComponents(for symbol: Character) throws -> [UInt8] {
        switch symbol {
        case "R": [255, 0, 0, 255]
        case "G": [0, 255, 0, 255]
        case "B": [0, 0, 255, 255]
        case "C": [0, 255, 255, 255]
        case "Y": [255, 255, 0, 255]
        case "M": [255, 0, 255, 255]
        case "K": [0, 0, 0, 255]
        case "W": [255, 255, 255, 255]
        default:
            XCTFail("Unsupported probe symbol \(symbol)")
            throw ProbeImageError.unsupportedSymbol(symbol)
        }
    }

    private func pixelSymbols(
        from data: Data,
        x: Int = 0,
        y: Int = 0,
        width: Int? = nil,
        height: Int? = nil
    ) throws -> [String] {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let resolvedWidth = width ?? bitmap.pixelsWide - x
        let resolvedHeight = height ?? bitmap.pixelsHigh - y
        guard x >= 0, y >= 0, resolvedWidth >= 0, resolvedHeight >= 0,
              x + resolvedWidth <= bitmap.pixelsWide,
              y + resolvedHeight <= bitmap.pixelsHigh else {
            XCTFail("Requested pixel region is outside the rendered bitmap.")
            return []
        }

        return try (y..<(y + resolvedHeight)).map { sampleY in
            try (x..<(x + resolvedWidth)).map { sampleX in
                let color = try XCTUnwrap(bitmap.colorAt(x: sampleX, y: sampleY)?.usingColorSpace(.sRGB))
                return symbol(for: color)
            }
            .joined()
        }
    }

    private func symbol(for color: NSColor) -> String {
        if color.alphaComponent < 0.05 { return "." }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())

        if red < 80, green < 80, blue < 80 { return "K" }
        if red > 200, green < 100, blue < 100 { return "R" }
        if red < 100, green > 200, blue < 100 { return "G" }
        if red < 100, green < 100, blue > 200 { return "B" }
        if red < 100, green > 200, blue > 200 { return "C" }
        if red > 200, green < 100, blue > 200 { return "M" }
        if red > 200, green > 200, blue < 100 { return "Y" }
        if red > 200, green > 200, blue > 200 { return "W" }
        return "?"
    }

    private enum ProbeImageError: Error {
        case unsupportedSymbol(Character)
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
        let editor = ScreenshotEditorDriver()
        let background = BackgroundStyle.solid(BackgroundPresets.solidColors[1])

        editor.update(\.background, to: background)

        XCTAssertEqual(editor.state.screenshot.background, background)
        XCTAssertTrue(editor.canUndo)

        editor.undo()

        XCTAssertEqual(editor.state.screenshot.background, ScreenshotEditorState.default.background)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)

        editor.redo()

        XCTAssertEqual(editor.state.screenshot.background, background)
    }

    @MainActor
    func testSliderTransactionCollapsesScreenshotStyleChanges() {
        let editor = ScreenshotEditorDriver()

        editor.beginUndoTransaction()
        editor.update(\.padding, to: 72)
        editor.update(\.padding, to: 96)
        editor.endUndoTransaction()

        XCTAssertEqual(editor.state.screenshot.padding, 96)
        XCTAssertTrue(editor.canUndo)

        editor.undo()

        XCTAssertEqual(editor.state.screenshot.padding, ScreenshotEditorState.default.padding)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
    }

    @MainActor
    func testRedoIsClearedAfterNewScreenshotStyleChange() {
        let editor = ScreenshotEditorDriver()

        editor.update(\.padding, to: 72)
        editor.undo()
        XCTAssertTrue(editor.canRedo)

        editor.update(\.imageShadow, to: 0.2)

        XCTAssertFalse(editor.canRedo)
        XCTAssertEqual(editor.state.screenshot.imageShadow, 0.2, accuracy: 0.001)
    }

    @MainActor
    func testResetHistoryKeepsScreenshotStyleButClearsUndo() {
        let editor = ScreenshotEditorDriver()

        editor.update(\.imageRoundness, to: 24)
        XCTAssertTrue(editor.canUndo)

        editor.resetHistory()

        XCTAssertEqual(editor.state.screenshot.imageRoundness, 24, accuracy: 0.001)
        XCTAssertFalse(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
    }

    @MainActor
    func testSaveComposedPNGUsesCurrentScreenshotStyle() throws {
        let editor = ScreenshotEditorDriver()
        let image = NSImage(size: NSSize(width: 2, height: 2))
        let targetURL = URL(fileURLWithPath: "/tmp/styled-export.png")
        var renderedState: ScreenshotEditorState?
        var writtenURL: URL?
        var writtenData: Data?
        let background = BackgroundStyle.solid(SerializableColor(red: 1, green: 0, blue: 0))

        editor.configure(
            saveHandler: { _ in makeScreenshotProjectSummary() },
            statusHandler: { _ in },
            setStatusMessage: { _ in },
            renderPNG: { _, state in
                renderedState = state
                return Data("styled-png".utf8)
            },
            presentSaveURL: { suggestedName in
                XCTAssertEqual(suggestedName, "screen-export.png")
                return targetURL
            },
            writePNG: { data, url in
                writtenData = data
                writtenURL = url
            }
        )

        editor.update(\.background, to: background)
        editor.update(\.padding, to: 96)
        editor.update(\.backgroundRoundness, to: 44)
        editor.update(\.imageShadow, to: 0.15)
        editor.saveComposedPNG(image: image, suggestedFileName: "screen-export.png")

        let state = try XCTUnwrap(renderedState)
        XCTAssertEqual(state.background, background)
        XCTAssertEqual(state.padding, 96)
        XCTAssertEqual(state.backgroundRoundness, 44)
        XCTAssertEqual(state.imageShadow, 0.15, accuracy: 0.001)
        XCTAssertEqual(writtenURL, targetURL)
        XCTAssertEqual(writtenData, Data("styled-png".utf8))
    }

    @MainActor
    func testCopyComposedPNGUsesCurrentScreenshotStyle() throws {
        let editor = ScreenshotEditorDriver()
        let image = NSImage(size: NSSize(width: 2, height: 2))
        var renderedState: ScreenshotEditorState?
        var copiedData: Data?

        editor.configure(
            saveHandler: { _ in makeScreenshotProjectSummary() },
            statusHandler: { _ in },
            setStatusMessage: { _ in },
            renderPNG: { _, state in
                renderedState = state
                return Data("copied-png".utf8)
            },
            copyPNG: { data in
                copiedData = data
                return true
            }
        )

        editor.update(\.padding, to: 12)
        editor.update(\.imageRoundness, to: 22)
        editor.copyComposedPNG(image: image)

        let state = try XCTUnwrap(renderedState)
        XCTAssertEqual(state.padding, 12)
        XCTAssertEqual(state.imageRoundness, 22)
        XCTAssertEqual(copiedData, Data("copied-png".utf8))
    }
}

private func makeScreenshotProjectSummary() -> ProjectSummary {
    ProjectSummary(
        id: "screenshot-project",
        title: "Screenshot",
        path: "/tmp/screenshot.openrecorder",
        recordingPath: nil,
        screenshotPath: "/tmp/screenshot.png",
        sourceName: "Display",
        createdAt: "2026-05-20T00:00:00Z",
        updatedAt: "2026-05-20T00:00:00Z",
        lastOpenedAt: "2026-05-20T00:00:00Z",
        missing: false
    )
}
