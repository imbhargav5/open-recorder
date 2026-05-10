import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI

typealias TimelineRegionID = UUID

enum TimelineRegionKind: String, CaseIterable, Identifiable {
    case zoom
    case trim
    case annotation
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zoom: "Zoom"
        case .trim: "Trim"
        case .annotation: "Annotation"
        case .speed: "Speed"
        }
    }

    var accent: Color {
        switch self {
        case .zoom: .blue
        case .trim: .red
        case .annotation: .purple
        case .speed: .orange
        }
    }
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
    var depth: Double = 1.8
    var focusX: Double = 0.5
    var focusY: Double = 0.5
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

struct TimelineSpeedRegion: Identifiable, Codable, Equatable, Hashable {
    var id = TimelineRegionID()
    var span: TimelineSpan
    var speed: Double = 1.5
}

struct TimelineClipSegment: Identifiable, Equatable {
    var index: Int
    var start: Double
    var end: Double

    var id: Int { index }
    var span: TimelineSpan { TimelineSpan(start: start, end: end) }

    static func segments(duration: Double, splitTimes: [Double]) -> [TimelineClipSegment] {
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
            return TimelineClipSegment(index: index, start: start, end: end)
        }
    }
}

struct TimelineEditSnapshot: Equatable {
    var zoomRegions: [TimelineZoomRegion] = []
    var trimRegions: [TimelineTrimRegion] = []
    var annotationRegions: [TimelineAnnotationRegion] = []
    var speedRegions: [TimelineSpeedRegion] = []
    var clipSplitTimes: [Double] = []

    static let empty = TimelineEditSnapshot()

    var hasEdits: Bool {
        !zoomRegions.isEmpty || !trimRegions.isEmpty || !annotationRegions.isEmpty || !speedRegions.isEmpty || !clipSplitTimes.isEmpty
    }

    func activeZoom(at time: Double) -> TimelineZoomRegion? {
        zoomRegions.sorted { $0.span.start < $1.span.start }.last { $0.span.contains(time) }
    }

    func activeSpeed(at time: Double) -> TimelineSpeedRegion? {
        speedRegions.sorted { $0.span.start < $1.span.start }.last { $0.span.contains(time) }
    }

    func nextTrimEnd(containing time: Double) -> Double? {
        trimRegions.sorted { $0.span.start < $1.span.start }.first { $0.span.contains(time) }?.span.end
    }

    func annotations(at time: Double) -> [TimelineAnnotationRegion] {
        annotationRegions.filter { $0.span.contains(time) }.sorted { $0.span.start < $1.span.start }
    }
}

@MainActor
final class TimelineEditController: ObservableObject {
    @Published var zoomRegions: [TimelineZoomRegion] = []
    @Published var trimRegions: [TimelineTrimRegion] = []
    @Published var annotationRegions: [TimelineAnnotationRegion] = []
    @Published var speedRegions: [TimelineSpeedRegion] = []
    @Published var clipSplitTimes: [Double] = []
    @Published var selectedKind: TimelineRegionKind?
    @Published var selectedID: TimelineRegionID?
    @Published var selectedClipIndex: Int?
    @Published var statusMessage = "Use toolbar buttons or shortcuts. Space plays, Z zooms, S changes speed, T splits."

    var snapshot: TimelineEditSnapshot {
        TimelineEditSnapshot(
            zoomRegions: zoomRegions,
            trimRegions: trimRegions,
            annotationRegions: annotationRegions,
            speedRegions: speedRegions,
            clipSplitTimes: clipSplitTimes
        )
    }

    var hasSelection: Bool {
        selectedClipIndex != nil || (selectedKind != nil && selectedID != nil)
    }

    func reset() {
        zoomRegions.removeAll()
        trimRegions.removeAll()
        annotationRegions.removeAll()
        speedRegions.removeAll()
        clipSplitTimes.removeAll()
        clearSelection()
        statusMessage = "Timeline edits reset."
    }

    func add(_ kind: TimelineRegionKind, at currentTime: Double, duration: Double) {
        guard duration.isFinite, duration > 0 else {
            statusMessage = "Open a video before adding timeline edits."
            return
        }

        let defaultDuration = min(1.0, duration)
        let start = min(max(currentTime, 0), duration)
        let span = TimelineSpan(start: start, end: min(start + defaultDuration, duration)).normalized(duration: duration)

        switch kind {
        case .zoom:
            guard canPlaceNonOverlapping(span, existing: zoomRegions.map(\.span)) else {
                statusMessage = "Cannot place zoom on top of another zoom."
                return
            }
            let region = TimelineZoomRegion(span: span)
            zoomRegions.append(region)
            select(.zoom, id: region.id)
        case .trim:
            guard canPlaceNonOverlapping(span, existing: trimRegions.map(\.span)) else {
                statusMessage = "Cannot place trim on top of another trim."
                return
            }
            let region = TimelineTrimRegion(span: span)
            trimRegions.append(region)
            select(.trim, id: region.id)
        case .annotation:
            statusMessage = "Annotations are currently unavailable."
            select(nil, id: nil)
            return
        case .speed:
            guard canPlaceNonOverlapping(span, existing: speedRegions.map(\.span)) else {
                statusMessage = "Cannot place speed on top of another speed region."
                return
            }
            let region = TimelineSpeedRegion(span: span)
            speedRegions.append(region)
            select(.speed, id: region.id)
        }
        statusMessage = "Added \(kind.title.lowercased()) at \(formatPlaybackTime(span.start))."
    }

