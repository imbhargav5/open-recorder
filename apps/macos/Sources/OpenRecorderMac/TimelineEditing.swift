import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import Observation
import QuartzCore
import SwiftUI

typealias TimelineRegionID = UUID

enum TimelineZoomMode: String, Codable, Hashable {
    case auto
    case manual
}

enum TimelineZoomDepth {
    static let defaultDepth = 1.75
    static let values: [Double] = [1.0, 1.25, 1.5, 1.75, 2.0]

    static func normalized(_ depth: Double) -> Double {
        guard depth.isFinite else { return defaultDepth }
        return values.min { abs($0 - depth) < abs($1 - depth) } ?? defaultDepth
    }

    static func label(_ depth: Double) -> String {
        guard depth.isFinite else { return label(defaultDepth) }
        let roundedWhole = depth.rounded()
        if abs(roundedWhole - depth) < 0.001 {
            return "\(Int(roundedWhole))x"
        }

        let roundedTenth = (depth * 10).rounded() / 10
        if abs(roundedTenth - depth) < 0.001 {
            return String(format: "%.1fx", depth)
        }

        return String(format: "%.2fx", depth)
    }
}

enum TimelineRegionKind: String, CaseIterable, Identifiable {
    case zoom
    case trim
    case annotation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zoom: "Zoom"
        case .trim: "Trim"
        case .annotation: "Annotation"
        }
    }

    var accent: Color {
        switch self {
        case .zoom: .blue
        case .trim: .red
        case .annotation: .purple
        }
    }
}

enum TimelineCameraMergeDirection: Equatable {
    case previous
    case next
}

struct TimelineSpan: Codable, Equatable, Hashable {
    var start: Double
    var end: Double

    var duration: Double { max(0, end - start) }

    func normalized(duration: Double, minimumDuration: Double = 0.10) -> TimelineSpan {
        guard duration.isFinite, duration > 0 else { return TimelineSpan(start: 0, end: 0) }
        let safeMinimum = min(max(0.01, minimumDuration), duration)
        let clampedStart = min(max(start, 0), max(0, duration - safeMinimum))
        let clampedEnd = min(max(end, clampedStart + safeMinimum), duration)
        return TimelineSpan(start: clampedStart, end: clampedEnd)
    }

    func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

struct TimelineZoomRegion: Identifiable, Codable, Equatable, Hashable {
    var id = TimelineRegionID()
    var span: TimelineSpan
    var depth: Double = TimelineZoomDepth.defaultDepth
    var focusX: Double = 0.5
    var focusY: Double = 0.5
    var mode: TimelineZoomMode = .manual
    var animationPreset: TimelineZoomAnimationPreset = .balanced
    var sourceClickTimestamp: Int?

    init(
        id: TimelineRegionID = TimelineRegionID(),
        span: TimelineSpan,
        depth: Double = TimelineZoomDepth.defaultDepth,
        focusX: Double = 0.5,
        focusY: Double = 0.5,
        mode: TimelineZoomMode = .manual,
        animationPreset: TimelineZoomAnimationPreset = .balanced,
        sourceClickTimestamp: Int? = nil
    ) {
        self.id = id
        self.span = span
        self.depth = depth
        self.focusX = focusX
        self.focusY = focusY
        self.mode = mode
        self.animationPreset = animationPreset
        self.sourceClickTimestamp = sourceClickTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case span
        case depth
        case focusX
        case focusY
        case mode
        case animationPreset
        case sourceClickTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(TimelineRegionID.self, forKey: .id) ?? TimelineRegionID()
        span = try container.decode(TimelineSpan.self, forKey: .span)
        depth = try container.decodeIfPresent(Double.self, forKey: .depth) ?? TimelineZoomDepth.defaultDepth
        focusX = try container.decodeIfPresent(Double.self, forKey: .focusX) ?? 0.5
        focusY = try container.decodeIfPresent(Double.self, forKey: .focusY) ?? 0.5
        mode = try container.decodeIfPresent(TimelineZoomMode.self, forKey: .mode) ?? .manual
        animationPreset = try container.decodeIfPresent(TimelineZoomAnimationPreset.self, forKey: .animationPreset) ?? .balanced
        sourceClickTimestamp = try container.decodeIfPresent(Int.self, forKey: .sourceClickTimestamp)
    }
}

struct TimelineTrimRegion: Identifiable, Codable, Equatable, Hashable {
    var id = TimelineRegionID()
    var span: TimelineSpan
}

struct TimelineAnnotationRegion: Identifiable, Codable, Equatable, Hashable {
    var id = TimelineRegionID()
    var span: TimelineSpan
    var text = "Annotation"
    var x = 0.5
    var y = 0.28
    var fontSize: CGFloat = 34
}

struct TimelineCameraClip: Identifiable, Codable, Equatable, Hashable {
    var id = TimelineRegionID()
    var span: TimelineSpan
    var settings: FacecamSettings

    init(
        id: TimelineRegionID = TimelineRegionID(),
        span: TimelineSpan,
        settings: FacecamSettings
    ) {
        self.id = id
        self.span = span
        self.settings = settings.clamped
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case span
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(TimelineRegionID.self, forKey: .id) ?? TimelineRegionID()
        span = try container.decode(TimelineSpan.self, forKey: .span)
        settings = (try container.decodeIfPresent(FacecamSettings.self, forKey: .settings) ?? defaultFacecamSettings(enabled: true)).clamped
    }
}

struct TimelineClipSegment: Identifiable, Equatable {
    var index: Int
    var start: Double
    var end: Double
    var speed: Double = TimelineClipSpeed.defaultSpeed

    var id: Int { index }
    var span: TimelineSpan { TimelineSpan(start: start, end: end) }

    static func segments(duration: Double, splitTimes: [Double], clipSpeeds: [Int: Double] = [:]) -> [TimelineClipSegment] {
        guard duration.isFinite, duration > 0 else {
            return [TimelineClipSegment(index: 0, start: 0, end: 0)]
        }

        let boundaries = ([0, duration] + splitTimes)
            .map { min(max($0, 0), duration) }
            .filter { $0.isFinite }
            .sorted()

        let uniqueBoundaries = boundaries.reduce(into: [Double]()) { result, boundary in
            if result.last.map({ abs($0 - boundary) > 0.001 }) ?? true {
                result.append(boundary)
            }
        }

        return uniqueBoundaries.dropLast().enumerated().compactMap { index, start in
            let end = uniqueBoundaries[index + 1]
            guard end - start > 0.001 else { return nil }
            return TimelineClipSegment(index: index, start: start, end: end, speed: TimelineClipSpeed.normalized(clipSpeeds[index] ?? TimelineClipSpeed.defaultSpeed))
        }
    }
}

enum TimelineClipSpeed {
    static let defaultSpeed = 1.0
    static let values: [Double] = [1.0, 1.25, 1.5, 1.75, 2.0]

    static func normalized(_ speed: Double) -> Double {
        guard speed.isFinite else { return defaultSpeed }
        return values.min { abs($0 - speed) < abs($1 - speed) } ?? defaultSpeed
    }

