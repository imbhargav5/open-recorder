import AVFoundation
import XCTest
@testable import OpenRecorderMac

final class VideoExportCancellationIntegrationTests: XCTestCase {
    @MainActor func testCancelActiveExportThenExportAgain() async throws {
        guard let path = ProcessInfo.processInfo.environment["OPEN_RECORDER_EXPORT_CANCEL_FIXTURE"] else {
            throw XCTSkip("Set a local video fixture for real cancellation validation")
        }
        let source = URL(fileURLWithPath: path)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-cancellation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var options = VideoExportOptions.default
        options.resolution = .source
        options.frameRate = .fps30
        options.styling = VideoBackgroundStyling(background: BackgroundPresets.default, paddingRatio: 0.036,
            borderRadiusRatio: 0.04, shadowIntensity: 0.35, backgroundBlurRatio: 0, inset: .none)
        let diagnostics = VideoExportDiagnostics()
        let token = VideoExportCancellationToken()
        let task = Task {
            try await VideoExportRenderer.export(sourceURL: source, targetURL: root.appendingPathComponent("cancelled.mov"),
                options: options, cancellationToken: token, diagnostics: diagnostics)
        }
        for _ in 0..<500 {
            if diagnostics.snapshot().renderedFrames >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(diagnostics.snapshot().renderedFrames, 2, "Cancel admitted rendering work")
        token.cancel(); task.cancel()
        do {
            try await task.value
            XCTFail("Cancelled export reported success")
        } catch VideoExportRendererError.exportCancelled { }
        let finishedFrames = diagnostics.snapshot().renderedFrames
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(diagnostics.snapshot().renderedFrames, finishedFrames, "No stale completions after cancellation")
        let retry = root.appendingPathComponent("retry.mov")
        try await VideoExportRenderer.export(sourceURL: source, targetURL: retry, options: options)
        let asset = AVURLAsset(url: retry)
        let duration = try await asset.load(.duration).seconds
        let sourceDuration = try await AVURLAsset(url: source).load(.duration).seconds
        XCTAssertEqual(duration, sourceDuration, accuracy: 0.05)
        XCTAssertGreaterThan(try retry.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
    }
}
