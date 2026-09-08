import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Darwin
import Foundation
import XCTest
@testable import OpenRecorderMac

/// Explicit opt-in: JSON manifest + output directory; no timing thresholds in CI.
final class VideoExportBenchmarkTests: XCTestCase {
    struct Fixture: Decodable {
        let name: String
        let path: String
        var appearance: String = "wallpaper"
        var fps: Double = 30
        var repeats: Int = 5
        var warmup: Bool = true
        enum CodingKeys: String, CodingKey { case name, path, appearance, fps, repeats, warmup }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            path = try c.decode(String.self, forKey: .path)
            appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "wallpaper"
            fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? 30
            repeats = try c.decodeIfPresent(Int.self, forKey: .repeats) ?? 5
            warmup = try c.decodeIfPresent(Bool.self, forKey: .warmup) ?? true
        }
    }
    struct Media: Codable {
        let width: Double, height: Double, duration: Double, nominalFPS: Double
        let frames: Int
        let firstPTS: Double, lastPTS: Double
        let monotonic: Bool
        let maximumFrameIntervalError: Double
        let audioTracks: Int
    }
    struct Run: Codable {
        let fixture: String, appearance: String, revision: String, configuration: String
        let warmup: Bool, detailed: Bool
        let requestedFPS: Double
        let input: Media, output: Media
        let exportSeconds: Double, saveSeconds: Double
        let rssSamples: [UInt64]
        let peakResidentBytes: UInt64
        let composition: VideoExportDiagnostics.Snapshot
    }
    final class MemorySamples: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [UInt64] = []
        func sample() {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { p in
                p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS { lock.lock(); samples.append(info.resident_size); lock.unlock() }
        }
        func snapshot() -> [UInt64] { lock.lock(); defer { lock.unlock() }; return samples }
    }

    final class FrameCapture: @unchecked Sendable {
        let directory: URL
        let context = CIContext(options: [.cacheIntermediates: false])
        let lock = NSLock()
        init(_ directory: URL) { self.directory = directory }
        func capture(_ buffer: CVPixelBuffer, time: Double) {
            guard [0.0, 1.0, 2.0].contains(where: { abs($0 - time) < 0.0001 }) else { return }
            lock.lock(); defer { lock.unlock() }
            let source = CIImage(cvPixelBuffer: buffer)
            guard let image = context.createCGImage(source, from: source.extent),
                  let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent("frame-\(Int(time)).png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, image, nil)
            _ = CGImageDestinationFinalize(destination)
        }
    }

    @MainActor func testExportBenchmarks() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let manifest = env["OPEN_RECORDER_EXPORT_BENCH_MANIFEST"],
              let resultPath = env["OPEN_RECORDER_EXPORT_BENCH_OUTPUT"] else {
            throw XCTSkip("Set explicit benchmark manifest and output directory")
        }
        let root = URL(fileURLWithPath: resultPath, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
        var results: [Run] = []
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        for fixture in fixtures {
            let source = URL(fileURLWithPath: fixture.path)
            let input = try await metadata(source)
            var options = VideoExportOptions.default
            options.resolution = .source
            options.frameRate = fixture.fps == 60 ? .fps60 : .fps30
            XCTAssertTrue([30, 60].contains(fixture.fps))
            if fixture.appearance != "plain" {
                options.styling = VideoBackgroundStyling(background: BackgroundPresets.default,
                    paddingRatio: 0.036, borderRadiusRatio: fixture.appearance == "rounded" ? 0.04 : 0,
                    shadowIntensity: 0.35, backgroundBlurRatio: fixture.appearance == "blur" ? 0.04 : 0, inset: .none)
            }
            if fixture.appearance == "facecam" {
                options.facecamVideoURL = source
                options.facecamFallbackSettings = defaultFacecamSettings(enabled: true)
            }
            for index in (fixture.warmup ? 0 : 1)...max(1, fixture.repeats) {
                let captureDirectory = root.appendingPathComponent("\(fixture.name)-\(index)-frames", isDirectory: true)
                let capturing = env["OPEN_RECORDER_EXPORT_CAPTURE_FRAMES"] == "1"
                if capturing { try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true) }
                let observer: (@Sendable (CVPixelBuffer, Double) -> Void)?
                if capturing {
                    let capture = FrameCapture(captureDirectory)
                    observer = { buffer, time in capture.capture(buffer, time: time) }
                }
                else { observer = nil }
                let diagnostics = VideoExportDiagnostics(detailed: env["OPEN_RECORDER_EXPORT_DIAGNOSTICS"] == "1", frameObserver: observer)
                let output = root.appendingPathComponent("\(fixture.name)-\(index).mov")
                let saved = root.appendingPathComponent("\(fixture.name)-\(index)-saved.mov")
                let memory = MemorySamples()
                memory.sample()
                let timer = Task.detached {
                    while !Task.isCancelled {
                        memory.sample()
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
                let start = ContinuousClock.now
                do {
                    try await VideoExportRenderer.export(sourceURL: source, targetURL: output, options: options, diagnostics: diagnostics)
                } catch { timer.cancel(); throw error }
                let exportSeconds = seconds(start.duration(to: .now))
                memory.sample(); timer.cancel()
                await timer.value
                let saveStart = ContinuousClock.now
                if FileManager.default.fileExists(atPath: saved.path) { try FileManager.default.removeItem(at: saved) }
                try FileManager.default.copyItem(at: output, to: saved)
                let saveSeconds = seconds(saveStart.duration(to: .now))
                try FileManager.default.removeItem(at: saved)
                let actual = try await metadata(output)
                let samples = memory.snapshot()
                results.append(Run(fixture: fixture.name, appearance: fixture.appearance,
                    revision: env["OPEN_RECORDER_EXPORT_REVISION"] ?? "unspecified", configuration: configuration,
                    warmup: index == 0, detailed: diagnostics.detailed, requestedFPS: fixture.fps,
                    input: input, output: actual, exportSeconds: exportSeconds, saveSeconds: saveSeconds,
                    rssSamples: samples, peakResidentBytes: samples.max() ?? 0, composition: diagnostics.snapshot()))
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(results).write(to: root.appendingPathComponent("results.json"), options: .atomic)
                XCTAssertEqual(actual.duration, input.duration, accuracy: 0.05, fixture.name)
                XCTAssertEqual(actual.width, input.width, fixture.name)
                XCTAssertEqual(actual.height, input.height, fixture.name)
                XCTAssertEqual(actual.nominalFPS, fixture.fps, accuracy: 0.01, "Requested FPS mismatch: \(fixture.name)")
                XCTAssertEqual(actual.frames, Int(ceil(actual.duration * fixture.fps - 0.000001)), fixture.name)
                XCTAssertEqual(actual.audioTracks, input.audioTracks, fixture.name)
                XCTAssertTrue(actual.monotonic, fixture.name)
                XCTAssertLessThanOrEqual(actual.maximumFrameIntervalError, 0.001, fixture.name)
                print("EXPORT_BENCH \(fixture.name) run=\(index) seconds=\(exportSeconds) frames=\(actual.frames)")
            }
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    @MainActor private func metadata(_ url: URL) async throws -> Media {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        let fps = try await track.load(.nominalFrameRate)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        if reader.status == .failed { throw reader.error! }
        // Decode frames: compressed samples may include encoder preroll and duplicates.
        // Preserve decoder presentation order so timestamp regressions fail validation.
        return Media(width: size.width, height: size.height, duration: duration, nominalFPS: Double(fps),
                     frames: times.count, firstPTS: times.first ?? 0, lastPTS: times.last ?? 0,
                     monotonic: zip(times, times.dropFirst()).allSatisfy { $0 < $1 },
                     maximumFrameIntervalError: zip(times, times.dropFirst()).map { abs(($1 - $0) - 1 / Double(fps)) }.max() ?? 0,
                     audioTracks: try await asset.loadTracks(withMediaType: .audio).count)
    }
}