    static func label(_ speed: Double) -> String {
        let normalizedSpeed = normalized(speed)
        if abs(normalizedSpeed.rounded() - normalizedSpeed) < 0.001 {
            return "\(Int(normalizedSpeed.rounded()))x"
        }
        if abs((normalizedSpeed * 2).rounded() - normalizedSpeed * 2) < 0.001 {
            return String(format: "%.1fx", normalizedSpeed)
        }
        return String(format: "%.2fx", normalizedSpeed)
    }

    static func storedValue(_ speed: Double) -> Double? {
        let normalizedSpeed = normalized(speed)
        return normalizedSpeed == defaultSpeed ? nil : normalizedSpeed
    }
}

struct TimelineEditSnapshot: Codable, Equatable, Hashable {
    var zoomRegions: [TimelineZoomRegion] = []
    var trimRegions: [TimelineTrimRegion] = []
    var annotationRegions: [TimelineAnnotationRegion] = []
    var clipSplitTimes: [Double] = []
    var clipSpeeds: [Int: Double] = [:]
    var cameraClips: [TimelineCameraClip] = []

    static let empty = TimelineEditSnapshot()

    init(
        zoomRegions: [TimelineZoomRegion] = [],
        trimRegions: [TimelineTrimRegion] = [],
        annotationRegions: [TimelineAnnotationRegion] = [],
        clipSplitTimes: [Double] = [],
        clipSpeeds: [Int: Double] = [:],
        cameraClips: [TimelineCameraClip] = []
    ) {
        self.zoomRegions = zoomRegions
        self.trimRegions = trimRegions
        self.annotationRegions = annotationRegions
        self.clipSplitTimes = clipSplitTimes
        self.clipSpeeds = clipSpeeds
        self.cameraClips = cameraClips.map { TimelineCameraClip(id: $0.id, span: $0.span, settings: $0.settings) }
    }

    private enum CodingKeys: String, CodingKey {
        case zoomRegions
        case trimRegions
        case annotationRegions
        case clipSplitTimes
        case clipSpeeds
        case cameraClips
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoomRegions = try container.decodeIfPresent([TimelineZoomRegion].self, forKey: .zoomRegions) ?? []
        trimRegions = try container.decodeIfPresent([TimelineTrimRegion].self, forKey: .trimRegions) ?? []
        annotationRegions = try container.decodeIfPresent([TimelineAnnotationRegion].self, forKey: .annotationRegions) ?? []
        clipSplitTimes = try container.decodeIfPresent([Double].self, forKey: .clipSplitTimes) ?? []
        clipSpeeds = try container.decodeIfPresent([Int: Double].self, forKey: .clipSpeeds) ?? [:]
        cameraClips = try container.decodeIfPresent([TimelineCameraClip].self, forKey: .cameraClips) ?? []
    }

    var hasEdits: Bool {
        !zoomRegions.isEmpty || !trimRegions.isEmpty || !annotationRegions.isEmpty || !clipSplitTimes.isEmpty || hasClipSpeedEdits || !cameraClips.isEmpty
    }

    var hasClipSpeedEdits: Bool {
        clipSpeeds.values.contains { TimelineClipSpeed.normalized($0) != TimelineClipSpeed.defaultSpeed }
    }

    func activeZoom(at time: Double) -> TimelineZoomRegion? {
        zoomRegions.sorted { $0.span.start < $1.span.start }.last { $0.span.contains(time) }
    }

    func activeZoomEffect(at time: Double, cursorTrack: CursorTelemetryTrack? = nil) -> TimelineZoomEffect? {
        guard let zoom = activeZoom(at: time) else { return nil }
        let depth = TimelineZoomAnimator.animatedDepth(for: zoom, at: time)
        let focus = TimelineZoomFocusResolver.focus(
            for: zoom,
            at: time,
            depth: depth,
            cursorTrack: cursorTrack
        )
        return TimelineZoomEffect(
            depth: depth,
            focusX: focus.x,
            focusY: focus.y
        )
    }

    func clipSegments(duration: Double) -> [TimelineClipSegment] {
        TimelineClipSegment.segments(duration: duration, splitTimes: clipSplitTimes, clipSpeeds: clipSpeeds)
    }

    func clip(at time: Double, duration: Double) -> TimelineClipSegment? {
        let segments = clipSegments(duration: duration)
        return segments.first { time >= $0.start && (time < $0.end || $0.index == segments.last?.index) }
    }

    func activeSpeed(at time: Double, duration: Double) -> Double {
        clip(at: time, duration: duration)?.speed ?? TimelineClipSpeed.defaultSpeed
    }

    func nextTrimEnd(containing time: Double) -> Double? {
        trimRegions.sorted { $0.span.start < $1.span.start }.first { $0.span.contains(time) }?.span.end
    }

    func annotations(at time: Double) -> [TimelineAnnotationRegion] {
        annotationRegions.filter { $0.span.contains(time) }.sorted { $0.span.start < $1.span.start }
    }

    func resolvedCameraClips(duration: Double, fallback: FacecamSettings?) -> [TimelineCameraClip] {
        let normalized = cameraClips
            .map { TimelineCameraClip(id: $0.id, span: $0.span.normalized(duration: duration), settings: $0.settings) }
            .filter { $0.span.duration > 0.001 }
            .sorted { $0.span.start < $1.span.start }

        if !normalized.isEmpty {
            return normalized
        }

        guard duration.isFinite,
              duration > 0,
              let fallback = fallback?.clamped else {
            return []
        }

        return [
            TimelineCameraClip(
                span: TimelineSpan(start: 0, end: duration),
                settings: fallback
            )
        ]
    }

    func activeCameraSettings(at time: Double, duration: Double, fallback: FacecamSettings?) -> FacecamSettings? {
        guard duration.isFinite,
              duration > 0 else {
            return nil
        }

        let clips = resolvedCameraClips(duration: duration, fallback: fallback)
        guard let clip = clips.last(where: { time >= $0.span.start && (time < $0.span.end || abs($0.span.end - duration) < 0.001) }) else {
            return nil
        }

        let settings = clip.settings.clamped
        return settings.enabled ? settings : nil
    }
}

struct TimelineZoomEffect: Equatable {
    var depth: Double
    var focusX: Double
    var focusY: Double
}

enum TimelineZoomCanvasTransform {
    static func transform(for effect: TimelineZoomEffect?, in rect: CGRect, flipsY: Bool = false) -> CGAffineTransform {
        guard let effect else { return .identity }
        let depth = CGFloat(max(1, effect.depth))
        guard depth > 1,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.width > 0,
              rect.height > 0 else {
            return .identity
        }

        let focus = CGPoint(
            x: rect.minX + rect.width * CGFloat(effect.focusX),
            y: rect.minY + rect.height * CGFloat(flipsY ? 1 - effect.focusY : effect.focusY)
        )
        return CGAffineTransform(translationX: -focus.x, y: -focus.y)
            .concatenating(CGAffineTransform(scaleX: depth, y: depth))
            .concatenating(CGAffineTransform(translationX: focus.x, y: focus.y))
    }

