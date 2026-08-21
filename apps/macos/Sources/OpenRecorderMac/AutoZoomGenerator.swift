import Foundation

enum AutoZoomGenerator {
    static let defaultDepth = TimelineZoomAnimationPreset.balanced.configuration.depth
    static let leadInSeconds = TimelineZoomAnimationPreset.balanced.configuration.leadInSeconds
    static let holdAfterClickSeconds = TimelineZoomAnimationPreset.balanced.configuration.holdAfterClickSeconds
    static let mergeThresholdSeconds = TimelineZoomAnimationPreset.balanced.configuration.mergeThresholdSeconds
    static let minimumGapSeconds = TimelineZoomAnimationPreset.balanced.configuration.minimumGapSeconds
    static let minimumDurationSeconds = TimelineZoomAnimationPreset.balanced.configuration.minimumDurationSeconds
    static let focusClampRange = TimelineZoomAnimationPreset.balanced.configuration.focusClampRange

    static func generate(
        from telemetry: CursorTelemetryPayload,
        duration: Double,
        preset: TimelineZoomAnimationPreset = .balanced,
        cameraSettings: FacecamSettings? = nil
    ) -> [TimelineZoomRegion] {
        guard duration.isFinite, duration > 0 else { return [] }
        guard telemetry.width > 0, telemetry.height > 0 else { return [] }

        let width = Double(max(telemetry.width, 1))
        let height = Double(max(telemetry.height, 1))

        let isInsideCamera: (Int, Int) -> Bool = { x, y in
            guard let camera = cameraSettings, camera.enabled else { return false }
            let normX = Double(x) / width
            let normY = Double(y) / height
            let cameraRect = FacecamOverlayLayout.normalizedRect(for: camera)
            let expandedRect = cameraRect.insetBy(dx: -0.06, dy: -0.06)
            return expandedRect.contains(CGPoint(x: normX, y: normY))
        }

        let config = preset.configuration
        let sortedClicks = telemetry.clicks
            .filter { $0.timestamp >= 0 && !isInsideCamera($0.x, $0.y) }
            .sorted { $0.timestamp < $1.timestamp }
        let sortedSamples = telemetry.samples
            .filter { $0.timestamp >= 0 && !isInsideCamera($0.x, $0.y) }
            .sorted { $0.timestamp < $1.timestamp }

        let clickCandidates = clusteredClicks(sortedClicks, mergeThresholdSeconds: config.mergeThresholdSeconds)
            .map { candidate(for: $0, samples: sortedSamples, telemetry: telemetry, config: config) }
        let cursorCandidates = cursorActivityCandidates(
            samples: sortedSamples,
            clicks: sortedClicks,
            telemetry: telemetry,
            config: config,
            preset: preset
        )
        let candidates = (clickCandidates + cursorCandidates)
            .filter { $0.confidence >= config.minimumConfidence }
            .sorted { lhs, rhs in
                if lhs.startTimestamp == rhs.startTimestamp {
                    return lhs.endTimestamp < rhs.endTimestamp
                }
                return lhs.startTimestamp < rhs.startTimestamp
            }

        var generated: [TimelineZoomRegion] = []

        for candidate in candidates {
            let firstTime = Double(candidate.startTimestamp) / 1_000
            let lastTime = Double(candidate.endTimestamp) / 1_000
            var start = max(0, firstTime - config.leadInSeconds)
            let end = min(duration, lastTime + config.holdAfterClickSeconds)

            if let previous = generated.last {
                start = max(start, previous.span.end + config.minimumGapSeconds)
            }
            guard end - start >= config.minimumDurationSeconds else { continue }

            generated.append(TimelineZoomRegion(
                span: TimelineSpan(start: start, end: end).normalized(duration: duration, minimumDuration: config.minimumDurationSeconds),
                depth: config.depth,
                focusX: clampedFocus(candidate.focusX, range: config.focusClampRange),
                focusY: clampedFocus(candidate.focusY, range: config.focusClampRange),
                mode: .auto,
                animationPreset: preset,
                sourceClickTimestamp: candidate.sourceClickTimestamp
            ))
        }

        return generated
    }

