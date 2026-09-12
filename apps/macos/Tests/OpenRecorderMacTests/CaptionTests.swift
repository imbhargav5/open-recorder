import AVFoundation
import CoreImage
import XCTest
import SwiftUI
@testable import OpenRecorderMac

final class CaptionTests: XCTestCase {
    func testLegacyProjectAndCaptionRoundTrip() throws {
        let legacy = try JSONDecoder().decode(ProjectEditorState.self, from: Data("{\"timelineEdits\":{}}".utf8))
        XCTAssertNil(legacy.timelineEdits.captions)
        var snapshot = TimelineEditSnapshot.empty
        snapshot.captions = CaptionTrack(segments: [.init(start: 0.25, end: 2.5, text: "Hello, ప్రపంచం!")])
        let state = ProjectEditorState(timelineEdits: snapshot)
        XCTAssertEqual(try JSONDecoder().decode(ProjectEditorState.self, from: JSONEncoder().encode(state)), state)
    }

    @MainActor func testCaptionAndTimelineChangesShareUndoAndAreWorkspaceIsolated() {
        let first = EditorWorkspaceDriver()
        let second = EditorWorkspaceDriver()
        let track = CaptionTrack(segments: [.init(start: 0, end: 1, text: "Hello")])
        first.timeline.send(.replaceCaptions(track))
        first.timeline.addClipSplit(at: 1, duration: 3)
        first.timeline.undo()
        XCTAssertEqual(first.timeline.snapshot.captions, track)
        XCTAssertTrue(first.timeline.snapshot.clipSplitTimes.isEmpty)
        first.timeline.undo()
        XCTAssertNil(first.timeline.snapshot.captions)
        first.timeline.redo()
        XCTAssertEqual(first.timeline.snapshot.captions, track)
        XCTAssertNil(second.timeline.snapshot.captions)
    }

    func testOllamaValidationPreservesWordsIDsAndTiming() throws {
        let original = [CaptionSegment(start: 1.25, end: 3.75, text: "hello world")]
        func json(_ text: String, id: String? = nil) throws -> Data {
            try JSONEncoder().encode(OllamaCaptionService.Payload(captions: [.init(id: id ?? original[0].id.uuidString, text: text)]))
        }
        let valid = try OllamaCaptionService.validated(json("Hello, world!"), original: original)
        XCTAssertEqual(valid[0].start, 1.25)
        XCTAssertEqual(valid[0].end, 3.75)
        XCTAssertEqual(valid[0].id, original[0].id)
        XCTAssertThrowsError(try OllamaCaptionService.validated(json("Hello, new world!"), original: original))
        XCTAssertThrowsError(try OllamaCaptionService.validated(json("Hello, world!", id: "wrong"), original: original))
        XCTAssertThrowsError(try OllamaCaptionService.validated(Data("{\"captions\":[]}".utf8), original: original))
        XCTAssertThrowsError(try OllamaCaptionService.validated(Data("not json".utf8), original: original))
    }