    static func activeEffect(
        edits: TimelineEditSnapshot,
        editPlan: TimelineExportEditPlan,
        outputTime: Double,
        cursorTrack: CursorTelemetryTrack? = nil
    ) -> TimelineZoomEffect? {
        guard outputTime.isFinite else { return nil }
        let active = edits.zoomRegions
            .sorted { $0.span.start < $1.span.start }
            .compactMap { zoom -> (TimelineZoomRegion, TimelineSpan)? in
                guard let outputSpan = editPlan.outputSpans(forSourceSpan: zoom.span).last(where: { $0.contains(outputTime) }) else {
                    return nil
                }
                return (zoom, outputSpan)
            }
            .last
        guard let (zoom, outputSpan) = active else { return nil }

        let progress = TimelineZoomAnimator.animationProgress(for: outputSpan, preset: zoom.animationPreset, at: outputTime)
        let depth = 1 + (max(1, zoom.depth) - 1) * progress
        let sourceTime = editPlan.sourceTime(forOutputTime: outputTime) ?? outputTime
        let focus = TimelineZoomFocusResolver.focus(
            for: zoom,
            at: sourceTime,
            depth: depth,
            cursorTrack: cursorTrack
        )
        return TimelineZoomEffect(
            depth: depth,
            focusX: focus.x,
            focusY: focus.y
        )
    }
}

enum TimelineZoomAnimator {
    static let rampInSeconds = TimelineZoomAnimationPreset.balanced.configuration.rampInSeconds
    static let rampOutSeconds = TimelineZoomAnimationPreset.balanced.configuration.rampOutSeconds

    static func animatedDepth(for zoom: TimelineZoomRegion, at time: Double) -> Double {
        let progress = animationProgress(for: zoom, at: time)
        return 1 + (max(1, zoom.depth) - 1) * progress
    }

    static func animationProgress(for span: TimelineSpan, at time: Double) -> Double {
        animationProgress(for: span, preset: .balanced, at: time)
    }

    static func animationProgress(for zoom: TimelineZoomRegion, at time: Double) -> Double {
        animationProgress(for: zoom.span, preset: zoom.animationPreset, at: time)
    }

    static func animationProgress(for span: TimelineSpan, preset: TimelineZoomAnimationPreset, at time: Double) -> Double {
        guard span.duration > 0, span.contains(time) else { return 0 }

        let config = preset.configuration
        let rampIn = min(config.rampInSeconds, span.duration * 0.4)
        let rampOut = min(config.rampOutSeconds, span.duration * 0.4)
        if rampIn > 0, time < span.start + rampIn {
            return config.easing.value((time - span.start) / rampIn)
        }
        if rampOut > 0, time > span.end - rampOut {
            return config.easing.value((span.end - time) / rampOut)
        }
        return 1
    }
}

enum TimelineZoomFocusResolver {
    static func focus(
        for zoom: TimelineZoomRegion,
        at time: Double,
        depth: Double,
        cursorTrack: CursorTelemetryTrack?
    ) -> CGPoint {
        let config = zoom.animationPreset.configuration
        let staticFocus = CGPoint(
            x: clamped(zoom.focusX, in: config.focusClampRange),
            y: clamped(zoom.focusY, in: config.focusClampRange)
        )
        guard config.followsCursor,
              let cursorTrack,
              !cursorTrack.samples.isEmpty,
              time.isFinite else {
            return staticFocus
        }

        let rampOut = min(config.rampOutSeconds, zoom.span.duration * 0.4)
        let holdEnd = max(zoom.span.start, zoom.span.end - rampOut)
        let effectiveTime = min(max(time, zoom.span.start), holdEnd)
        guard let cursorPoint = cursorTrack.normalizedPointAtOrBefore(seconds: effectiveTime) else {
            return staticFocus
        }

        let safeZoneRatio = min(max(config.safeZoneRatio, 0), 0.49)
        let visibleHalfSpan = 1 / (2 * max(depth, 1))
        let safeInset = visibleHalfSpan * 2 * safeZoneRatio
        var focus = staticFocus
        let cursorFocus = CGPoint(
            x: clamped(cursorPoint.x, in: config.focusClampRange),
            y: clamped(cursorPoint.y, in: config.focusClampRange)
        )

        let safeLeft = focus.x - visibleHalfSpan + safeInset
        let safeRight = focus.x + visibleHalfSpan - safeInset
        let safeTop = focus.y - visibleHalfSpan + safeInset
        let safeBottom = focus.y + visibleHalfSpan - safeInset

        if cursorFocus.x < safeLeft || cursorFocus.x > safeRight {
            focus.x = cursorFocus.x
        }
        if cursorFocus.y < safeTop || cursorFocus.y > safeBottom {
            focus.y = cursorFocus.y
        }

        return CGPoint(
            x: clamped(focus.x, in: config.focusClampRange),
            y: clamped(focus.y, in: config.focusClampRange)
        )
    }

