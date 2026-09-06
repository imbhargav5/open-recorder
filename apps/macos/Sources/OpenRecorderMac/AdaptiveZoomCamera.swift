import Foundation
import CoreGraphics

extension TimelineEditSnapshot {
    var hasAdaptiveCamera: Bool {
        zoomRegions.contains { $0.cameraPath?.version == 1 }
    }
}

/// Stored in recording coordinates, independent of preview size and output format.
struct AutoZoomCameraKeyframe: Codable, Equatable, Hashable {
    var time: Double
    var centerX: Double
    var centerY: Double
    var depth: Double
}

struct AutoZoomCameraPath: Codable, Equatable, Hashable {
    var version = 1
    var keyframes: [AutoZoomCameraKeyframe]
    var contextWidth = 0.2
    var contextHeight = 0.2
    var automaticFraming = true

    private enum CodingKeys: String, CodingKey { case version, keyframes, contextWidth, contextHeight, automaticFraming }

    init(keyframes: [AutoZoomCameraKeyframe], contextWidth: Double = 0.2, contextHeight: Double = 0.2) {
        self.keyframes = keyframes
        self.contextWidth = contextWidth
        self.contextHeight = contextHeight
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        automaticFraming = try values.decodeIfPresent(Bool.self, forKey: .automaticFraming) ?? true
        version = try values.decode(Int.self, forKey: .version)
        keyframes = try values.decode([AutoZoomCameraKeyframe].self, forKey: .keyframes)
        contextWidth = try values.decodeIfPresent(Double.self, forKey: .contextWidth) ?? 0.2
        contextHeight = try values.decodeIfPresent(Double.self, forKey: .contextHeight) ?? 0.2
        guard keyframes.count >= 2, contextWidth.isFinite, contextHeight.isFinite,
              contextWidth > 0, contextHeight > 0,
              keyframes.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.centerX.isFinite && $0.centerY.isFinite
                  && $0.depth.isFinite && $0.depth >= 1 && $0.depth <= 5 }),
              zip(keyframes, keyframes.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            throw DecodingError.dataCorruptedError(forKey: .keyframes, in: values, debugDescription: "Invalid automatic camera path")
        }
    }

    func effect(at time: Double) -> TimelineZoomEffect? {
        guard version == 1, time.isFinite, let first = keyframes.first, let last = keyframes.last else { return nil }
        let frame: AutoZoomCameraKeyframe
        if time <= first.time { frame = first }
        else if time >= last.time { frame = last }
        else {
            var low = 0
            var high = keyframes.count - 1
            while low + 1 < high {
                let mid = (low + high) / 2
                if keyframes[mid].time <= time { low = mid } else { high = mid }
            }
            let a = keyframes[low], b = keyframes[high]
            let t = Self.ease((time - a.time) / max(0.0001, b.time - a.time))
            frame = AutoZoomCameraKeyframe(time: time,
                centerX: a.centerX + (b.centerX - a.centerX) * t,
                centerY: a.centerY + (b.centerY - a.centerY) * t,
                depth: a.depth + (b.depth - a.depth) * t)
        }
        guard frame.centerX.isFinite, frame.centerY.isFinite, frame.depth.isFinite else { return nil }
        return TimelineZoomEffect(depth: max(1, frame.depth), focusX: frame.centerX,
                                  focusY: frame.centerY, usesViewportCenter: true,
                                  contextSize: automaticFraming ? CGSize(width: contextWidth, height: contextHeight) : nil)
    }

    static func ease(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    mutating func retime(from old: TimelineSpan, to new: TimelineSpan) {
        guard old.duration > 0 else { return }
        for index in keyframes.indices {
            keyframes[index].time = new.start + (keyframes[index].time - old.start) / old.duration * new.duration
        }
    }
}

/// A single source -> cropped/placed canvas mapping, shared by preview and export.
struct AutoZoomGeometry {
    var sourceSize: CGSize
    var cropRect: CGRect
    /// The actual aspect-fitted video rectangle, in a top-left-origin canvas.
    var contentRect: CGRect
    var canvasSize: CGSize

