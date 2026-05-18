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
    static let values = [1.0, 1.25, 1.5, 1.75, 2.0]

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
    var sourceClickTimestamp: Int?

    init(
        id: TimelineRegionID = TimelineRegionID(),
        span: TimelineSpan,
        depth: Double = TimelineZoomDepth.defaultDepth,
        focusX: Double = 0.5,
        focusY: Double = 0.5,
        mode: TimelineZoomMode = .manual,
        sourceClickTimestamp: Int? = nil
    ) {
        self.id = id
        self.span = span
        self.depth = depth
        self.focusX = focusX
        self.focusY = focusY
        self.mode = mode
        self.sourceClickTimestamp = sourceClickTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case span
        case depth
        case focusX
        case focusY
        case mode
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
    static let values = [1.0, 1.25, 1.5, 1.75, 2.0]

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

    static let empty = TimelineEditSnapshot()

    var hasEdits: Bool {
        !zoomRegions.isEmpty || !trimRegions.isEmpty || !annotationRegions.isEmpty || !clipSplitTimes.isEmpty || hasClipSpeedEdits
    }

    var hasClipSpeedEdits: Bool {
        clipSpeeds.values.contains { TimelineClipSpeed.normalized($0) != TimelineClipSpeed.defaultSpeed }
    }

    func activeZoom(at time: Double) -> TimelineZoomRegion? {
        zoomRegions.sorted { $0.span.start < $1.span.start }.last { $0.span.contains(time) }
    }

    func activeZoomEffect(at time: Double) -> TimelineZoomEffect? {
        guard let zoom = activeZoom(at: time) else { return nil }
        return TimelineZoomEffect(
            depth: TimelineZoomAnimator.animatedDepth(for: zoom, at: time),
            focusX: zoom.focusX,
            focusY: zoom.focusY
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
}

struct TimelineZoomEffect: Equatable {
    var depth: Double
    var focusX: Double
    var focusY: Double
}

enum TimelineZoomAnimator {
    static let rampInSeconds = 0.22
    static let rampOutSeconds = 0.25

    static func animatedDepth(for zoom: TimelineZoomRegion, at time: Double) -> Double {
        let progress = animationProgress(for: zoom.span, at: time)
        return 1 + (max(1, zoom.depth) - 1) * progress
    }

    static func animationProgress(for span: TimelineSpan, at time: Double) -> Double {
        guard span.duration > 0, span.contains(time) else { return 0 }

        let rampIn = min(rampInSeconds, span.duration * 0.4)
        let rampOut = min(rampOutSeconds, span.duration * 0.4)
        if rampIn > 0, time < span.start + rampIn {
            return smoothstep((time - span.start) / rampIn)
        }
        if rampOut > 0, time > span.end - rampOut {
            return smoothstep((span.end - time) / rampOut)
        }
        return 1
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

struct TimelineEditState: Equatable {
    var snapshot = TimelineEditSnapshot.empty
    var selectedKind: TimelineRegionKind?
    var selectedID: TimelineRegionID?
    var selectedClipIndex: Int?
    var statusMessage = "Use shortcuts to edit. Space plays, Z zooms, S cycles clip speed, T splits clips."

    static let empty = TimelineEditState()

    var hasSelection: Bool {
        selectedClipIndex != nil || (selectedKind != nil && selectedID != nil)
    }
}

enum TimelineEditEvent: Equatable {
    case applySnapshot(TimelineEditSnapshot)
    case reset
    case add(TimelineRegionKind, currentTime: Double, duration: Double)
    case regenerateAutoZoomsRequested(videoURL: URL?, duration: Double)
    case replaceAutoZooms([TimelineZoomRegion])
    case addClipSplit(currentTime: Double, duration: Double)
    case select(TimelineRegionKind?, TimelineRegionID?)
    case selectClip(index: Int)
    case clearSelection
    case deleteSelection
    case updateSpan(kind: TimelineRegionKind, id: TimelineRegionID, span: TimelineSpan, duration: Double)
    case cycleClipSpeed(index: Int)
    case cycleClipSpeedAt(currentTime: Double, duration: Double)
    case updateClipSpeed(index: Int, speed: Double)
    case deepenZoom(id: TimelineRegionID)
    case updateZoomDepth(id: TimelineRegionID, depth: Double)
    case updateZoomFocus(id: TimelineRegionID, focusX: Double?, focusY: Double?)
    case updateAnnotationText(id: TimelineRegionID, text: String)
    case removeClipSplit(splitTime: Double, duration: Double)
}

enum TimelineEditEffect: Equatable {
    case generateAutoZooms(URL, duration: Double)
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

        case .regenerateAutoZoomsRequested(let videoURL, let duration):
            guard let videoURL else {
                statusMessage = "Open a recording before generating automatic zooms."
                return []
            }
            return [.generateAutoZooms(videoURL, duration: duration)]

        case .replaceAutoZooms(let generatedZooms):
            replaceAutoZooms(with: generatedZooms)
            return []

        case .addClipSplit(let currentTime, let duration):
            addClipSplit(at: currentTime, duration: duration)
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

        case .deleteSelection:
            deleteSelection()
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

    private mutating func select(_ kind: TimelineRegionKind?, id: TimelineRegionID?) {
        selectedClipIndex = nil
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
        selectedClipIndex = max(0, index)
    }

    private mutating func clearSelection() {
        selectedKind = nil
        selectedID = nil
        selectedClipIndex = nil
    }

    private mutating func deleteSelection() {
        guard let selectedKind, let selectedID else { return }
        switch selectedKind {
        case .zoom: snapshot.zoomRegions.removeAll { $0.id == selectedID }
        case .trim: snapshot.trimRegions.removeAll { $0.id == selectedID }
        case .annotation: snapshot.annotationRegions.removeAll { $0.id == selectedID }
        }
        clearSelection()
        statusMessage = "Deleted \(selectedKind.title.lowercased())."
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

    private mutating func updateAnnotationText(id: TimelineRegionID, text: String) {
        mutate(&snapshot.annotationRegions, id: id) { $0.text = text }
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

    func regenerateAutoZooms(from videoURL: URL?, duration: Double) {
        send(.regenerateAutoZoomsRequested(videoURL: videoURL, duration: duration))
    }

    func replaceAutoZooms(with generatedZooms: [TimelineZoomRegion]) {
        send(.replaceAutoZooms(generatedZooms))
    }

    func addClipSplit(at currentTime: Double, duration: Double) {
        send(.addClipSplit(currentTime: currentTime, duration: duration))
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
        send(.deleteSelection)
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

    func updateAnnotationText(id: TimelineRegionID, text: String) {
        send(.updateAnnotationText(id: id, text: text))
    }

    func selectedClip(duration: Double) -> TimelineClipSegment? {
        state.selectedClip(duration: duration)
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
            case .generateAutoZooms(let videoURL, let duration):
                let telemetryURL = CursorTelemetryRecorder.telemetryURL(for: videoURL)
                let generated = AutoZoomGenerator.generate(from: telemetryURL, duration: duration)
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

    func sourceTime(forOutputTime outputTime: Double) -> Double? {
        for segment in segments where outputTime >= segment.outputStart && outputTime <= segment.outputEnd {
            return segment.sourceStart + (outputTime - segment.outputStart) * max(0.05, segment.speed)
        }
        return nil
    }
}