    private static func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct TimelineEditState: Equatable {
    var snapshot = TimelineEditSnapshot.empty
    var selectedKind: TimelineRegionKind?
    var selectedID: TimelineRegionID?
    var selectedClipIndex: Int?
    var selectedCameraClipID: TimelineRegionID?
    var statusMessage = "Use shortcuts to edit. Space plays, Z zooms, S cycles clip speed, T splits clips, C splits camera."

    static let empty = TimelineEditState()

    var hasSelection: Bool {
        selectedClipIndex != nil || selectedCameraClipID != nil || (selectedKind != nil && selectedID != nil)
    }
}

enum TimelineEditEvent: Equatable {
    case applySnapshot(TimelineEditSnapshot)
    case reset
    case add(TimelineRegionKind, currentTime: Double, duration: Double)
    case regenerateAutoZoomsRequested(videoURL: URL?, duration: Double, preset: TimelineZoomAnimationPreset)
    case replaceAutoZooms([TimelineZoomRegion])
    case addClipSplit(currentTime: Double, duration: Double)
    case ensureCameraClips(duration: Double, fallback: FacecamSettings?)
    case splitCameraClip(currentTime: Double, duration: Double, fallback: FacecamSettings?)
    case deleteRecordingClip(index: Int, duration: Double)
    case selectCameraClip(TimelineRegionID)
    case updateCameraClipSettings(id: TimelineRegionID, settings: FacecamSettings)
    case mergeCameraClip(id: TimelineRegionID, direction: TimelineCameraMergeDirection)
    case deleteCameraClip(id: TimelineRegionID, duration: Double, fallback: FacecamSettings?)
    case select(TimelineRegionKind?, TimelineRegionID?)
    case selectClip(index: Int)
    case clearSelection
    case deleteSelection(duration: Double?)
    case updateSpan(kind: TimelineRegionKind, id: TimelineRegionID, span: TimelineSpan, duration: Double)
    case cycleClipSpeed(index: Int)
    case cycleClipSpeedAt(currentTime: Double, duration: Double)
    case updateClipSpeed(index: Int, speed: Double)
    case deepenZoom(id: TimelineRegionID)
    case updateZoomDepth(id: TimelineRegionID, depth: Double)
    case updateZoomFocus(id: TimelineRegionID, focusX: Double?, focusY: Double?)
    case updateZoomAnimationPreset(id: TimelineRegionID, preset: TimelineZoomAnimationPreset)
    case updateAnnotationText(id: TimelineRegionID, text: String)
    case removeClipSplit(splitTime: Double, duration: Double)
}

enum TimelineEditEffect: Equatable {
    case generateAutoZooms(URL, duration: Double, preset: TimelineZoomAnimationPreset)
}

extension TimelineEditState {
    mutating func applying(_ event: TimelineEditEvent) -> [TimelineEditEffect] {
        switch event {
        case .applySnapshot(let snapshot):
            self.snapshot = snapshot
            clearSelection()
            statusMessage = Self.empty.statusMessage
            return []

        case .reset:
            snapshot = .empty
            clearSelection()
            statusMessage = "Timeline edits reset."
            return []

        case .add(let kind, let currentTime, let duration):
            add(kind, at: currentTime, duration: duration)
            return []

        case .regenerateAutoZoomsRequested(let videoURL, let duration, let preset):
            guard let videoURL else {
                statusMessage = "Open a recording before generating automatic zooms."
                return []
            }
            return [.generateAutoZooms(videoURL, duration: duration, preset: preset)]

        case .replaceAutoZooms(let generatedZooms):
            replaceAutoZooms(with: generatedZooms)
            return []

        case .addClipSplit(let currentTime, let duration):
            addClipSplit(at: currentTime, duration: duration)
            return []

        case .ensureCameraClips(let duration, let fallback):
            ensureCameraClips(duration: duration, fallback: fallback)
            return []

        case .splitCameraClip(let currentTime, let duration, let fallback):
            splitCameraClip(at: currentTime, duration: duration, fallback: fallback)
            return []

        case .deleteRecordingClip(let index, let duration):
            deleteRecordingClip(index: index, duration: duration)
            return []

        case .selectCameraClip(let id):
            selectCameraClip(id: id)
            return []

        case .updateCameraClipSettings(let id, let settings):
            updateCameraClipSettings(id: id, settings: settings)
            return []

        case .mergeCameraClip(let id, let direction):
            mergeCameraClip(id: id, direction: direction)
            return []

        case .deleteCameraClip(let id, let duration, let fallback):
            deleteCameraClip(id: id, duration: duration, fallback: fallback)
            return []

        case .select(let kind, let id):
            select(kind, id: id)
            return []

        case .selectClip(let index):
            selectClip(index: index)
            return []

        case .clearSelection:
            clearSelection()
            return []

        case .deleteSelection(let duration):
            deleteSelection(duration: duration)
            return []

        case .updateSpan(let kind, let id, let span, let duration):
            updateSpan(kind: kind, id: id, span: span, duration: duration)
            return []

        case .cycleClipSpeed(let index):
            cycleClipSpeed(index: index)
            return []

        case .cycleClipSpeedAt(let currentTime, let duration):
            cycleClipSpeed(at: currentTime, duration: duration)
            return []

        case .updateClipSpeed(let index, let speed):
            updateClipSpeed(index: index, speed: speed)
            return []

        case .deepenZoom(let id):
            deepenZoom(id: id)
            return []

        case .updateZoomDepth(let id, let depth):
            updateZoomDepth(id: id, depth: depth)
            return []

        case .updateZoomFocus(let id, let focusX, let focusY):
            updateZoomFocus(id: id, focusX: focusX, focusY: focusY)
            return []

        case .updateZoomAnimationPreset(let id, let preset):
            updateZoomAnimationPreset(id: id, preset: preset)
            return []

        case .updateAnnotationText(let id, let text):
            updateAnnotationText(id: id, text: text)
            return []

        case .removeClipSplit(let splitTime, let duration):
            removeClipSplit(at: splitTime, duration: duration)
            return []
        }
    }

    func selectedClip(duration: Double) -> TimelineClipSegment? {
        guard let selectedClipIndex else { return nil }
        let segments = snapshot.clipSegments(duration: duration)
        guard segments.indices.contains(selectedClipIndex) else { return nil }
        return segments[selectedClipIndex]
    }

    func selectedCameraClip(duration: Double, fallback: FacecamSettings?) -> TimelineCameraClip? {
        guard let selectedCameraClipID else { return nil }
        return snapshot.resolvedCameraClips(duration: duration, fallback: fallback).first { $0.id == selectedCameraClipID }
    }

    func canDeleteRecordingClip(index: Int, duration: Double) -> Bool {
        guard let candidate = recordingClipDeletionCandidate(index: index, duration: duration),
              !isClipOmitted(candidate.segment, trimRegions: snapshot.trimRegions) else {
            return false
        }
        return !TimelineExportEditPlan.build(duration: duration, edits: candidate.snapshot).segments.isEmpty
    }

    func canDeleteCameraClip(id: TimelineRegionID, duration: Double, fallback: FacecamSettings?) -> Bool {
        guard duration.isFinite, duration > 0 else { return false }
        let clips = snapshot.resolvedCameraClips(duration: duration, fallback: fallback)
        guard clips.count > 1,
              let clip = clips.first(where: { $0.id == id }) else {
            return false
        }
        return clip.settings.clamped.enabled
    }

    func clipSpeed(index: Int) -> Double {
        TimelineClipSpeed.normalized(snapshot.clipSpeeds[index] ?? TimelineClipSpeed.defaultSpeed)
    }

    private mutating func add(_ kind: TimelineRegionKind, at currentTime: Double, duration: Double) {
        guard duration.isFinite, duration > 0 else {
            statusMessage = "Open a video before adding timeline edits."
            return
        }

        let defaultDuration = min(1.0, duration)
        let start = min(max(currentTime, 0), duration)
        let span = TimelineSpan(start: start, end: min(start + defaultDuration, duration)).normalized(duration: duration)

        switch kind {
        case .zoom:
            guard canPlaceNonOverlapping(span, existing: snapshot.zoomRegions.map(\.span)) else {
                statusMessage = "Cannot place zoom on top of another zoom."
                return
            }
            let region = TimelineZoomRegion(span: span, mode: .manual)
            snapshot.zoomRegions.append(region)
            select(.zoom, id: region.id)
        case .trim:
            statusMessage = "Use clip splitting instead of trim sections."
            select(nil, id: nil)
            return
        case .annotation:
            statusMessage = "Annotations are currently unavailable."
            select(nil, id: nil)
            return
        }

        statusMessage = "Added \(kind.title.lowercased()) at \(formatPlaybackTime(span.start))."
    }

    private mutating func replaceAutoZooms(with generatedZooms: [TimelineZoomRegion]) {
        snapshot.zoomRegions.removeAll { $0.mode == .auto }
        snapshot.zoomRegions.append(contentsOf: generatedZooms.map { zoom in
            var copy = zoom
            copy.mode = .auto
            return copy
        })
        snapshot.zoomRegions.sort { $0.span.start < $1.span.start }
        clearSelection()
        statusMessage = generatedZooms.isEmpty
            ? "No clicks found. Add a manual zoom with Z."
            : "Generated \(generatedZooms.count) automatic \(generatedZooms.count == 1 ? "zoom" : "zooms")."
    }

