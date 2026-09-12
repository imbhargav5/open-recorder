import AVFoundation
import AppKit
import CoreImage
import ImageIO
import Metal
import SwiftUI
import XCTest
@testable import OpenRecorderMac

@MainActor
final class SceneTests: XCTestCase {
    func testLegacyProjectsRemainFlatAndUseAutomaticCanvas() throws {
        for data in [Data("{}".utf8)] {
            let video = try JSONDecoder().decode(ProjectVideoEditorState.self, from: data)
            let image = try JSONDecoder().decode(ScreenshotEditorState.self, from: data)
            XCTAssertFalse(video.scene.isActive)
            XCTAssertFalse(image.scene.isActive)
            XCTAssertEqual(video.canvasAspect, .auto)
            XCTAssertEqual(image.canvasAspect, .auto)
        }
        var video = ProjectVideoEditorState.default
        video.scene.pose = ScenePosePreset.elevated.pose
        video.scene.motion.enabled = true
        video.canvasAspect = .vertical
        XCTAssertEqual(try JSONDecoder().decode(ProjectVideoEditorState.self, from: JSONEncoder().encode(video)), video)
        var image = ScreenshotEditorState.default
        image.scene = video.scene
        image.canvasAspect = .square
        XCTAssertEqual(try JSONDecoder().decode(ScreenshotEditorState.self, from: JSONEncoder().encode(image)), image)
    }

    func testMotionHoldsEndpointsAndClampsShortenedOutput() {
        var motion = SceneMotion(enabled: true, startTime: 2, endTime: 6,
                                 startPose: ScenePose(tiltY: -20, x: -0.2), endPose: ScenePose(tiltY: 20, x: 0.2), easing: .linear)
        XCTAssertEqual(motion.pose(at: 0), motion.startPose)
        XCTAssertEqual(motion.pose(at: 7), motion.endPose)
        XCTAssertEqual(motion.pose(at: 4).tiltY, 0, accuracy: 0.0001)
        motion = motion.clamped(to: 1)
        XCTAssertGreaterThan(motion.endTime, motion.startTime)
        XCTAssertEqual(motion.endTime, 1)
        XCTAssertEqual(motion.clamped(to: 0).endTime, 0)
        for easing in SceneEasing.allCases {
            XCTAssertEqual(easing.evaluate(-1), 0)
            XCTAssertEqual(easing.evaluate(2), 1)
        }
    }

