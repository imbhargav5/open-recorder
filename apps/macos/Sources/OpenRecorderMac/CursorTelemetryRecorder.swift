import AppKit
import Foundation

struct CursorTelemetrySample: Codable, Equatable {
    var x: Int
    var y: Int
    var timestamp: Int
    var cursorType: String
}

struct CursorTelemetryClick: Codable, Equatable {
    var x: Int
    var y: Int
    var timestamp: Int
    var button: String
    var clickCount: Int
}

struct CursorTelemetryPayload: Codable, Equatable {
    var width: Int
    var height: Int
    var samples: [CursorTelemetrySample]
    var clicks: [CursorTelemetryClick]

    static func load(from url: URL) throws -> CursorTelemetryPayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CursorTelemetryPayload.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case samples
        case clicks
    }

    init(width: Int, height: Int, samples: [CursorTelemetrySample], clicks: [CursorTelemetryClick]) {
        self.width = width
        self.height = height
        self.samples = samples
        self.clicks = clicks
    }

    func offsetTimestamps(byMilliseconds offset: Int) -> CursorTelemetryPayload {
        CursorTelemetryPayload(
            width: width,
            height: height,
            samples: samples.map {
                CursorTelemetrySample(
                    x: $0.x,
                    y: $0.y,
                    timestamp: $0.timestamp + offset,
                    cursorType: $0.cursorType
                )
            },
            clicks: clicks.map {
                CursorTelemetryClick(
                    x: $0.x,
                    y: $0.y,
                    timestamp: $0.timestamp + offset,
                    button: $0.button,
                    clickCount: $0.clickCount
                )
            }
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        samples = try container.decodeIfPresent([CursorTelemetrySample].self, forKey: .samples) ?? []
        clicks = (try? container.decode([CursorTelemetryClick].self, forKey: .clicks)) ?? []
    }
}

struct CursorTelemetryTrack: Equatable {
    var width: Int
    var height: Int
    var samples: [CursorTelemetrySample]

    init(payload: CursorTelemetryPayload) {
        width = max(payload.width, 1)
        height = max(payload.height, 1)
        samples = payload.samples.sorted { $0.timestamp < $1.timestamp }
    }

    var durationSeconds: Double {
        guard let timestamp = samples.last?.timestamp else { return 0 }
        return max(0, Double(timestamp) / 1_000)
    }

    func point(at seconds: Double, settings: CursorOverlaySettings) -> CGPoint? {
        guard settings.clamped.isVisible else { return nil }
        return point(at: seconds, loops: settings.loops, smoothing: settings.smoothing)
    }

    func point(at seconds: Double, loops: Bool, smoothing: Double) -> CGPoint? {
        guard !samples.isEmpty, seconds.isFinite else { return nil }

        let timestamp = normalizedTimestamp(milliseconds: seconds * 1_000, loops: loops)
        let smoothingRadius = max(0, min(smoothing, 2)) * 180
        guard smoothingRadius > 1 else {
            return interpolatedPoint(atMilliseconds: timestamp, loops: loops)
        }

        let probeCount = 7
        var weightedX = 0.0
        var weightedY = 0.0
        var totalWeight = 0.0

        for index in 0..<probeCount {
            let progress = Double(index) / Double(probeCount - 1)
            let offset = (progress - 0.5) * 2 * smoothingRadius
            guard let point = interpolatedPoint(atMilliseconds: timestamp + offset, loops: loops) else {
                continue
            }
            let weight = max(0.05, 1 - abs(offset) / smoothingRadius)
            weightedX += point.x * weight
            weightedY += point.y * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return interpolatedPoint(atMilliseconds: timestamp, loops: loops)
        }

        return CGPoint(x: weightedX / totalWeight, y: weightedY / totalWeight)
    }

    func normalizedPointAtOrBefore(seconds: Double) -> CGPoint? {
        guard !samples.isEmpty, seconds.isFinite else { return nil }

        let timestamp = min(max(seconds * 1_000, Double(samples[0].timestamp)), Double(samples[samples.count - 1].timestamp))
        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if Double(samples[mid].timestamp) <= timestamp {
                low = mid
            } else {
                high = mid - 1
            }
        }