    private mutating func addClipSplit(at currentTime: Double, duration: Double) {
        guard duration.isFinite, duration > 0 else {
            statusMessage = "Open a video before splitting the clip."
            return
        }

        let minimumDistance = min(0.05, duration / 4)
        let splitTime = min(max(currentTime, 0), duration)
        guard splitTime > minimumDistance, splitTime < duration - minimumDistance else {
            statusMessage = "Move the playhead inside the clip before splitting."
            return
        }

        guard !snapshot.clipSplitTimes.contains(where: { abs($0 - splitTime) < minimumDistance }) else {
            statusMessage = "There is already a split at \(formatPlaybackTime(splitTime))."
            return
        }

        let oldSegments = TimelineClipSegment.segments(
            duration: duration,
            splitTimes: snapshot.clipSplitTimes,
            clipSpeeds: snapshot.clipSpeeds
        )
        snapshot.clipSplitTimes.append(splitTime)
        snapshot.clipSplitTimes.sort()
        let newSegments = TimelineClipSegment.segments(duration: duration, splitTimes: snapshot.clipSplitTimes, clipSpeeds: [:])
        snapshot.clipSpeeds = remappedClipSpeeds(from: oldSegments, to: newSegments)
        clearSelection()
        statusMessage = "Split clip at \(formatPlaybackTime(splitTime))."
    }

    private mutating func ensureCameraClips(duration: Double, fallback: FacecamSettings?) {
        guard snapshot.cameraClips.isEmpty,
              duration.isFinite,
              duration > 0,
              let fallback = fallback?.clamped else {
            return
        }

        snapshot.cameraClips = [
            TimelineCameraClip(
                span: TimelineSpan(start: 0, end: duration),
                settings: fallback
            )
        ]
    }

    private mutating func splitCameraClip(at currentTime: Double, duration: Double, fallback: FacecamSettings?) {
        ensureCameraClips(duration: duration, fallback: fallback)
        guard duration.isFinite, duration > 0, !snapshot.cameraClips.isEmpty else {
            statusMessage = "Record with camera before splitting camera settings."
            return
        }

        let minimumDistance = min(0.05, duration / 4)
        let splitTime = min(max(currentTime, 0), duration)
        guard splitTime > minimumDistance, splitTime < duration - minimumDistance else {
            statusMessage = "Move the playhead inside the camera clip before splitting."
            return
        }

        var clips = snapshot.resolvedCameraClips(duration: duration, fallback: fallback)
        guard let index = clips.firstIndex(where: { splitTime > $0.span.start + minimumDistance && splitTime < $0.span.end - minimumDistance }) else {
            statusMessage = "There is already a camera split at \(formatPlaybackTime(splitTime))."
            return
        }

        let clip = clips[index]
        let left = TimelineCameraClip(
            id: clip.id,
            span: TimelineSpan(start: clip.span.start, end: splitTime),
            settings: clip.settings
        )
        let right = TimelineCameraClip(
            span: TimelineSpan(start: splitTime, end: clip.span.end),
            settings: clip.settings
        )
        clips.replaceSubrange(index...index, with: [left, right])
        snapshot.cameraClips = clips
        selectCameraClip(id: right.id)
        statusMessage = "Split camera at \(formatPlaybackTime(splitTime))."
    }

    private mutating func select(_ kind: TimelineRegionKind?, id: TimelineRegionID?) {
        selectedClipIndex = nil
        selectedCameraClipID = nil
        guard let kind, let id else {
            selectedKind = nil
            selectedID = nil
            return
        }
        selectedKind = kind
        selectedID = id
    }

    private mutating func selectClip(index: Int) {
        selectedKind = nil
        selectedID = nil
        selectedCameraClipID = nil
        selectedClipIndex = max(0, index)
    }

    private mutating func selectCameraClip(id: TimelineRegionID) {
        selectedKind = nil
        selectedID = nil
        selectedClipIndex = nil
        selectedCameraClipID = id
    }

    private mutating func clearSelection() {
        selectedKind = nil
        selectedID = nil
        selectedClipIndex = nil
        selectedCameraClipID = nil
    }

    private mutating func deleteSelection(duration: Double? = nil) {
        if let selectedClipIndex {
            deleteSelectedClip(index: selectedClipIndex, duration: duration)
            return
        }

        if let selectedCameraClipID, let duration {
            deleteCameraClip(id: selectedCameraClipID, duration: duration, fallback: nil)
            return
        }

        guard let selectedKind, let selectedID else { return }
        switch selectedKind {
        case .zoom: snapshot.zoomRegions.removeAll { $0.id == selectedID }
        case .trim: snapshot.trimRegions.removeAll { $0.id == selectedID }
        case .annotation: snapshot.annotationRegions.removeAll { $0.id == selectedID }
        }
        clearSelection()
        statusMessage = "Deleted \(selectedKind.title.lowercased())."
    }

    private mutating func deleteSelectedClip(index selectedClipIndex: Int, duration: Double?) {
        guard let duration,
              duration.isFinite,
              duration > 0 else {
            statusMessage = "Open a video before deleting a clip."
            return
        }

        deleteRecordingClip(index: selectedClipIndex, duration: duration)
    }

    private mutating func deleteRecordingClip(index selectedClipIndex: Int, duration: Double) {
        guard duration.isFinite, duration > 0 else {
            statusMessage = "Open a video before deleting a clip."
            return
        }

        let segments = snapshot.clipSegments(duration: duration)
        guard segments.indices.contains(selectedClipIndex) else {
            clearSelection()
            statusMessage = "Selected clip is no longer available."
            return
        }

        let segment = segments[selectedClipIndex]
        guard !isClipOmitted(segment, trimRegions: snapshot.trimRegions) else {
            statusMessage = "Clip \(segment.index + 1) is already deleted."
            return
        }

        guard let candidate = recordingClipDeletionCandidate(index: selectedClipIndex, duration: duration)?.snapshot else {
            clearSelection()
            statusMessage = "Selected clip is no longer available."
            return
        }
        guard !TimelineExportEditPlan.build(duration: duration, edits: candidate).segments.isEmpty else {
            statusMessage = "Cannot delete the only playable clip."
            return
        }

        snapshot = candidate
        clearSelection()
        statusMessage = "Deleted clip \(segment.index + 1)."
    }

    private func recordingClipDeletionCandidate(index selectedClipIndex: Int, duration: Double) -> (segment: TimelineClipSegment, snapshot: TimelineEditSnapshot)? {
        guard duration.isFinite, duration > 0 else { return nil }
        let segments = snapshot.clipSegments(duration: duration)
        guard segments.indices.contains(selectedClipIndex) else { return nil }

        let segment = segments[selectedClipIndex]
        let deleteRegion = TimelineTrimRegion(span: segment.span.normalized(duration: duration))
        var candidate = snapshot
        candidate.trimRegions.append(deleteRegion)
        candidate.trimRegions = mergedTrimRegions(candidate.trimRegions, duration: duration)
        return (segment, candidate)
    }