    func canvasEffect(_ effect: TimelineZoomEffect, cameraSettings: FacecamSettings? = nil) -> TimelineZoomEffect {
        guard effect.usesViewportCenter, canvasSize.width > 0, canvasSize.height > 0,
              cropRect.width > 0, cropRect.height > 0 else { return effect }
        let x = contentRect.minX + (effect.focusX * sourceSize.width - cropRect.minX) / cropRect.width * contentRect.width
        let y = contentRect.minY + (effect.focusY * sourceSize.height - cropRect.minY) / cropRect.height * contentRect.height
        var depth = effect.depth
        if let context = effect.contextSize {
            let normalizedWidth = context.width * sourceSize.width / cropRect.width * contentRect.width / canvasSize.width
            let normalizedHeight = context.height * sourceSize.height / cropRect.height * contentRect.height / canvasSize.height
            let fitDepth = max(1, min(1 / max(0.001, normalizedWidth), 1 / max(0.001, normalizedHeight)))
            depth = min(depth, fitDepth)
            if let cameraSettings, cameraSettings.enabled {
                let camera = FacecamOverlayLayout.frame(in: canvasSize, settings: cameraSettings)
                let required = CGRect(x: x - normalizedWidth * canvasSize.width / 2,
                    y: y - normalizedHeight * canvasSize.height / 2,
                    width: normalizedWidth * canvasSize.width, height: normalizedHeight * canvasSize.height)
                let overlap = camera.intersection(required)
                if !overlap.isNull {
                    // Fade the conservative limit in at the boundary, avoiding a sudden
                    // magnification change as a planned pan approaches the camera overlay.
                    let fraction = overlap.width * overlap.height / max(1, required.width * required.height)
                    depth -= max(0, depth - 1.35) * AutoZoomCameraPath.ease(min(1, fraction * 4))
                }
            }
        }
        return TimelineZoomEffect(depth: depth, focusX: x / canvasSize.width,
                                  focusY: y / canvasSize.height, usesViewportCenter: true)
    }

    static func fitted(sourceSize: CGSize, cropRect: CGRect, container: CGRect, canvasSize: CGSize) -> Self {
        let scale = min(container.width / max(1, cropRect.width), container.height / max(1, cropRect.height))
        let size = CGSize(width: cropRect.width * scale, height: cropRect.height * scale)
        return Self(sourceSize: sourceSize, cropRect: cropRect,
                    contentRect: CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                                        width: size.width, height: size.height), canvasSize: canvasSize)
    }
}

extension TimelineZoomRegion {
    mutating func setEditedDepth(_ value: Double) {
        guard value.isFinite else { return }
        let newDepth = min(max(value, 1), 5)
        if var path = cameraPath {
            path.automaticFraming = false
            let ratio = (newDepth - 1) / max(0.0001, depth - 1)
            for index in path.keyframes.indices {
                if depth <= 1.0001 {
                    path.keyframes[index].depth = index == 0 || index == path.keyframes.count - 1 ? 1 : newDepth
                } else {
                    path.keyframes[index].depth = 1 + (path.keyframes[index].depth - 1) * ratio
                }
            }
            cameraPath = path
        }
        depth = newDepth
        isUserEdited = true
    }
}

extension TimelineZoomCanvasTransform {
    /// Sample moving intervals at a fixed cadence, independent of total recording length.
    /// Static holds and unzoomed gaps need only endpoints.
    static func animationSampleTimes(edits: TimelineEditSnapshot, editPlan: TimelineExportEditPlan) -> [Double] {
        var times: Set<Double> = [0, editPlan.outputDuration]
        // A cut can skip an entire pan and join two static holds. Preserve both
        // sides of each edit boundary so Core Animation does not interpolate
        // across the following hold. The tiny interval is below a video frame.
        for segment in editPlan.segments {
            for boundary in [segment.outputStart, segment.outputEnd] {
                times.insert(boundary)
                if boundary > 0 { times.insert(max(0, boundary - 0.000001)) }
                if boundary < editPlan.outputDuration {
                    times.insert(min(editPlan.outputDuration, boundary + 0.000001))
                }
            }
        }
        for zoom in edits.zoomRegions {
            let intervals: [TimelineSpan]
            if let path = zoom.cameraPath, path.version == 1 {
                intervals = zip(path.keyframes, path.keyframes.dropFirst()).compactMap { a, b in
                    guard a.centerX != b.centerX || a.centerY != b.centerY || a.depth != b.depth else { return nil }
                    return TimelineSpan(start: max(zoom.span.start, a.time), end: min(zoom.span.end, b.time))
                }
            } else { intervals = [zoom.span] }
            for span in editPlan.outputSpans(forSourceSpan: zoom.span) {
                times.insert(span.start)
                times.insert(span.end)
            }
            for interval in intervals where interval.duration > 0 {
                for span in editPlan.outputSpans(forSourceSpan: interval) {
                    let steps = max(1, Int(ceil(span.duration * 60)))
                    for index in 0...steps { times.insert(span.start + span.duration * Double(index) / Double(steps)) }
                }
            }
        }
        return times.sorted()
    }
}
