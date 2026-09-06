import Foundation
import CoreGraphics
import OSLog

/// Offline camera planning. No telemetry analysis is performed on the rendering path.
enum AutoZoomGenerator {
    private static let logger = Logger(subsystem: "dev.openrecorder.app", category: "AutoZoom")
    static let defaultDepth = 2.0
    static let leadInSeconds = 0.6
    static let holdAfterClickSeconds = 1.4
    static let mergeThresholdSeconds = 1.5
    static let minimumGapSeconds = 0.2
    static let minimumDurationSeconds = 2.0
    static let exitSeconds = 0.7
    static let panLookaheadSeconds = 0.3
    static let sustainedCrossingSeconds = 0.2
    static let maximumSampleGapMilliseconds = 250

    static func maximumDepth(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 1), 3) : defaultDepth
    }

    private struct Target {
        var time: Double
        var end: Double
        var point: CGPoint
        var bounds: CGRect
        var confidence: Double
        var click: Int?
    }

    static func generate(from telemetryURL: URL, duration: Double,
                         preset: TimelineZoomAnimationPreset = .balanced,
                         cameraSettings: FacecamSettings? = nil,
                         maximumZoom: Double = defaultDepth,
                         cameraClips: [TimelineCameraClip] = []) -> [TimelineZoomRegion] {
        let start = ProcessInfo.processInfo.systemUptime
        guard let telemetry = try? CursorTelemetryPayload.load(from: telemetryURL) else { return [] }
        let loaded = ProcessInfo.processInfo.systemUptime
        let result = generate(from: telemetry, duration: duration, preset: preset, cameraSettings: cameraSettings,
                              maximumZoom: maximumZoom, cameraClips: cameraClips)
        let analyzed = ProcessInfo.processInfo.systemUptime
        logger.debug("Telemetry load: \(loaded - start)s; camera planning: \(analyzed - loaded)s; regions: \(result.count)")
        return result
    }

    static func generate(from telemetry: CursorTelemetryPayload, duration: Double,
                         preset: TimelineZoomAnimationPreset = .balanced,
                         cameraSettings: FacecamSettings? = nil,
                         maximumZoom: Double = defaultDepth,
                         cameraClips: [TimelineCameraClip] = []) -> [TimelineZoomRegion] {
        guard duration.isFinite, duration > 0, telemetry.width > 0, telemetry.height > 0,
              maximumDepth(maximumZoom) >= 1.15 else { return [] }
        let width = Double(telemetry.width), height = Double(telemetry.height)
        func valid(_ x: Int, _ y: Int, _ t: Int) -> Bool {
            x >= 0 && y >= 0 && x <= telemetry.width && y <= telemetry.height && t >= 0 && Double(t) / 1000 <= duration
        }
        func point(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: Double(x) / width, y: Double(y) / height) }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
            hypot((a.x - b.x) * width, (a.y - b.y) * height) / hypot(width, height)
        }
        let samples = telemetry.samples.filter { valid($0.x, $0.y, $0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
        let clicks = telemetry.clicks.filter { valid($0.x, $0.y, $0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
        let boundsIndex = SampleBoundsIndex(samples: samples, width: width, height: height)
        // Indexed windows also let dense bursts share the same boundary evidence.
        var gapCounts = [0]
        for i in samples.indices {
            gapCounts.append(gapCounts.last! + (i > 0 && samples[i].timestamp - samples[i - 1].timestamp > maximumSampleGapMilliseconds ? 1 : 0))
        }
        func lowerBound(_ milliseconds: Double) -> Int {
            var low = 0, high = samples.count
            while low < high {
                let mid = (low + high) / 2
                if Double(samples[mid].timestamp) < milliseconds { low = mid + 1 } else { high = mid }
            }
            return low
        }
        func sustainedCrossing(_ target: Target, center: CGPoint, half: Double) -> Bool {
            let start = lowerBound(target.time * 1000)
            let end = lowerBound((target.time + panLookaheadSeconds) * 1000 + 1)
            // Click-only recordings have no continuity evidence. An explicit action
            // remains a usable fallback; missing samples never count as a dwell.
            if start == end { return target.click != nil }
            guard end - start >= 2,
                  Double(samples[end - 1].timestamp - samples[start].timestamp) >= sustainedCrossingSeconds * 1000,
                  gapCounts[end] == gapCounts[start + 1],
                  let bounds = boundsIndex.bounds(in: start..<end) else { return false }
            return bounds.minX > center.x + half || bounds.maxX < center.x - half
                || bounds.minY > center.y + half || bounds.maxY < center.y - half
        }
        var targets: [Target] = []
        var sampleIndex = 0
        var sampleEnd = 0
        for click in clicks {
            let t = Double(click.timestamp) / 1000
            let p = point(click.x, click.y)
            var box = CGRect(origin: p, size: .zero)
            while sampleIndex < samples.count && Double(samples[sampleIndex].timestamp) / 1000 < t - 0.15 { sampleIndex += 1 }
            sampleEnd = max(sampleEnd, sampleIndex)
            while sampleEnd < samples.count && Double(samples[sampleEnd].timestamp) / 1000 <= t + 0.45 { sampleEnd += 1 }
            if let context = boundsIndex.bounds(in: sampleIndex..<sampleEnd) {
                box = include(CGPoint(x: context.minX, y: context.minY), in: box)
                box = include(CGPoint(x: context.maxX, y: context.maxY), in: box)
            }
            targets.append(Target(time: t, end: t, point: p, bounds: box,
                                  confidence: click.clickCount > 1 ? 0.9 : 0.75, click: click.timestamp))
        }
        // Cursor arrival followed by dwell. Consume each dwell once, including its idle tail.
        var index = 1
        var clickIndex = 0
        var arrivalIndex = 0
        while index < samples.count {
            let sample = samples[index]
            let p = point(sample.x, sample.y)
            while arrivalIndex + 1 < index && samples[arrivalIndex + 1].timestamp < sample.timestamp - 300 { arrivalIndex += 1 }
            let prior = point(samples[arrivalIndex].x, samples[arrivalIndex].y)
            guard distance(p, prior) >= 0.025,
                  gapCounts[index + 1] == gapCounts[arrivalIndex + 1] else { index += 1; continue }
            var end = index
            var box = CGRect(origin: p, size: .zero)
            while end + 1 < samples.count,
                  distance(point(samples[end + 1].x, samples[end + 1].y), p) <= 0.035,
                  samples[end + 1].timestamp - samples[end].timestamp <= 250 {
                end += 1
                box = include(point(samples[end].x, samples[end].y), in: box)
            }
            let t = Double(sample.timestamp) / 1000
            while clickIndex < clicks.count && Double(clicks[clickIndex].timestamp) / 1000 < t - 0.5 { clickIndex += 1 }
            let nearbyClick = clickIndex < clicks.count && Double(clicks[clickIndex].timestamp) / 1000 <= t + 1.4
            if samples[end].timestamp - sample.timestamp >= 900 && !nearbyClick {
                targets.append(Target(time: t, end: t + 0.9, point: p, bounds: box, confidence: 0.6, click: nil))
            }
            index = max(index + 1, end + 1)
        }
        targets.sort { $0.time == $1.time ? $0.confidence > $1.confidence : $0.time < $1.time }
        var groups: [[Target]] = []
        for target in targets {
            if let previous = groups.last?.last,
               target.time - previous.end <= mergeThresholdSeconds,
               distance(previous.point, target.point) <= 0.2 {
                groups[groups.count - 1].append(target)
            } else { groups.append([target]) }
        }
        let entrance = preset == .balanced ? leadInSeconds : preset.configuration.rampInSeconds
        let exit = preset == .balanced ? exitSeconds : preset.configuration.rampOutSeconds
        var result: [TimelineZoomRegion] = []
        var confidences: [Double] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let span = TimelineSpan(start: max(0, first.time - entrance),
                                    end: min(duration, max(last.end + holdAfterClickSeconds + exit,
                                        max(0, first.time - entrance) + minimumDurationSeconds)))
            guard span.duration >= minimumDurationSeconds || (first.click != nil && span.duration >= 0.7) else { continue }
            var depth = maximumDepth(maximumZoom)
            for target in group {
                let padded = target.bounds.insetBy(dx: -0.1, dy: -0.1)
                depth = min(depth, 1 / max(padded.width, padded.height))
                let camera = cameraClips.isEmpty ? cameraSettings
                    : cameraClips.last(where: { $0.span.contains(target.time) })?.settings
                // These bounds are only an initial conservative hint. Render-time geometry handles placement.
                if let camera, camera.enabled {
                    let frame = FacecamOverlayLayout.frame(in: CGSize(width: width, height: height), settings: camera)
                    let normalized = CGRect(x: frame.minX / width, y: frame.minY / height,
                        width: frame.width / width, height: frame.height / height)
                    if normalized.intersects(padded) { depth = min(depth, 1.35) }
                }
            }
            guard depth >= 1.15 else { continue }
            let entranceEnd = min(span.end, max(first.time, span.start + min(entrance, span.duration * 0.3)))
            let holdEnd = max(entranceEnd, span.end - min(exit, span.duration * 0.3))
            func center(_ target: Target) -> CGPoint {
                CGPoint(x: target.bounds.midX, y: target.bounds.midY)
            }
            // A bounded evidence score, not a probability. Additional actions support
            // the whole interaction without allowing arbitrarily large bursts to dominate.
            let strongest = group.map(\.confidence).max() ?? 0
            let support = group.reduce(0.0) { $0 + $1.confidence } - strongest
            let score = strongest + 0.25 * (1 - exp(-support))
            var current = center(first)
            var frames = [AutoZoomCameraKeyframe(time: span.start, centerX: 0.5, centerY: 0.5, depth: 1),
                          AutoZoomCameraKeyframe(time: entranceEnd, centerX: current.x, centerY: current.y, depth: depth)]
            for target in group.dropFirst() {
                let safeHalf = 0.3 / depth
                let viewport = CGRect(x: current.x - 0.5 / depth, y: current.y - 0.5 / depth, width: 1 / depth, height: 1 / depth)
                let required = target.bounds.insetBy(dx: -0.1, dy: -0.1)
                guard abs(target.point.x - current.x) > safeHalf || abs(target.point.y - current.y) > safeHalf
                        || !viewport.contains(required) else { continue }
                guard sustainedCrossing(target, center: current, half: safeHalf) else { continue }
                let next = center(target)
                let panDuration = max(0.6, distance(current, next) * 3)
                let start = max(frames.last!.time, target.time - panLookaheadSeconds)
                let end = min(holdEnd, start + panDuration)
                guard end >= start + 0.6 else { continue }
                if start > frames.last!.time { frames.append(.init(time: start, centerX: current.x, centerY: current.y, depth: depth)) }
                frames.append(.init(time: end, centerX: next.x, centerY: next.y, depth: depth))
                current = next
            }
            if holdEnd > frames.last!.time { frames.append(.init(time: holdEnd, centerX: current.x, centerY: current.y, depth: depth)) }
            frames.append(.init(time: span.end, centerX: 0.5, centerY: 0.5, depth: 1))
            // A suppressed or unfinished pan must not hide the action it was meant
            // to show. Fit every target around the camera's actual position at its
            // timestamp, then widen the entire interaction to retain a stable depth.
            let plannedPath = AutoZoomCameraPath(keyframes: frames)
            for target in group {
                guard let effect = plannedPath.effect(at: target.time) else { continue }
                let required = target.bounds.insetBy(dx: -0.1, dy: -0.1)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                let radius = max(abs(required.minX - effect.focusX), abs(required.maxX - effect.focusX),
                                 abs(required.minY - effect.focusY), abs(required.maxY - effect.focusY))
                depth = min(depth, 0.5 / max(0.001, radius))
            }
            guard depth >= 1.15 else { continue }
            for index in frames.indices where frames[index].depth > 1 { frames[index].depth = depth }
            let contextWidth = group.map { $0.bounds.width + 0.2 }.max() ?? 0.2
            let contextHeight = group.map { $0.bounds.height + 0.2 }.max() ?? 0.2
            // Resolve only after validating the new candidate, so an unusable candidate
            // cannot erase a valid earlier interaction.
            if let previous = result.last, span.start < previous.span.end + minimumGapSeconds {
                guard score > (confidences.last ?? 0) else { continue }
                result.removeLast()
                confidences.removeLast()
            }
            confidences.append(score)
            result.append(TimelineZoomRegion(span: span, depth: depth, focusX: center(first).x, focusY: center(first).y,
                mode: .auto, animationPreset: preset, sourceClickTimestamp: first.click,
                cameraPath: AutoZoomCameraPath(keyframes: frames, contextWidth: contextWidth, contextHeight: contextHeight)))
        }
        return result
    }

    /// Range extrema make dense click bursts O(log samples) per query instead of
    /// repeatedly traversing the same local telemetry window.
    private struct SampleBoundsIndex {
        private var leaves: Int
        private var tree: [CGRect?]

        init(samples: [CursorTelemetrySample], width: Double, height: Double) {
            var count = 1
            while count < samples.count { count *= 2 }
            leaves = count
            tree = Array(repeating: nil, count: count * 2)
            for (index, sample) in samples.enumerated() {
                tree[count + index] = CGRect(x: Double(sample.x) / width, y: Double(sample.y) / height, width: 0, height: 0)
            }
            if count > 1 {
                for index in stride(from: count - 1, through: 1, by: -1) {
                    tree[index] = Self.merged(tree[index * 2], tree[index * 2 + 1])
                }
            }
        }

        func bounds(in range: Range<Int>) -> CGRect? {
            var left = range.lowerBound + leaves, right = range.upperBound + leaves
            var result: CGRect?
            while left < right {
                if left % 2 == 1 { result = Self.merged(result, tree[left]); left += 1 }
                if right % 2 == 1 { right -= 1; result = Self.merged(result, tree[right]) }
                left /= 2
                right /= 2
            }
            return result
        }

        private static func merged(_ a: CGRect?, _ b: CGRect?) -> CGRect? {
            guard let a else { return b }
            guard let b else { return a }
            return CGRect(x: min(a.minX, b.minX), y: min(a.minY, b.minY),
                width: max(a.maxX, b.maxX) - min(a.minX, b.minX),
                height: max(a.maxY, b.maxY) - min(a.minY, b.minY))
        }
    }

    private static func include(_ p: CGPoint, in rect: CGRect) -> CGRect {
        let x = min(rect.minX, p.x), y = min(rect.minY, p.y)
        return CGRect(x: x, y: y, width: max(rect.maxX, p.x) - x, height: max(rect.maxY, p.y) - y)
    }
}

struct AutoZoomGenerationRequest: Sendable {
    var telemetryURL: URL
    var duration: Double
    var preset: TimelineZoomAnimationPreset
    var cameraSettings: FacecamSettings?
    var maximumZoom: Double
    var cameraClips: [TimelineCameraClip]
}

enum AutoZoomGenerationService {
    static func generate(_ request: AutoZoomGenerationRequest) async -> [TimelineZoomRegion] {
        await Task.detached(priority: .userInitiated) {
            AutoZoomGenerator.generate(from: request.telemetryURL, duration: request.duration,
                preset: request.preset, cameraSettings: request.cameraSettings,
                maximumZoom: request.maximumZoom, cameraClips: request.cameraClips)
        }.value
    }
}