        let sample = samples[low]
        return CGPoint(
            x: min(max(Double(sample.x) / Double(width), 0), 1),
            y: min(max(Double(sample.y) / Double(height), 0), 1)
        )
    }

    private func normalizedTimestamp(milliseconds: Double, loops: Bool) -> Double {
        guard let first = samples.first?.timestamp,
              let last = samples.last?.timestamp else {
            return 0
        }
        let lower = Double(first)
        let upper = Double(last)
        guard loops, upper > lower else {
            return min(max(milliseconds, lower), upper)
        }

        let span = upper - lower
        let shifted = milliseconds - lower
        let remainder = shifted.truncatingRemainder(dividingBy: span)
        return lower + (remainder >= 0 ? remainder : remainder + span)
    }

    private func interpolatedPoint(atMilliseconds milliseconds: Double, loops: Bool) -> CGPoint? {
        guard let first = samples.first,
              let last = samples.last else {
            return nil
        }

        let timestamp = normalizedTimestamp(milliseconds: milliseconds, loops: loops)
        if timestamp <= Double(first.timestamp) {
            return CGPoint(x: first.x, y: first.y)
        }
        if timestamp >= Double(last.timestamp) {
            return CGPoint(x: last.x, y: last.y)
        }

        var low = 0
        var high = samples.count - 1
        while low < high {
            let mid = (low + high) / 2
            if Double(samples[mid].timestamp) < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let upperIndex = max(1, low)
        let lowerSample = samples[upperIndex - 1]
        let upperSample = samples[upperIndex]
        let span = max(Double(upperSample.timestamp - lowerSample.timestamp), 1)
        let progress = max(0, min((timestamp - Double(lowerSample.timestamp)) / span, 1))
        let x = Double(lowerSample.x) + (Double(upperSample.x) - Double(lowerSample.x)) * progress
        let y = Double(lowerSample.y) + (Double(upperSample.y) - Double(lowerSample.y)) * progress
        return CGPoint(x: x, y: y)
    }
}

@MainActor
final class CursorTelemetryRecorder {
    private var timer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var startedAt: Date?
    private var bounds: CGRect = .zero
    private var samples: [CursorTelemetrySample] = []
    private var clicks: [CursorTelemetryClick] = []

    var isRecording: Bool {
        timer != nil
    }

    static func telemetryURL(for videoURL: URL) -> URL {
        videoURL
            .deletingPathExtension()
            .appendingPathExtension("cursor.json")
    }

    func start(for source: CaptureSource?) {
        stop(videoURL: nil)

        bounds = captureBounds(for: source)
        startedAt = Date()
        samples = []
        clicks = []
        sample()
        installClickMonitors()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    func alignStart(to mediaStartedAt: Date) {
        guard let previousStartedAt = startedAt else { return }
        let offset = Int(previousStartedAt.timeIntervalSince(mediaStartedAt) * 1000)
        samples = samples.map {
            CursorTelemetrySample(
                x: $0.x,
                y: $0.y,
                timestamp: $0.timestamp + offset,
                cursorType: $0.cursorType
            )
        }
        clicks = clicks.map {
            CursorTelemetryClick(
                x: $0.x,
                y: $0.y,
                timestamp: $0.timestamp + offset,
                button: $0.button,
                clickCount: $0.clickCount
            )
        }
        startedAt = mediaStartedAt
    }

    @discardableResult
    func stop(videoURL: URL?) -> URL? {
        timer?.invalidate()
        timer = nil
        removeClickMonitors()

        guard let videoURL else {
            samples = []
            clicks = []
            startedAt = nil
            return nil
        }

        let telemetryURL = Self.telemetryURL(for: videoURL)
        let payload = CursorTelemetryPayload(
            width: max(Int(bounds.width.rounded()), 1),
            height: max(Int(bounds.height.rounded()), 1),
            samples: samples,
            clicks: clicks
        )

        do {
            let data = try JSONEncoder.prettyPrinted.encode(payload)
            try data.write(to: telemetryURL, options: .atomic)
            samples = []
            clicks = []
            startedAt = nil
            return telemetryURL
        } catch {
            samples = []
            clicks = []
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

    private func installClickMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.recordClick(event)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.recordClick(event)
            }
            return event
        }
    }

    private func removeClickMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func recordClick(_ event: NSEvent) {
        guard let startedAt else { return }
        let point = NSEvent.mouseLocation
        guard bounds.contains(point) else { return }

        let relativeX = min(max(point.x - bounds.minX, 0), bounds.width)
        let relativeY = min(max(bounds.maxY - point.y, 0), bounds.height)
        let timestamp = Int(Date().timeIntervalSince(startedAt) * 1000)
        clicks.append(CursorTelemetryClick(
            x: Int(relativeX.rounded()),
            y: Int(relativeY.rounded()),
            timestamp: timestamp,
            button: buttonName(for: event.type),
            clickCount: max(event.clickCount, 1)
        ))
    }

    private func buttonName(for eventType: NSEvent.EventType) -> String {
        switch eventType {
        case .rightMouseDown:
            "right"
        case .otherMouseDown:
            "other"
        default:
            "left"
        }
    }

    private func captureBounds(for source: CaptureSource?) -> CGRect {
        if let source {
            return RecordingCountdownTargetResolver.currentFrame(for: source)
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
