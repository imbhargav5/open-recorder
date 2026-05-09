import AppKit
import Foundation

private struct CursorTelemetrySample: Codable {
    var x: Int
    var y: Int
    var timestamp: Int
    var cursorType: String
}

private struct CursorTelemetryPayload: Codable {
    var width: Int
    var height: Int
    var samples: [CursorTelemetrySample]
    var clicks: [String]
}

@MainActor
final class CursorTelemetryRecorder {
    private var timer: Timer?
    private var startedAt: Date?
    private var bounds: CGRect = .zero
    private var samples: [CursorTelemetrySample] = []

    var isRecording: Bool {
        timer != nil
    }

    func start(for source: CaptureSource?) {
        stop(videoURL: nil)

        bounds = captureBounds(for: source)
        startedAt = Date()
        samples = []
        sample()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    @discardableResult
    func stop(videoURL: URL?) -> URL? {
        timer?.invalidate()
        timer = nil

        guard let videoURL else {
            samples = []
            startedAt = nil
            return nil
        }

        let telemetryURL = videoURL
            .deletingPathExtension()
            .appendingPathExtension("cursor.json")
        let payload = CursorTelemetryPayload(
            width: max(Int(bounds.width.rounded()), 1),
            height: max(Int(bounds.height.rounded()), 1),
            samples: samples,
            clicks: []
        )

        do {
            let data = try JSONEncoder.prettyPrinted.encode(payload)
            try data.write(to: telemetryURL, options: .atomic)
            samples = []
            startedAt = nil
            return telemetryURL
        } catch {
            samples = []
            startedAt = nil
            return nil
        }
    }

    private func sample() {
        guard let startedAt else { return }
        let point = NSEvent.mouseLocation
        let relativeX = min(max(point.x - bounds.minX, 0), bounds.width)
        let relativeY = min(max(bounds.maxY - point.y, 0), bounds.height)
        let timestamp = Int(Date().timeIntervalSince(startedAt) * 1000)
        samples.append(CursorTelemetrySample(
            x: Int(relativeX.rounded()),
            y: Int(relativeY.rounded()),
            timestamp: timestamp,
            cursorType: "arrow"
        ))
    }

    private func captureBounds(for source: CaptureSource?) -> CGRect {
        if let area = source?.area {
            return CGRect(
                x: area.x,
                y: area.y,
                width: max(area.width, 1),
                height: max(area.height, 1)
            )
        }

        if let displayID = source?.displayID,
           let screen = NSScreen.screen(displayID: displayID) {
            return screen.frame
        }

        return NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension NSScreen {
    static func screen(displayID: UInt32) -> NSScreen? {
        screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}