    func addClipSplit(at currentTime: Double, duration: Double) {
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

        guard !clipSplitTimes.contains(where: { abs($0 - splitTime) < minimumDistance }) else {
            statusMessage = "There is already a split at \(formatPlaybackTime(splitTime))."
            return
        }

        clipSplitTimes.append(splitTime)
        clipSplitTimes.sort()
        clearSelection()
        statusMessage = "Split clip at \(formatPlaybackTime(splitTime))."
    }

    func select(_ kind: TimelineRegionKind?, id: TimelineRegionID?) {
        selectedClipIndex = nil
        guard let kind, let id else {
            selectedKind = nil
            selectedID = nil
            return
        }
        selectedKind = kind
        selectedID = id
    }

    func selectClip(index: Int) {
        selectedKind = nil
        selectedID = nil
        selectedClipIndex = max(0, index)
    }

    func clearSelection() {
        selectedKind = nil
        selectedID = nil
        selectedClipIndex = nil
    }

    func deleteSelection() {
        guard let selectedKind, let selectedID else { return }
        switch selectedKind {
        case .zoom: zoomRegions.removeAll { $0.id == selectedID }
        case .trim: trimRegions.removeAll { $0.id == selectedID }
        case .annotation: annotationRegions.removeAll { $0.id == selectedID }
        case .speed: speedRegions.removeAll { $0.id == selectedID }
        }
        clearSelection()
        statusMessage = "Deleted \(selectedKind.title.lowercased())."
    }

    func updateSpan(kind: TimelineRegionKind, id: TimelineRegionID, span: TimelineSpan, duration: Double) {
        let normalized = span.normalized(duration: duration)
        switch kind {
        case .zoom:
            mutate(&zoomRegions, id: id) { $0.span = normalized }
        case .trim:
            mutate(&trimRegions, id: id) { $0.span = normalized }
        case .annotation:
            mutate(&annotationRegions, id: id) { $0.span = normalized }
        case .speed:
            mutate(&speedRegions, id: id) { $0.span = normalized }
        }
    }

    func cycleSpeed(id: TimelineRegionID) {
        let values = [0.25, 0.5, 0.75, 1.25, 1.5, 1.75, 2.0]
        mutate(&speedRegions, id: id) { region in
            let index = values.firstIndex(of: region.speed) ?? 3
            region.speed = values[(index + 1) % values.count]
        }
    }

    func updateSpeed(id: TimelineRegionID, speed: Double) {
        mutate(&speedRegions, id: id) { region in
            region.speed = min(max(speed, 0.25), 2.0)
        }
    }

    func deepenZoom(id: TimelineRegionID) {
        let values = [1.25, 1.5, 1.8, 2.2, 3.5, 5.0]
        mutate(&zoomRegions, id: id) { region in
            let nearest = values.enumerated().min { abs($0.element - region.depth) < abs($1.element - region.depth) }?.offset ?? 1
            region.depth = values[(nearest + 1) % values.count]
        }
    }

    func updateZoomDepth(id: TimelineRegionID, depth: Double) {
        mutate(&zoomRegions, id: id) { region in
            region.depth = min(max(depth, 1.0), 5.0)
        }
    }

    func updateAnnotationText(id: TimelineRegionID, text: String) {
        mutate(&annotationRegions, id: id) { $0.text = text }
    }

    func selectedClip(duration: Double) -> TimelineClipSegment? {
        guard let selectedClipIndex else { return nil }
        let segments = TimelineClipSegment.segments(duration: duration, splitTimes: clipSplitTimes)
        guard segments.indices.contains(selectedClipIndex) else { return nil }
        return segments[selectedClipIndex]
    }

    func removeClipSplit(at splitTime: Double) {
        guard let index = clipSplitTimes.firstIndex(where: { abs($0 - splitTime) < 0.001 }) else { return }
        clipSplitTimes.remove(at: index)
        clearSelection()
        statusMessage = "Removed split at \(formatPlaybackTime(splitTime))."
    }

    private func canPlaceNonOverlapping(_ span: TimelineSpan, existing: [TimelineSpan]) -> Bool {
        !existing.contains { span.end > $0.start && span.start < $0.end }
    }

    private func mutate<T: Identifiable>(_ array: inout [T], id: T.ID, update: (inout T) -> Void) where T.ID: Equatable {
        guard let index = array.firstIndex(where: { $0.id == id }) else { return }
        update(&array[index])
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
        boundaries.append(contentsOf: edits.speedRegions.flatMap { [$0.span.start, $0.span.end] })
        boundaries.append(contentsOf: edits.zoomRegions.flatMap { [$0.span.start, $0.span.end] })
        boundaries.append(contentsOf: edits.annotationRegions.flatMap { [$0.span.start, $0.span.end] })
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
            let speed = edits.activeSpeed(at: midpoint)?.speed ?? 1
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
}