    private func isClipOmitted(_ segment: TimelineClipSegment, trimRegions: [TimelineTrimRegion]) -> Bool {
        trimRegions.contains { region in
            region.span.start <= segment.start + 0.001 && region.span.end >= segment.end - 0.001
        }
    }

    private mutating func updateSpan(kind: TimelineRegionKind, id: TimelineRegionID, span: TimelineSpan, duration: Double) {
        let normalized = span.normalized(duration: duration)
        switch kind {
        case .zoom:
            mutate(&snapshot.zoomRegions, id: id) { $0.span = normalized }
        case .trim:
            mutate(&snapshot.trimRegions, id: id) { $0.span = normalized }
        case .annotation:
            mutate(&snapshot.annotationRegions, id: id) { $0.span = normalized }
        }
    }

    private mutating func cycleClipSpeed(index: Int) {
        let currentSpeed = clipSpeed(index: index)
        let currentIndex = TimelineClipSpeed.values.firstIndex(of: currentSpeed) ?? 0
        let nextSpeed = TimelineClipSpeed.values[(currentIndex + 1) % TimelineClipSpeed.values.count]
        updateClipSpeed(index: index, speed: nextSpeed)
    }

    private mutating func cycleClipSpeed(at currentTime: Double, duration: Double) {
        guard duration.isFinite, duration > 0 else {
            statusMessage = "Open a video before changing clip speed."
            return
        }

        let segments = TimelineClipSegment.segments(
            duration: duration,
            splitTimes: snapshot.clipSplitTimes,
            clipSpeeds: snapshot.clipSpeeds
        )
        let targetIndex = selectedClipIndex.flatMap { selected in
            segments.indices.contains(selected) ? selected : nil
        } ?? segments.first { currentTime >= $0.start && (currentTime < $0.end || $0.index == segments.last?.index) }?.index

        guard let targetIndex else {
            statusMessage = "Move the playhead onto a clip before changing speed."
            return
        }

        selectClip(index: targetIndex)
        cycleClipSpeed(index: targetIndex)
    }

    private mutating func updateClipSpeed(index: Int, speed: Double) {
        guard index >= 0 else { return }
        if let storedSpeed = TimelineClipSpeed.storedValue(speed) {
            snapshot.clipSpeeds[index] = storedSpeed
        } else {
            snapshot.clipSpeeds.removeValue(forKey: index)
        }
        statusMessage = "Set Clip \(index + 1) speed to \(TimelineClipSpeed.label(speed))."
    }

    private mutating func deepenZoom(id: TimelineRegionID) {
        let values = TimelineZoomDepth.values
        mutate(&snapshot.zoomRegions, id: id) { region in
            let nearest = values.enumerated().min { abs($0.element - region.depth) < abs($1.element - region.depth) }?.offset ?? 1
            region.depth = values[(nearest + 1) % values.count]
        }
    }

    private mutating func updateZoomDepth(id: TimelineRegionID, depth: Double) {
        mutate(&snapshot.zoomRegions, id: id) { region in
            region.depth = min(max(depth, 1.0), 5.0)
        }
    }

    private mutating func updateZoomFocus(id: TimelineRegionID, focusX: Double? = nil, focusY: Double? = nil) {
        mutate(&snapshot.zoomRegions, id: id) { region in
            if let focusX {
                region.focusX = min(max(focusX, 0), 1)
            }
            if let focusY {
                region.focusY = min(max(focusY, 0), 1)
            }
            region.mode = .manual
            region.sourceClickTimestamp = nil
        }
    }

    private mutating func updateZoomAnimationPreset(id: TimelineRegionID, preset: TimelineZoomAnimationPreset) {
        mutate(&snapshot.zoomRegions, id: id) { region in
            region.animationPreset = preset
        }
        statusMessage = "Set zoom style to \(preset.title)."
    }

    private mutating func updateAnnotationText(id: TimelineRegionID, text: String) {
        mutate(&snapshot.annotationRegions, id: id) { $0.text = text }
    }

    private mutating func updateCameraClipSettings(id: TimelineRegionID, settings: FacecamSettings) {
        mutate(&snapshot.cameraClips, id: id) { clip in
            clip.settings = settings.clamped
        }
        selectedCameraClipID = id
        statusMessage = "Updated camera settings."
    }

    private mutating func mergeCameraClip(id: TimelineRegionID, direction: TimelineCameraMergeDirection) {
        let clips = snapshot.cameraClips.sorted { $0.span.start < $1.span.start }
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }

        let neighborIndex: Int
        switch direction {
        case .previous:
            neighborIndex = index - 1
        case .next:
            neighborIndex = index + 1
        }
        guard clips.indices.contains(neighborIndex) else { return }

        let selected = clips[index]
        let neighbor = clips[neighborIndex]
        let merged = TimelineCameraClip(
            id: selected.id,
            span: TimelineSpan(
                start: min(selected.span.start, neighbor.span.start),
                end: max(selected.span.end, neighbor.span.end)
            ),
            settings: selected.settings
        )

        var next = clips
        for removeIndex in [index, neighborIndex].sorted(by: >) {
            next.remove(at: removeIndex)
        }
        next.append(merged)
        snapshot.cameraClips = next.sorted { $0.span.start < $1.span.start }
        selectCameraClip(id: selected.id)
        statusMessage = "Merged camera clips."
    }

    private mutating func deleteCameraClip(id: TimelineRegionID, duration: Double, fallback: FacecamSettings?) {
        guard duration.isFinite, duration > 0 else {
            statusMessage = "Open a video before deleting a camera clip."
            return
        }

        var clips = snapshot.resolvedCameraClips(duration: duration, fallback: fallback)
        guard clips.count > 1 else {
            statusMessage = "Cannot delete the only camera clip."
            return
        }

        guard let index = clips.firstIndex(where: { $0.id == id }) else {
            clearSelection()
            statusMessage = "Selected camera clip is no longer available."
            return
        }

        guard clips[index].settings.clamped.enabled else {
            statusMessage = "Camera clip is already deleted."
            return
        }

        var settings = clips[index].settings.clamped
        settings.enabled = false
        clips[index].settings = settings
        snapshot.cameraClips = clips
        selectCameraClip(id: id)
        statusMessage = "Deleted camera clip."
    }

    private mutating func removeClipSplit(at splitTime: Double, duration: Double) {
        guard let index = snapshot.clipSplitTimes.firstIndex(where: { abs($0 - splitTime) < 0.001 }) else { return }
        let oldSegments = TimelineClipSegment.segments(
            duration: duration,
            splitTimes: snapshot.clipSplitTimes,
            clipSpeeds: snapshot.clipSpeeds
        )
        snapshot.clipSplitTimes.remove(at: index)
        let newSegments = TimelineClipSegment.segments(duration: duration, splitTimes: snapshot.clipSplitTimes, clipSpeeds: [:])
        snapshot.clipSpeeds = remappedClipSpeeds(from: oldSegments, to: newSegments)
        clearSelection()
        statusMessage = "Removed split at \(formatPlaybackTime(splitTime))."
    }