    func testWhisperOffsetsAndSilence() throws {
        let data = Data("""
        {"transcription":[
          {"offsets":{"from":350,"to":1800},"text":" Hello "},
          {"offsets":{"from":1800,"to":2300},"text":"[BLANK_AUDIO]"},
          {"offsets":{"from":2300,"to":2300},"text":"Invalid"}
        ]}
        """.utf8)
        let result = try LocalCaptionSpeechService.parse(data)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0.35)
        XCTAssertEqual(result[0].end, 1.8)
        XCTAssertEqual(result[0].text, "Hello")
        XCTAssertEqual(try LocalCaptionSpeechService.parse(Data("{\"transcription\":[]}".utf8)), [])
    }

    func testCaptionTimingFollowsTrimAndSpeed() {
        var edits = TimelineEditSnapshot(clipSplitTimes: [2], clipSpeeds: [1: 2])
        edits.trimRegions = [.init(span: .init(start: 0, end: 1))]
        let track = CaptionTrack(segments: [.init(start: 2, end: 4, text: "Fast caption")])
        edits.captions = track
        let plan = TimelineExportEditPlan.build(duration: 5, edits: edits)
        XCTAssertNil(plan.outputTime(forSourceTime: 0.5))
        XCTAssertEqual(plan.outputTime(forSourceTime: 3) ?? -1, 1.5, accuracy: 0.001)
        XCTAssertEqual(track.active(at: plan.sourceTime(forOutputTime: 1.5)!)?.text, "Fast caption")
        XCTAssertNil(track.active(at: 4), "End time is exclusive")
    }

    func testRendererFitsTwoLinesAndScalesAcrossCanvases() throws {
        let texts = ["Hello, world!", "తెలుగు captions 日本語字幕 مرحبا بالعالم", String(repeating: "Long caption words ", count: 15)]
        for text in texts {
            for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 640, height: 360)] {
                let raster = try XCTUnwrap(CaptionRenderer.render(text: text, style: .init(), canvas: size))
                XCTAssertGreaterThan(raster.frame.minY, 0)
                XCTAssertLessThanOrEqual(raster.frame.maxX, size.width)
                XCTAssertLessThan(raster.frame.maxY, size.height)
                XCTAssertGreaterThan(raster.image.width, 0)
                var top = CaptionStyle(); top.position = .top
                let topRaster = try XCTUnwrap(CaptionRenderer.render(text: text, style: top, canvas: size))
                XCTAssertEqual(topRaster.frame.maxY, size.height * 0.94, accuracy: 1)
            }
        }
    }

    @MainActor func testSetupRequiresAudioModelAndLocalOllama() async throws {
        let defaults = UserDefaults(suiteName: "caption-test-\(UUID())")!
        defaults.set("missing-saved-model", forKey: "captions.ollamaModel")
        let controller = CaptionController(ollama: FakeCaptionOllama(), defaults: defaults, environment: .fixture)
        controller.attach(URL(fileURLWithPath: "/test.mov"))
        try await settle(controller)
        XCTAssertEqual(controller.selectedModel, "missing-saved-model")
        XCTAssertFalse(controller.canGenerate)
        controller.selectedModel = "llama3:latest"
        XCTAssertTrue(controller.canGenerate)
        controller.close()
        var noAudio = CaptionEnvironment.fixture
        noAudio.hasAudio = { _ in false }
        let silent = CaptionController(ollama: FakeCaptionOllama(), defaults: defaults, environment: noAudio)
        silent.attach(URL(fileURLWithPath: "/silent.mov"))
        try await settle(silent)
        XCTAssertEqual(silent.hasAudio, false)
        XCTAssertFalse(silent.canGenerate)
    }

    @MainActor func testCleanupFailureRetainsTranscriptAndRetryCommitsAtomically() async throws {
        let ollama = FakeCaptionOllama(failures: 1)
        let speech = FakeCaptionSpeech()
        let controller = CaptionController(speech: speech, ollama: ollama,
            defaults: UserDefaults(suiteName: "caption-test-\(UUID())")!, environment: .fixture)
        controller.attach(URL(fileURLWithPath: "/test.mov"))
        try await settle(controller)
        let old = CaptionTrack(segments: [.init(start: 0, end: 1, text: "Old caption")])
        var saved = old
        controller.generate(existing: old) { saved = $0 }
        try await settle(controller)
        XCTAssertEqual(saved, old)
        XCTAssertNotNil(controller.pendingTranscript)
        XCTAssertNotNil(controller.error)
        controller.retryCleanup(existing: saved) { saved = $0 }
        try await settle(controller)
        XCTAssertEqual(saved.segments.first?.text, "Hello, world!")
        XCTAssertNil(controller.pendingTranscript)
        let calls = await speech.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testCancelAndStaleResultNeverReplaceTrack() async throws {
        let controller = CaptionController(speech: FakeCaptionSpeech(delay: true), ollama: FakeCaptionOllama(),
            defaults: UserDefaults(suiteName: "caption-test-\(UUID())")!, environment: .fixture)
        controller.attach(URL(fileURLWithPath: "/test.mov"))
        try await settle(controller)
        var committed = false
        controller.generate(existing: nil) { _ in committed = true }
        try await Task.sleep(for: .milliseconds(20))
        controller.close()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(committed)
        XCTAssertFalse(controller.isBusy)
        controller.attach(URL(fileURLWithPath: "/other.mov"))
        try await settle(controller)
        controller.generate(existing: nil, isCurrent: { false }) { _ in committed = true }
        try await settle(controller)
        XCTAssertFalse(committed)
        XCTAssertNotNil(controller.error)
    }

    @MainActor func testMissingHelperAndDownloadFailureRemainActionable() async throws {
        var environment = CaptionEnvironment.fixture
        environment.helperReady = { false }
        environment.modelReady = { false }
        environment.download = { _ in throw CaptionFailure.message("Download failed") }
        let controller = CaptionController(ollama: FakeCaptionOllama(),
            defaults: UserDefaults(suiteName: "caption-test-\(UUID())")!, environment: environment)
        controller.attach(URL(fileURLWithPath: "/test.mov"))
        try await settle(controller)
        XCTAssertFalse(controller.canGenerate)
        controller.downloadSpeechModel()
        try await settle(controller)
        XCTAssertFalse(controller.speechReady)
        XCTAssertEqual(controller.error, "Download failed")
        XCTAssertFalse(controller.isBusy)
    }

    @MainActor func testInspectorLayoutSnapshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_CAPTION_ARTIFACTS"] else {
            throw XCTSkip("Set an artifact directory for inspector layout snapshots")
        }
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for ready in [false, true] {
            var environment = CaptionEnvironment.fixture
            environment.modelReady = { ready }
            let controller = CaptionController(ollama: FakeCaptionOllama(),
                defaults: UserDefaults(suiteName: "caption-test-\(UUID())")!, environment: environment)
            controller.attach(URL(fileURLWithPath: "/test.mov"))
            try await settle(controller)
            let edits = TimelineEditDriver()
            if ready {
                edits.send(.replaceCaptions(CaptionTrack(segments: [
                    .init(start: 0, end: 3, text: "Welcome to Open Recorder."),
                    .init(start: 3, end: 6, text: "Generate captions entirely on your Mac.")
                ])))
            }
            let view = NSHostingView(rootView:
                ScrollView { CaptionInspector(controller: controller, edits: edits, playback: VideoPlaybackController()).padding(16) }
                    .frame(width: 320, height: 880).background(Theme.sidebarBg).environment(\.colorScheme, .dark))
            view.appearance = NSAppearance(named: .darkAqua)
            view.frame = CGRect(x: 0, y: 0, width: 320, height: 880)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: root.appendingPathComponent(ready ? "inspector-editing.png" : "inspector-setup.png"))
            controller.close()
        }
    }

    @MainActor private func settle(_ controller: CaptionController) async throws {
        for _ in 0..<400 {
            if !controller.isBusy && !controller.isChecking { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Caption operation timed out")
    }
}

private extension CaptionEnvironment {
    static var fixture: Self {
        .init(modelReady: { true }, helperReady: { true }, hasAudio: { _ in true }, prepare: { _, _ in }, download: { _ in })
    }
}

private actor FakeCaptionSpeech: CaptionTranscribing {
    var calls = 0
    var delay: Bool
    init(delay: Bool = false) { self.delay = delay }
    func transcribe(audio: URL, language: String, progress: @escaping @Sendable (Double) -> Void) async throws -> [CaptionSegment] {
        calls += 1
        if delay { try? await Task.sleep(for: .milliseconds(100)) }
        return [.init(start: 0, end: 1, text: "hello world")]
    }
}

private actor FakeCaptionOllama: CaptionCleaning {
    var failures: Int
    init(failures: Int = 0) { self.failures = failures }
    func models() async throws -> [String] { ["llama3:latest"] }
    func clean(_ segments: [CaptionSegment], model: String) async throws -> [CaptionSegment] {
        if failures > 0 { failures -= 1; throw CaptionFailure.message("Model unavailable") }
        return segments.map { var value = $0; value.text = "Hello, world!"; return value }
    }
}