    static func generate(
        from telemetryURL: URL,
        duration: Double,
        preset: TimelineZoomAnimationPreset = .balanced,
        cameraSettings: FacecamSettings? = nil
    ) -> [TimelineZoomRegion] {
        guard let telemetry = try? CursorTelemetryPayload.load(from: telemetryURL) else { return [] }
        return generate(from: telemetry, duration: duration, preset: preset, cameraSettings: cameraSettings)
    }

    private static func clusteredClicks(_ clicks: [CursorTelemetryClick], mergeThresholdSeconds: Double) -> [[CursorTelemetryClick]] {
        clicks.reduce(into: [[CursorTelemetryClick]]()) { clusters, click in
            guard var current = clusters.popLast(), let previous = current.last else {
                clusters.append([click])
                return
            }

            let gap = Double(click.timestamp - previous.timestamp) / 1_000
            if gap <= mergeThresholdSeconds {
                current.append(click)
                clusters.append(current)
            } else {
                clusters.append(current)
                clusters.append([click])
            }
        }
    }

    private static func candidate(
        for cluster: [CursorTelemetryClick],
        samples: [CursorTelemetrySample],
        telemetry: CursorTelemetryPayload,
        config: TimelineZoomAnimationConfiguration
    ) -> ZoomCandidate {
        let width = Double(max(telemetry.width, 1))
        let height = Double(max(telemetry.height, 1))
        var best = ZoomCandidate(
            startTimestamp: cluster.first?.timestamp ?? 0,
            focusX: Double(cluster.last?.x ?? telemetry.width / 2) / width,
            focusY: Double(cluster.last?.y ?? telemetry.height / 2) / height,
            endTimestamp: cluster.last?.timestamp ?? 0,
            confidence: 0,
            sourceClickTimestamp: cluster.last?.timestamp
        )

        for click in cluster {
            let classified = classify(click: click, samples: samples, width: width, height: height)
            if classified.confidence >= best.confidence {
                best = ZoomCandidate(
                    startTimestamp: cluster.first?.timestamp ?? click.timestamp,
                    focusX: Double(click.x) / width,
                    focusY: Double(click.y) / height,
                    endTimestamp: max(click.timestamp, classified.endTimestamp),
                    confidence: classified.confidence,
                    sourceClickTimestamp: cluster.last?.timestamp
                )
            } else {
                best.endTimestamp = max(best.endTimestamp, classified.endTimestamp)
            }
        }

        let burstBonus = min(0.18, Double(max(cluster.count - 1, 0)) * 0.06)
        best.confidence = min(1, best.confidence + burstBonus)
        best.focusX = clampedFocus(best.focusX, range: config.focusClampRange)
        best.focusY = clampedFocus(best.focusY, range: config.focusClampRange)
        return best
    }

    private static func cursorActivityCandidates(
        samples: [CursorTelemetrySample],
        clicks: [CursorTelemetryClick],
        telemetry: CursorTelemetryPayload,
        config: TimelineZoomAnimationConfiguration,
        preset: TimelineZoomAnimationPreset
    ) -> [ZoomCandidate] {
        guard preset == .guided, samples.count >= 8 else { return [] }

        let width = Double(max(telemetry.width, 1))
        let height = Double(max(telemetry.height, 1))
        let minimumWindowMilliseconds = 900
        let maximumWindowMilliseconds = 2_200
        let clickExclusionMilliseconds = 500
        var candidates: [ZoomCandidate] = []
        var startIndex = 0

        while startIndex < samples.count {
            let startTimestamp = samples[startIndex].timestamp
            var endIndex = startIndex
            while endIndex + 1 < samples.count,
                  samples[endIndex + 1].timestamp - startTimestamp <= maximumWindowMilliseconds {
                endIndex += 1
            }

            let endTimestamp = samples[endIndex].timestamp
            if endTimestamp - startTimestamp >= minimumWindowMilliseconds,
               !clicks.contains(where: { click in
                   click.timestamp >= startTimestamp - clickExclusionMilliseconds
                       && click.timestamp <= endTimestamp + clickExclusionMilliseconds
               }),
               let candidate = cursorActivityCandidate(
                   samples: Array(samples[startIndex...endIndex]),
                   width: width,
                   height: height,
                   config: config
               ) {
                candidates.append(candidate)
                startIndex = endIndex + 1
            } else {
                startIndex += 4
            }
        }

        return candidates
    }