    private func mergedTrimRegions(_ regions: [TimelineTrimRegion], duration: Double) -> [TimelineTrimRegion] {
        let sorted = regions
            .map { region in
                var copy = region
                copy.span = copy.span.normalized(duration: duration)
                return copy
            }
            .filter { $0.span.duration > 0.001 }
            .sorted { $0.span.start < $1.span.start }

        return sorted.reduce(into: [TimelineTrimRegion]()) { result, region in
            guard var last = result.popLast() else {
                result.append(region)
                return
            }

            if region.span.start <= last.span.end + 0.001 {
                last.span = TimelineSpan(
                    start: min(last.span.start, region.span.start),
                    end: max(last.span.end, region.span.end)
                ).normalized(duration: duration)
                result.append(last)
            } else {
                result.append(last)
                result.append(region)
            }
        }
    }

    private func canPlaceNonOverlapping(_ span: TimelineSpan, existing: [TimelineSpan]) -> Bool {
        !existing.contains { span.end > $0.start && span.start < $0.end }
    }

    private func remappedClipSpeeds(from oldSegments: [TimelineClipSegment], to newSegments: [TimelineClipSegment]) -> [Int: Double] {
        newSegments.reduce(into: [Int: Double]()) { result, segment in
            let probeTime = min(max(segment.start + 0.001, 0), max(segment.end - 0.001, 0))
            let sourceSegment = oldSegments.first { old in
                probeTime >= old.start && (probeTime < old.end || old.index == oldSegments.last?.index)
            }
            guard let speed = sourceSegment?.speed, let storedSpeed = TimelineClipSpeed.storedValue(speed) else { return }
            result[segment.index] = storedSpeed
        }
    }

    private func mutate<T: Identifiable>(_ array: inout [T], id: T.ID, update: (inout T) -> Void) where T.ID: Equatable {
        guard let index = array.firstIndex(where: { $0.id == id }) else { return }
        update(&array[index])
    }
}

@Observable
@MainActor
final class TimelineEditDriver {
    var state = TimelineEditState.empty
    private var historyRevision = 0
    @ObservationIgnored private var history = EditorHistory<TimelineEditState>()

    var snapshot: TimelineEditSnapshot {
        state.snapshot
    }

    var hasSelection: Bool {
        state.hasSelection
    }

    var canUndo: Bool {
        _ = historyRevision
        return history.canUndo
    }

    var canRedo: Bool {
        _ = historyRevision
        return history.canRedo
    }

    var zoomRegions: [TimelineZoomRegion] {
        get { state.snapshot.zoomRegions }
        set { state.snapshot.zoomRegions = newValue }
    }

    var trimRegions: [TimelineTrimRegion] {
        get { state.snapshot.trimRegions }
        set { state.snapshot.trimRegions = newValue }
    }

    var annotationRegions: [TimelineAnnotationRegion] {
        get { state.snapshot.annotationRegions }
        set { state.snapshot.annotationRegions = newValue }
    }

    var clipSplitTimes: [Double] {
        get { state.snapshot.clipSplitTimes }
        set { state.snapshot.clipSplitTimes = newValue }
    }

    var clipSpeeds: [Int: Double] {
        get { state.snapshot.clipSpeeds }
        set { state.snapshot.clipSpeeds = newValue }
    }

    var cameraClips: [TimelineCameraClip] {
        get { state.snapshot.cameraClips }
        set { state.snapshot.cameraClips = newValue }
    }

    var selectedKind: TimelineRegionKind? {
        get { state.selectedKind }
        set { state.selectedKind = newValue }
    }

    var selectedID: TimelineRegionID? {
        get { state.selectedID }
        set { state.selectedID = newValue }
    }

    var selectedClipIndex: Int? {
        get { state.selectedClipIndex }
        set { state.selectedClipIndex = newValue }
    }

    var selectedCameraClipID: TimelineRegionID? {
        get { state.selectedCameraClipID }
        set { state.selectedCameraClipID = newValue }
    }

    var statusMessage: String {
        get { state.statusMessage }
        set { state.statusMessage = newValue }
    }

    func undo() {
        guard let previous = history.undo(current: state) else { return }
        state = previous
        state.statusMessage = "Undid timeline edit."
        historyRevision += 1
    }

    func redo() {
        guard let next = history.redo(current: state) else { return }
        state = next
        state.statusMessage = "Redid timeline edit."
        historyRevision += 1
    }

    func resetHistory() {
        history.reset()
        historyRevision += 1
    }

    func beginUndoTransaction() {
        history.beginTransaction(current: state)
    }

    func endUndoTransaction() {
        if history.commitTransaction(current: state, shouldRecord: timelineContentChanged) {
            historyRevision += 1
        }
    }

    func cancelUndoTransaction() {
        history.cancelTransaction()
        historyRevision += 1
    }

    func reset() {
        send(.reset)
    }

    func add(_ kind: TimelineRegionKind, at currentTime: Double, duration: Double) {
        send(.add(kind, currentTime: currentTime, duration: duration))
    }

    func applySnapshot(_ snapshot: TimelineEditSnapshot) {
        send(.applySnapshot(snapshot), recordsUndo: false)
        resetHistory()
    }

    func regenerateAutoZooms(from videoURL: URL?, duration: Double, preset: TimelineZoomAnimationPreset) {
        send(.regenerateAutoZoomsRequested(videoURL: videoURL, duration: duration, preset: preset))
    }

    func replaceAutoZooms(with generatedZooms: [TimelineZoomRegion]) {
        send(.replaceAutoZooms(generatedZooms))
    }

    func addClipSplit(at currentTime: Double, duration: Double) {
        send(.addClipSplit(currentTime: currentTime, duration: duration))
    }

    func ensureCameraClips(duration: Double, fallback: FacecamSettings?) {
        send(.ensureCameraClips(duration: duration, fallback: fallback), recordsUndo: false)
    }

    func splitCameraClip(at currentTime: Double, duration: Double, fallback: FacecamSettings?) {
        send(.splitCameraClip(currentTime: currentTime, duration: duration, fallback: fallback))
    }

    func deleteRecordingClip(index: Int, duration: Double) {
        send(.deleteRecordingClip(index: index, duration: duration))
    }

    func canDeleteRecordingClip(index: Int, duration: Double) -> Bool {
        state.canDeleteRecordingClip(index: index, duration: duration)
    }

    func selectCameraClip(id: TimelineRegionID) {
        send(.selectCameraClip(id), recordsUndo: false)
    }

    func select(_ kind: TimelineRegionKind?, id: TimelineRegionID?) {
        send(.select(kind, id), recordsUndo: false)
    }

    func selectClip(index: Int) {
        send(.selectClip(index: index), recordsUndo: false)
    }

    func clearSelection() {
        send(.clearSelection, recordsUndo: false)
    }

    func deleteSelection() {
        send(.deleteSelection(duration: nil))
    }

    func deleteSelection(duration: Double) {
        send(.deleteSelection(duration: duration))
    }

