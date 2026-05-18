import AppKit
import SwiftUI

struct TimelineSelectionSidebar: View {
    var edits: TimelineEditDriver
    var playback: VideoPlaybackController

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
        .studioEditorPaneChrome()
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
            TimelineSelectionInfoRow(title: "Speed", value: TimelineClipSpeed.label(clip.speed))
        }

        InspectorGroup(title: "Speed", symbolName: "speedometer") {
            TimelineClipSpeedPicker(speed: clipSpeedBinding(index: clip.index))
        }

        InspectorGroup(title: "Split", symbolName: "timeline.selection") {
            TimelineSelectionActionButton(title: "Split at Playhead", symbolName: "scissors") {
                edits.addClipSplit(at: playback.currentTime, duration: playback.duration)
            }

            if clip.start > 0.001 {
                TimelineSelectionActionButton(title: "Merge Previous", symbolName: "arrow.left.to.line") {
                    edits.removeClipSplit(at: clip.start, duration: playback.duration)
                }
            }

            if playback.duration - clip.end > 0.001 {
                TimelineSelectionActionButton(title: "Merge Next", symbolName: "arrow.right.to.line") {
                    edits.removeClipSplit(at: clip.end, duration: playback.duration)
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
                    TimelineSelectionInfoRow(title: "Type", value: zoom.mode == .auto ? "Auto" : "Manual")
                    TimelineZoomDepthPicker(depth: zoomDepthBinding(id: id))
                }

                InspectorGroup(title: "Focus", symbolName: "scope") {
                    InspectorSlider(
                        title: "X",
                        valueText: focusValueText(zoom.focusX),
                        value: zoomFocusXBinding(id: id),
                        range: 0...1,
                        step: 0.01,
                        onEditingChanged: handleUndoTransaction
                    )
                    InspectorSlider(
                        title: "Y",
                        valueText: focusValueText(zoom.focusY),
                        value: zoomFocusYBinding(id: id),
                        range: 0...1,
                        step: 0.01,
                        onEditingChanged: handleUndoTransaction
                    )
                }
            } else {
                unavailableSelection
            }
        case .trim:
            unavailableSelection
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
            return "\(formatPlaybackTime(clip.start)) - \(formatPlaybackTime(clip.end)) @ \(TimelineClipSpeed.label(clip.speed))"
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
        }
    }

    private func zoomDepthBinding(id: TimelineRegionID) -> Binding<Double> {
        Binding(
            get: { edits.zoomRegions.first(where: { $0.id == id })?.depth ?? 1 },
            set: { edits.updateZoomDepth(id: id, depth: $0) }
        )
    }

    private func zoomFocusXBinding(id: TimelineRegionID) -> Binding<Double> {
        Binding(
            get: { edits.zoomRegions.first(where: { $0.id == id })?.focusX ?? 0.5 },
            set: { edits.updateZoomFocus(id: id, focusX: $0) }
        )
    }

    private func zoomFocusYBinding(id: TimelineRegionID) -> Binding<Double> {
        Binding(
            get: { edits.zoomRegions.first(where: { $0.id == id })?.focusY ?? 0.5 },
            set: { edits.updateZoomFocus(id: id, focusY: $0) }
        )
    }

    private func clipSpeedBinding(index: Int) -> Binding<Double> {
        Binding(
            get: { edits.clipSpeed(index: index) },
            set: { edits.updateClipSpeed(index: index, speed: $0) }
        )
    }

    private func annotationTextBinding(id: TimelineRegionID) -> Binding<String> {
        Binding(
            get: { edits.annotationRegions.first(where: { $0.id == id })?.text ?? "" },
            set: { edits.updateAnnotationText(id: id, text: $0) }
        )
    }

    private func handleUndoTransaction(_ isEditing: Bool) {
        if isEditing {
            edits.beginUndoTransaction()
        } else {
            edits.endUndoTransaction()
        }
    }

    private func focusValueText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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

private struct TimelineClipSpeedPicker: View {
    @Binding var speed: Double

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TimelineClipSpeed.values, id: \.self) { value in
                let isSelected = TimelineClipSpeed.normalized(speed) == value
                StudioButton(hitTarget: .rounded(7)) {
                    speed = value
                } label: {
                    Text(TimelineClipSpeed.label(value))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .foregroundStyle(isSelected ? Color.timelineClipForeground : Color.secondary)
                        .background(isSelected ? Color.timelineHandle.opacity(0.92) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isSelected ? Color.timelineClipBorder : Color.white.opacity(0.05), lineWidth: isSelected ? 1.5 : 1)
                        }
                }
                .help("Set clip speed to \(TimelineClipSpeed.label(value))")
                .accessibilityLabel("Set clip speed to \(TimelineClipSpeed.label(value))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct TimelineZoomDepthPicker: View {
    @Binding var depth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Depth")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TimelineZoomDepth.label(depth))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.78))
            }

            HStack(spacing: 5) {
                ForEach(TimelineZoomDepth.values, id: \.self) { value in
                    let isSelected = abs(depth - value) < 0.001
                    StudioButton(hitTarget: .rounded(7)) {
                        if !isSelected {
                            depth = value
                        }
                    } label: {
                        Text(TimelineZoomDepth.label(value))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .background(isSelected ? Color.brand.opacity(0.18) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isSelected ? Color.brand.opacity(0.42) : Color.white.opacity(0.05), lineWidth: isSelected ? 1.5 : 1)
                            }
                    }
                    .help("Set zoom depth to \(TimelineZoomDepth.label(value))")
                    .accessibilityLabel("Set zoom depth to \(TimelineZoomDepth.label(value))")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
