import AppKit
import SwiftUI

struct TimelineSelectionSidebar: View {
    @ObservedObject var edits: TimelineEditController
    @ObservedObject var playback: VideoPlaybackController

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    selectionHeader
                    selectionContent
                }
                .padding(12)
            }

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            selectionFooter
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 12)
    }

    private var selectionHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: selectionSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectionAccent)
                .frame(width: 30, height: 30)
                .background(selectionAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(selectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(selectionSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private var selectionContent: some View {
        if let clip = edits.selectedClip(duration: playback.duration) {
            clipControls(clip)
        } else if let kind = edits.selectedKind, let id = edits.selectedID {
            regionControls(kind: kind, id: id)
        } else {
            unavailableSelection
        }
    }

    private var selectionFooter: some View {
        HStack(spacing: 8) {
            TimelineSelectionActionButton(title: "Clear", symbolName: "xmark") {
                edits.clearSelection()
            }

            if edits.selectedKind != nil {
                TimelineSelectionActionButton(title: "Delete", symbolName: "trash", isDestructive: true) {
                    edits.deleteSelection()
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.025))
    }

    @ViewBuilder
    private func clipControls(_ clip: TimelineClipSegment) -> some View {
        InspectorGroup(title: "Clip", symbolName: "rectangle.on.rectangle") {
            TimelineSelectionInfoRow(title: "Start", value: formatPlaybackTime(clip.start))
            TimelineSelectionInfoRow(title: "End", value: formatPlaybackTime(clip.end))
            TimelineSelectionInfoRow(title: "Duration", value: formatClipDuration(clip.end - clip.start))
        }

        InspectorGroup(title: "Split", symbolName: "timeline.selection") {
            TimelineSelectionActionButton(title: "Split at Playhead", symbolName: "scissors") {
                edits.addClipSplit(at: playback.currentTime, duration: playback.duration)
            }

            if clip.start > 0.001 {
                TimelineSelectionActionButton(title: "Merge Previous", symbolName: "arrow.left.to.line") {
                    edits.removeClipSplit(at: clip.start)
                }
            }

            if playback.duration - clip.end > 0.001 {
                TimelineSelectionActionButton(title: "Merge Next", symbolName: "arrow.right.to.line") {
                    edits.removeClipSplit(at: clip.end)
                }
            }
        }
    }

    @ViewBuilder
    private func regionControls(kind: TimelineRegionKind, id: TimelineRegionID) -> some View {
        if let span = selectedRegionSpan(kind: kind, id: id) {
            InspectorGroup(title: "Timing", symbolName: "timer") {
                TimelineSelectionInfoRow(title: "Start", value: formatPlaybackTime(span.start))
                TimelineSelectionInfoRow(title: "End", value: formatPlaybackTime(span.end))
                TimelineSelectionInfoRow(title: "Duration", value: formatClipDuration(span.duration))
            }
        }

        switch kind {
        case .zoom:
            if let zoom = edits.zoomRegions.first(where: { $0.id == id }) {
                InspectorGroup(title: "Zoom", symbolName: "plus.magnifyingglass") {
                    InspectorSlider(
                        title: "Depth",
                        valueText: String(format: "%.2fx", zoom.depth),
                        value: zoomDepthBinding(id: id),
                        range: 1.0...5.0,
                        step: 0.05
                    )
                    TimelineSelectionActionButton(title: "Cycle Depth", symbolName: "arrow.triangle.2.circlepath") {
                        edits.deepenZoom(id: id)
                    }
                }
            } else {
                unavailableSelection
            }
        case .trim:
            InspectorGroup(title: "Trim", symbolName: "scissors") {
                Text("This range is removed during preview and export.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .speed:
            if let speed = edits.speedRegions.first(where: { $0.id == id }) {
                InspectorGroup(title: "Speed", symbolName: "speedometer") {
                    InspectorSlider(
                        title: "Rate",
                        valueText: String(format: "%.2gx", speed.speed),
                        value: speedBinding(id: id),
                        range: 0.25...2.0,
                        step: 0.25
                    )
                    TimelineSelectionActionButton(title: "Cycle Speed", symbolName: "arrow.triangle.2.circlepath") {
                        edits.cycleSpeed(id: id)
                    }
                }
            } else {
                unavailableSelection
            }
        case .annotation:
            InspectorGroup(title: "Annotation", symbolName: "text.bubble") {
                TextField("Annotation text", text: annotationTextBinding(id: id))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var unavailableSelection: some View {
        InspectorGroup(title: "Selection", symbolName: "exclamationmark.triangle") {
            Text("This selection is no longer available.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectionTitle: String {
        if let clip = edits.selectedClip(duration: playback.duration) {
            return "Selected Clip \(clip.index + 1)"
        }
        if let kind = edits.selectedKind {
            return "Selected \(kind.title)"
        }
        return "Selection"
    }

    private var selectionSubtitle: String {
        if let clip = edits.selectedClip(duration: playback.duration) {
            return "\(formatPlaybackTime(clip.start)) - \(formatPlaybackTime(clip.end))"
        }
        if let kind = edits.selectedKind, let id = edits.selectedID, let span = selectedRegionSpan(kind: kind, id: id) {
            return "\(formatPlaybackTime(span.start)) - \(formatPlaybackTime(span.end))"
        }
        return "No active segment"
    }

    private var selectionAccent: Color {
        if edits.selectedClipIndex != nil {
            return Color.timelineHandle
        }
        return edits.selectedKind?.accent ?? Color.brand
    }

    private var selectionSymbolName: String {
        if edits.selectedClipIndex != nil {
            return "rectangle.on.rectangle"
        }

        switch edits.selectedKind {
        case .zoom:
            return "plus.magnifyingglass"
        case .trim:
            return "scissors"
        case .speed:
            return "speedometer"
        case .annotation:
            return "text.bubble"
        case nil:
            return "timeline.selection"
        }
    }

    private func selectedRegionSpan(kind: TimelineRegionKind, id: TimelineRegionID) -> TimelineSpan? {
        switch kind {
        case .zoom:
            edits.zoomRegions.first { $0.id == id }?.span
        case .trim:
            edits.trimRegions.first { $0.id == id }?.span
        case .annotation:
            edits.annotationRegions.first { $0.id == id }?.span
        case .speed:
            edits.speedRegions.first { $0.id == id }?.span
        }
    }

    private func zoomDepthBinding(id: TimelineRegionID) -> Binding<Double> {
        Binding(
            get: { edits.zoomRegions.first(where: { $0.id == id })?.depth ?? 1 },
            set: { edits.updateZoomDepth(id: id, depth: $0) }
        )
    }

    private func speedBinding(id: TimelineRegionID) -> Binding<Double> {
        Binding(
            get: { edits.speedRegions.first(where: { $0.id == id })?.speed ?? 1 },
            set: { edits.updateSpeed(id: id, speed: $0) }
        )
    }

    private func annotationTextBinding(id: TimelineRegionID) -> Binding<String> {
        Binding(
            get: { edits.annotationRegions.first(where: { $0.id == id })?.text ?? "" },
            set: { edits.updateAnnotationText(id: id, text: $0) }
        )
    }
}

private struct TimelineSelectionInfoRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(0.78))
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.05))
        }
    }
}

private struct TimelineSelectionActionButton: View {
    var title: String
    var symbolName: String
    var isDestructive = false
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(8), action: action) {
            Label(title, systemImage: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundStyle(isDestructive ? Color.red.opacity(0.92) : Color.secondary)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDestructive ? Color.red.opacity(0.18) : Color.white.opacity(0.05))
                }
        }
    }
}