    func updateSpan(kind: TimelineRegionKind, id: TimelineRegionID, span: TimelineSpan, duration: Double) {
        send(.updateSpan(kind: kind, id: id, span: span, duration: duration))
    }

    func cycleClipSpeed(index: Int) {
        send(.cycleClipSpeed(index: index))
    }

    func cycleClipSpeed(at currentTime: Double, duration: Double) {
        send(.cycleClipSpeedAt(currentTime: currentTime, duration: duration))
    }

    func updateClipSpeed(index: Int, speed: Double) {
        send(.updateClipSpeed(index: index, speed: speed))
    }

    func clipSpeed(index: Int) -> Double {
        state.clipSpeed(index: index)
    }

    func deepenZoom(id: TimelineRegionID) {
        send(.deepenZoom(id: id))
    }

    func updateZoomDepth(id: TimelineRegionID, depth: Double) {
        send(.updateZoomDepth(id: id, depth: depth))
    }

    func updateZoomFocus(id: TimelineRegionID, focusX: Double? = nil, focusY: Double? = nil) {
        send(.updateZoomFocus(id: id, focusX: focusX, focusY: focusY))
    }

    func updateZoomAnimationPreset(id: TimelineRegionID, preset: TimelineZoomAnimationPreset) {
        send(.updateZoomAnimationPreset(id: id, preset: preset))
    }

    func updateAnnotationText(id: TimelineRegionID, text: String) {
        send(.updateAnnotationText(id: id, text: text))
    }

    func selectedClip(duration: Double) -> TimelineClipSegment? {
        state.selectedClip(duration: duration)
    }

    func selectedCameraClip(duration: Double, fallback: FacecamSettings?) -> TimelineCameraClip? {
        state.selectedCameraClip(duration: duration, fallback: fallback)
    }

    func resolvedCameraClips(duration: Double, fallback: FacecamSettings?) -> [TimelineCameraClip] {
        state.snapshot.resolvedCameraClips(duration: duration, fallback: fallback)
    }

    func updateCameraClipSettings(id: TimelineRegionID, settings: FacecamSettings) {
        send(.updateCameraClipSettings(id: id, settings: settings))
    }

    func mergeCameraClip(id: TimelineRegionID, direction: TimelineCameraMergeDirection) {
        send(.mergeCameraClip(id: id, direction: direction))
    }

    func deleteCameraClip(id: TimelineRegionID, duration: Double, fallback: FacecamSettings?) {
        send(.deleteCameraClip(id: id, duration: duration, fallback: fallback))
    }

    func canDeleteCameraClip(id: TimelineRegionID, duration: Double, fallback: FacecamSettings?) -> Bool {
        state.canDeleteCameraClip(id: id, duration: duration, fallback: fallback)
    }

    func removeClipSplit(at splitTime: Double, duration: Double) {
        send(.removeClipSplit(splitTime: splitTime, duration: duration))
    }

    func send(_ event: TimelineEditEvent, recordsUndo: Bool = true) {
        let before = state
        let effects = state.applying(event)
        if recordsUndo {
            history.recordChange(from: before, to: state, shouldRecord: timelineContentChanged)
            if before.snapshot != state.snapshot {
                historyRevision += 1
            }
        }
        perform(effects)
    }

    private func perform(_ effects: [TimelineEditEffect]) {
        for effect in effects {
            switch effect {
            case .generateAutoZooms(let videoURL, let duration, let preset):
                let telemetryURL = CursorTelemetryRecorder.telemetryURL(for: videoURL)
                let generated = AutoZoomGenerator.generate(from: telemetryURL, duration: duration, preset: preset)
                replaceAutoZooms(with: generated)
            }
        }
    }

    private func timelineContentChanged(_ before: TimelineEditState, _ after: TimelineEditState) -> Bool {
        before.snapshot != after.snapshot
    }
}

struct TimelineExportEditPlan: Equatable {
    struct Segment: Equatable {
        var sourceStart: Double
        var sourceEnd: Double
        var outputStart: Double
        var outputEnd: Double
        var speed: Double
    }

    var segments: [Segment]
    var outputDuration: Double

    static func build(duration: Double, edits: TimelineEditSnapshot) -> TimelineExportEditPlan {
        guard duration.isFinite, duration > 0 else { return TimelineExportEditPlan(segments: [], outputDuration: 0) }
        var boundaries: [Double] = [0, duration]
        boundaries.append(contentsOf: edits.trimRegions.flatMap { [$0.span.start, $0.span.end] })
        boundaries.append(contentsOf: edits.zoomRegions.flatMap { [$0.span.start, $0.span.end] })
        boundaries.append(contentsOf: edits.annotationRegions.flatMap { [$0.span.start, $0.span.end] })
        boundaries.append(contentsOf: edits.cameraClips.flatMap { [$0.span.start, $0.span.end] })
        boundaries.append(contentsOf: edits.clipSplitTimes)

        let sorted = Set(boundaries.map { min(max($0, 0.0), duration) }).sorted()
        var outputCursor = 0.0
        var segments: [Segment] = []

        for index in 0..<(sorted.count - 1) {
            let start = sorted[index]
            let end = sorted[index + 1]
            guard end - start > 0.001 else { continue }
            let midpoint = (start + end) / 2
            if edits.nextTrimEnd(containing: midpoint) != nil { continue }
            let speed = edits.activeSpeed(at: midpoint, duration: duration)
            let outputDuration = (end - start) / max(0.05, speed)
            segments.append(Segment(sourceStart: start, sourceEnd: end, outputStart: outputCursor, outputEnd: outputCursor + outputDuration, speed: speed))
            outputCursor += outputDuration
        }

        return TimelineExportEditPlan(segments: segments, outputDuration: outputCursor)
    }

    func outputTime(forSourceTime sourceTime: Double) -> Double? {
        for segment in segments where sourceTime >= segment.sourceStart && sourceTime <= segment.sourceEnd {
            return segment.outputStart + (sourceTime - segment.sourceStart) / max(0.05, segment.speed)
        }
        return nil
    }

    func outputSpans(forSourceSpan sourceSpan: TimelineSpan) -> [TimelineSpan] {
        guard sourceSpan.duration > 0 else { return [] }
        return segments.compactMap { segment in
            let clippedStart = max(sourceSpan.start, segment.sourceStart)
            let clippedEnd = min(sourceSpan.end, segment.sourceEnd)
            guard clippedEnd - clippedStart > 0.001 else { return nil }

            let speed = max(0.05, segment.speed)
            let outputStart = segment.outputStart + (clippedStart - segment.sourceStart) / speed
            let outputEnd = segment.outputStart + (clippedEnd - segment.sourceStart) / speed
            guard outputEnd - outputStart > 0.001 else { return nil }
            return TimelineSpan(start: outputStart, end: outputEnd)
        }
    }

    func sourceTime(forOutputTime outputTime: Double) -> Double? {
        for segment in segments where outputTime >= segment.outputStart && outputTime <= segment.outputEnd {
            return segment.sourceStart + (outputTime - segment.outputStart) * max(0.05, segment.speed)
        }
        return nil
    }
}