    private static func cursorActivityCandidate(
        samples: [CursorTelemetrySample],
        width: Double,
        height: Double,
        config: TimelineZoomAnimationConfiguration
    ) -> ZoomCandidate? {
        guard let first = samples.first, let last = samples.last, samples.count >= 8 else { return nil }

        var minX = Double(first.x) / width
        var maxX = minX
        var minY = Double(first.y) / height
        var maxY = minY
        var pathLength = 0.0
        var previous = first

        for sample in samples {
            let x = Double(sample.x) / width
            let y = Double(sample.y) / height
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)

            let dx = (Double(sample.x) - Double(previous.x)) / width
            let dy = (Double(sample.y) - Double(previous.y)) / height
            pathLength += hypot(dx, dy)
            previous = sample
        }

        let durationMilliseconds = last.timestamp - first.timestamp
        let boxWidth = maxX - minX
        let boxHeight = maxY - minY
        let dropdownLike = boxHeight >= 0.055 && boxHeight <= 0.32 && boxWidth <= 0.12
        let focusedHover = max(boxWidth, boxHeight) <= 0.13
        guard durationMilliseconds >= 900,
              pathLength >= 0.018,
              pathLength <= 0.75,
              dropdownLike || focusedHover else {
            return nil
        }

        let durationBonus = min(0.12, Double(durationMilliseconds) / 10_000)
        let confidence = min(1, (dropdownLike ? 0.56 : 0.42) + durationBonus)
        return ZoomCandidate(
            startTimestamp: first.timestamp,
            focusX: clampedFocus((minX + maxX) / 2, range: config.focusClampRange),
            focusY: clampedFocus((minY + maxY) / 2, range: config.focusClampRange),
            endTimestamp: last.timestamp,
            confidence: confidence,
            sourceClickTimestamp: nil
        )
    }

    private static func classify(
        click: CursorTelemetryClick,
        samples: [CursorTelemetrySample],
        width: Double,
        height: Double
    ) -> ClassifiedInteraction {
        let postSamples = samples.filter { sample in
            sample.timestamp >= click.timestamp + 80 && sample.timestamp <= click.timestamp + 2_000
        }

        guard !postSamples.isEmpty else {
            return ClassifiedInteraction(
                endTimestamp: click.timestamp,
                confidence: click.clickCount > 1 ? 0.82 : 0.55
            )
        }

        let clickX = Double(click.x)
        let clickY = Double(click.y)
        var maxDistance = 0.0
        var totalAbsDX = 0.0
        var totalAbsDY = 0.0
        for sample in postSamples {
            let dx = abs(Double(sample.x) - clickX) / width
            let dy = abs(Double(sample.y) - clickY) / height
            maxDistance = max(maxDistance, hypot(dx, dy))
            totalAbsDX += dx
            totalAbsDY += dy
        }

        let last = postSamples.last
        let netDY = (Double(last?.y ?? click.y) - clickY) / height
        let endTimestamp = last?.timestamp ?? click.timestamp

        if click.clickCount > 1 {
            return ClassifiedInteraction(endTimestamp: endTimestamp, confidence: 0.88)
        }
        if totalAbsDX > 0.06 && totalAbsDX > totalAbsDY * 1.8 {
            return ClassifiedInteraction(endTimestamp: endTimestamp, confidence: 0.86)
        }
        if netDY > 0.035 && totalAbsDY > totalAbsDX * 1.35 {
            return ClassifiedInteraction(endTimestamp: endTimestamp, confidence: 0.78)
        }
        if maxDistance < 0.018 {
            return ClassifiedInteraction(endTimestamp: min(endTimestamp, click.timestamp + 900), confidence: 0.70)
        }
        if maxDistance > 0.16 && postSamples.count >= 3 {
            return ClassifiedInteraction(endTimestamp: endTimestamp, confidence: 0.38)
        }

        return ClassifiedInteraction(endTimestamp: min(endTimestamp, click.timestamp + 700), confidence: 0.64)
    }

    private static func clampedFocus(_ value: Double, range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct ZoomCandidate {
    var startTimestamp: Int
    var focusX: Double
    var focusY: Double
    var endTimestamp: Int
    var confidence: Double
    var sourceClickTimestamp: Int?
}

private struct ClassifiedInteraction {
    var endTimestamp: Int
    var confidence: Double
}