    func testMotionUsesOutputTimeAcrossCutsAndSpeedChanges() {
        var edits = TimelineEditSnapshot.empty
        edits.trimRegions = [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 4))]
        edits.clipSplitTimes = [4]
        edits.clipSpeeds = [1: 2]
        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)
        XCTAssertEqual(plan.outputDuration, 4)
        XCTAssertEqual(plan.sourceTime(forOutputTime: 2), 4)
        XCTAssertEqual(plan.outputTime(forSourceTime: 6), 3)
        let motion = SceneMotion(enabled: true, startTime: 0, endTime: 4,
                                 startPose: ScenePose(x: 0), endPose: ScenePose(x: 1), easing: .linear)
        XCTAssertEqual(motion.pose(at: plan.outputTime(forSourceTime: 6)!).x, 0.75, accuracy: 0.0001)
    }

    func testVideoAndImageDragsAreSingleUndoSteps() {
        let video = VideoEditorDriver()
        video.beginUndoTransaction()
        for angle in [5.0, 10, 20] { video.binding(\.scene.pose.tiltY).wrappedValue = angle }
        video.endUndoTransaction()
        video.undo()
        XCTAssertEqual(video.state.video.scene.pose.tiltY, 0)
        XCTAssertFalse(video.canUndo)
        video.redo()
        XCTAssertEqual(video.state.video.scene.pose.tiltY, 20)
        let image = ScreenshotEditorDriver()
        image.beginUndoTransaction()
        for angle in [5.0, 10, 20] { image.binding(for: \.scene.pose.tiltY).wrappedValue = angle }
        image.endUndoTransaction()
        image.undo()
        XCTAssertEqual(image.state.screenshot.scene.pose.tiltY, 0)
        XCTAssertFalse(image.canUndo)
    }

    func testSafeProjectionAndMockupFit() {
        let frame = CGRect(x: 40, y: 40, width: 320, height: 180)
        let canvas = CGSize(width: 400, height: 260)
        let identity = SceneGeometry.evaluate(frame: frame, canvas: canvas, pose: .identity)
        XCTAssertEqual(identity.bounds, frame)
        for x in stride(from: -60.0, through: 60, by: 15) {
            for y in stride(from: -60.0, through: 60, by: 15) {
                let geometry = SceneGeometry.evaluate(frame: frame, canvas: canvas, pose: ScenePose(tiltX: x, tiltY: y, perspective: 1))
                XCTAssertTrue(geometry.bounds.width.isFinite)
                XCTAssertTrue(geometry.bounds.height.isFinite)
                XCTAssertGreaterThan(geometry.bounds.width, 0)
            }
        }
        for mockup in MockupStyle.allCases {
            let layout = SceneMockupLayout.make(in: frame, mediaAspect: 16 / 9, style: mockup, radius: 0)
            XCTAssertEqual(layout.content.width / layout.content.height, 16 / 9, accuracy: 0.001)
            XCTAssertTrue(frame.contains(layout.frame))
        }
        XCTAssertTrue(ScenePose(tiltX: .infinity, tiltY: .nan, scale: .nan).clamped.isIdentity)
    }

    func testSceneScreenshotPreservesOrientationAndTransparentCorners() throws {
        let image = try fixtureImage()
        var state = bareImageState()
        state.scene.pose.scale = 0.8
        let cg = try XCTUnwrap(ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(screenshotState: state)).renderImage(from: image))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let topLeft = try XCTUnwrap(bitmap.colorAt(x: 90, y: 55)?.usingColorSpace(.deviceRGB))
        let bottomRight = try XCTUnwrap(bitmap.colorAt(x: 225, y: 125)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(topLeft.redComponent, 0.8)
        XCTAssertLessThan(topLeft.blueComponent, 0.2)
        XCTAssertGreaterThan(bottomRight.blueComponent, 0.8)
        XCTAssertLessThan(bottomRight.redComponent, 0.2)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
    }

    func testMetalPreviewOrientationMatchesPNG() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 320, height: 180, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let context = CIContext(mtlDevice: device)
        let cg = try XCTUnwrap(try fixtureImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        SceneMetalDisplay.render(CIImage(cgImage: cg), context: context, texture: texture, commandBuffer: command)
        command.commit(); command.waitUntilCompleted()
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: 4, from: MTLRegionMake2D(80, 45, 1, 1), mipmapLevel: 0)
        XCTAssertGreaterThan(pixel[2], 200, "Metal's displayed top-left must match the red top-left in PNG")
        XCTAssertLessThan(pixel[0], 30)
    }

    func testAnimatedStillCopyUsesDisplayedPose() {
        let driver = ScreenshotEditorDriver()
        var received: ScreenshotEditorState?
        driver.configure(saveHandler: { _ in throw CancellationError() }, statusHandler: { _ in }, setWorkspaceStatus: { _ in },
            renderPNG: { _, state in received = state; return Data([1]) }, copyPNG: { _ in true })
        var scene = SceneSettings()
        scene.motion.enabled = true
        scene.motion.easing = .linear
        driver.binding(for: \.scene).wrappedValue = scene
        driver.scenePreviewTime = 1.5
        driver.copyComposedPNG(image: NSImage(size: CGSize(width: 1, height: 1)))
        XCTAssertEqual(received?.scene.pose.scale ?? 0, 0.9, accuracy: 0.001)
        XCTAssertFalse(received?.scene.motion.enabled ?? true)
        XCTAssertTrue(driver.state.screenshot.scene.motion.enabled)
    }

    func testImageExportsFormatsAndCancellationPreserveSource() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png")
        let image = try fixtureImage()
        let original = try XCTUnwrap(ScreenshotExportRenderer(configuration: ScreenshotExportConfiguration(screenshotState: bareImageState())).renderPNG(from: image))
        try original.write(to: source)
        var state = bareImageState()
        state.scene.imageDuration = 0.4
        state.scene.motion.enabled = true
        state.scene.motion = state.scene.motion.clamped(to: 0.4)
        state.scene.mockup = .browser
        state.scene.motion.startPose = ScenePosePreset.left.pose
        var options = VideoExportOptions.default
        options.resolution = .source
        options.frameRate = .fps15
        options.gifSize = .original
        options.screenshotState = state
        for format in VideoExportFormat.allCases {
            options.format = format
            let target = root.appendingPathComponent("scene.\(format.fileExtension)")
            try await VideoExportRenderer.export(sourceURL: source, targetURL: target, options: options)
            if format == .gif {
                let gif = try XCTUnwrap(CGImageSourceCreateWithURL(target as CFURL, nil))
                XCTAssertEqual(CGImageSourceGetCount(gif), 6)
            } else {
                let duration = try await AVURLAsset(url: target).load(.duration).seconds
                XCTAssertEqual(duration, 0.4, accuracy: 0.01)
            }
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        let cancelled = root.appendingPathComponent("cancelled.mov")
        let token = VideoExportCancellationToken()
        options.format = .mov
        do {
            try await VideoExportRenderer.export(sourceURL: source, targetURL: cancelled, options: options, cancellationToken: token) { progress in
                if progress > 0 { token.cancel() }
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
        do {
            try await VideoExportRenderer.export(sourceURL: source, targetURL: source, options: options)
            XCTFail("Original must be protected")
        } catch ExportFileSafety.Failure.originalFile { }
        XCTAssertEqual(try Data(contentsOf: source), original)
        let alias = root.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        XCTAssertTrue(ExportFileSafety.sameFile(alias, source))
    }

    func testAtomicExportReplacementAndFailure() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("new"), target = root.appendingPathComponent("export")
        try Data("old".utf8).write(to: target)
        XCTAssertThrowsError(try ExportFileSafety.install(source: source, destination: target))
        XCTAssertEqual(try Data(contentsOf: target), Data("old".utf8))
        try Data("new".utf8).write(to: source)
        try ExportFileSafety.install(source: source, destination: target)
        XCTAssertEqual(try Data(contentsOf: target), Data("new".utf8))
    }

    func testVideoSceneExportWithAudioCutsZoomAndFacecam() async throws {
        guard let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_SCENE_QA_ROOT"] else {
            throw XCTSkip("Set OPEN_RECORDER_SCENE_QA_ROOT to a directory containing source.mp4 for native media QA")
        }
        let root = URL(fileURLWithPath: path)
        let source = root.appendingPathComponent("source.mp4")
        var edits = TimelineEditSnapshot.empty
        edits.trimRegions = [TimelineTrimRegion(span: TimelineSpan(start: 1, end: 2))]
        edits.clipSplitTimes = [4]
        edits.clipSpeeds = [1: 2]
        edits.zoomRegions = [TimelineZoomRegion(span: TimelineSpan(start: 2.5, end: 4), depth: 1.5)]
        var options = VideoExportOptions.default
        options.resolution = .p720
        options.frameRate = .fps30
        options.styling = VideoBackgroundStyling(background: .solid(SerializableColor(hex: "#123456")),
            paddingRatio: 0.08, borderRadiusRatio: 0.025, shadowIntensity: 0.5, backgroundBlurRatio: 0, inset: .none)
        options.scene.mockup = .browser
        options.scene.motion.enabled = true
        options.scene.motion.startPose = ScenePosePreset.left.pose
        options.scene.motion.endPose = ScenePosePreset.right.pose
        options.scene.motion.endTime = 3
        options.facecamVideoURL = source
        options.facecamFallbackSettings = defaultFacecamSettings(enabled: true)
        let captures = root.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        let capture = VideoExportBenchmarkTests.FrameCapture(captures)
        let diagnostics = VideoExportDiagnostics(detailed: true, frameObserver: { buffer, time in capture.capture(buffer, time: time) })
        let start = ContinuousClock.now
        let target = root.appendingPathComponent("scene-video.mov")
        try await VideoExportRenderer.export(sourceURL: source, targetURL: target, options: options, edits: edits, diagnostics: diagnostics)
        let elapsed = start.duration(to: .now)
        let asset = AVURLAsset(url: target)
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(duration, 4, accuracy: 0.05)
        XCTAssertEqual(audio.count, 1)
        XCTAssertGreaterThan(diagnostics.snapshot().renderedFrames, 100)
        print("SCENE_VIDEO_QA elapsed=\(elapsed) frames=\(diagnostics.snapshot().renderedFrames) kernelSeconds=\(diagnostics.snapshot().kernelSeconds)")
        // Transparent, unpadded scenes must still select the custom compositor.
        options.styling = .none
        options.facecamVideoURL = nil
        options.facecamFallbackSettings = nil
        options.scene.motion.enabled = false
        options.scene.pose = ScenePosePreset.elevated.pose
        let plainDiagnostics = VideoExportDiagnostics()
        options.format = .mp4
        try await VideoExportRenderer.export(sourceURL: source, targetURL: root.appendingPathComponent("scene-unpadded.mp4"),
            options: options, diagnostics: plainDiagnostics)
        XCTAssertGreaterThan(plainDiagnostics.snapshot().renderedFrames, 150)
        options.format = .gif
        options.gifSize = .medium
        options.frameRate = .fps15
        try await VideoExportRenderer.export(sourceURL: source, targetURL: root.appendingPathComponent("scene-video.gif"), options: options)
        let gif = try XCTUnwrap(CGImageSourceCreateWithURL(root.appendingPathComponent("scene-video.gif") as CFURL, nil))
        XCTAssertGreaterThan(CGImageSourceGetCount(gif), 80)
    }

    func testSceneInspectorLayoutAndImageRenderTiming() throws {
        guard let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_SCENE_QA_ROOT"] else {
            throw XCTSkip("Set OPEN_RECORDER_SCENE_QA_ROOT for offscreen layout and render measurements")
        }
        let root = URL(fileURLWithPath: path)
        var scene = SceneSettings()
        scene.pose = ScenePosePreset.left.pose
        scene.mockup = .browser
        scene.motion.enabled = true
        let host = NSHostingView(rootView: SceneInspector(settings: .constant(scene), endpoint: .constant(.start), duration: 3)
            .padding(14).frame(width: 230).background(Theme.sidebarBg).environment(\.colorScheme, .dark))
        host.setFrameSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent("scene-inspector.png"))
        }
        let image = try XCTUnwrap(NSImage(contentsOf: root.appendingPathComponent("source.png")))
        var state = bareImageState()
        state.scene = scene
        state.padding = 80
        state.imageShadow = 0.4
        state.background = .solid(SerializableColor(hex: "#123456"))
        let renderer = SceneRenderer()
        let start = ContinuousClock.now
        for frame in 0..<120 {
            try autoreleasepool {
                var config = ScreenshotExportConfiguration(screenshotState: state)
                config.sceneTime = Double(frame) / 40
                let output = try XCTUnwrap(ScreenshotExportRenderer(configuration: config).renderImage(from: image, maxDimension: 1600, renderer: renderer))
                if [0, 60, 119].contains(frame) {
                    try NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent("image-frame-\(frame).png"))
                }
            }
        }
        print("SCENE_IMAGE_QA frames=120 elapsed=\(start.duration(to: .now))")
    }

    private func bareImageState() -> ScreenshotEditorState {
        ScreenshotEditorState(background: .transparent, padding: 0, backgroundRoundness: 0, backgroundShadow: 0, imageRoundness: 0, imageShadow: 0)
    }
    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scene-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func fixtureImage() throws -> NSImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 90, width: 160, height: 90))
        let image = try XCTUnwrap(context.makeImage())
        return NSImage(cgImage: image, size: CGSize(width: 320, height: 180))
    }
}
