import AppKit
import SwiftUI

struct TimelineSelectionSidebar: View {
    var edits: TimelineEditDriver
    var playback: VideoPlaybackController
    var defaultCameraSettings: FacecamSettings?

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
                .fill(Theme.border)
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
                .frame(width: 32, height: 32)
                .background(selectionAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(selectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(selectionSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surfaceRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .stroke(Theme.borderStrong.opacity(0.60), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var selectionContent: some View {
        if let clip = edits.selectedClip(duration: playback.duration) {
            clipControls(clip)
        } else if let cameraClip = edits.selectedCameraClip(duration: playback.duration, fallback: defaultCameraSettings) {
            cameraControls(cameraClip)
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

            if let cameraID = edits.selectedCameraClipID {
                TimelineSelectionActionButton(
                    title: "Delete",
                    symbolName: "trash",
                    isDestructive: true,
                    isEnabled: edits.canDeleteCameraClip(id: cameraID, duration: playback.duration, fallback: defaultCameraSettings)
                ) {
                    edits.deleteCameraClip(id: cameraID, duration: playback.duration, fallback: defaultCameraSettings)
                }
            } else if let clipIndex = edits.selectedClipIndex {
                TimelineSelectionActionButton(
                    title: "Delete",
                    symbolName: "trash",
                    isDestructive: true,
                    isEnabled: edits.canDeleteRecordingClip(index: clipIndex, duration: playback.duration)
                ) {
                    edits.deleteSelection(duration: playback.duration)
                }
            } else if edits.selectedKind != nil {
                TimelineSelectionActionButton(title: "Delete", symbolName: "trash", isDestructive: true) {
                    edits.deleteSelection(duration: playback.duration)
                }
            }
        }
        .padding(12)
        .background(Theme.surface.opacity(0.60))
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
    private func cameraControls(_ clip: TimelineCameraClip) -> some View {
        InspectorGroup(title: "Camera", symbolName: clip.settings.clamped.enabled ? "camera.fill" : "camera.slash.fill") {
            TimelineSelectionInfoRow(title: "Start", value: formatPlaybackTime(clip.span.start))
            TimelineSelectionInfoRow(title: "End", value: formatPlaybackTime(clip.span.end))
            TimelineSelectionInfoRow(title: "Duration", value: formatClipDuration(clip.span.duration))
        }

        InspectorGroup(title: "Visibility", symbolName: "eye") {
            InspectorSwitch(title: "Visible", isOn: cameraEnabledBinding(id: clip.id))
        }

        InspectorGroup(title: "Position", symbolName: "square.grid.3x3") {
            PositionGrid(selection: cameraAnchorBinding(id: clip.id))
        }

        InspectorGroup(title: "Style", symbolName: "slider.horizontal.3") {
            InspectorSlider(
                title: "Size",
                valueText: "\(Int(clip.settings.clamped.size.rounded()))%",
                value: cameraSizeBinding(id: clip.id),
                range: 12...40,
                step: 1,
                onEditingChanged: handleUndoTransaction
            )
            InspectorSlider(
                title: "Border",
                valueText: "\(Int(clip.settings.clamped.borderWidth.rounded()))px",
                value: cameraBorderWidthBinding(id: clip.id),
                range: 0...16,
                step: 1,
                onEditingChanged: handleUndoTransaction
            )
            InspectorSlider(
                title: "Margin",
                valueText: "\(Int(clip.settings.clamped.margin.rounded()))%",
                value: cameraMarginBinding(id: clip.id),
                range: 0...12,
                step: 1,
                onEditingChanged: handleUndoTransaction
            )
        }

        InspectorGroup(title: "Split", symbolName: "timeline.selection") {
            TimelineSelectionActionButton(title: "Split at Playhead", symbolName: "scissors") {
                edits.splitCameraClip(at: playback.currentTime, duration: playback.duration, fallback: defaultCameraSettings)
            }

            if clip.span.start > 0.001 {
                TimelineSelectionActionButton(title: "Merge Previous", symbolName: "arrow.left.to.line") {
                    edits.mergeCameraClip(id: clip.id, direction: .previous)
                }
            }

            if playback.duration - clip.span.end > 0.001 {
                TimelineSelectionActionButton(title: "Merge Next", symbolName: "arrow.right.to.line") {
                    edits.mergeCameraClip(id: clip.id, direction: .next)
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
                    TimelineZoomStylePicker(preset: zoomAnimationPresetBinding(id: id))
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
        if let clip = edits.selectedCameraClip(duration: playback.duration, fallback: defaultCameraSettings) {
            return clip.settings.clamped.enabled ? "Selected Camera" : "Hidden Camera"
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
        if let clip = edits.selectedCameraClip(duration: playback.duration, fallback: defaultCameraSettings) {
            return "\(formatPlaybackTime(clip.span.start)) - \(formatPlaybackTime(clip.span.end))"
        }
        if let kind = edits.selectedKind, let id = edits.selectedID, let span = selectedRegionSpan(kind: kind, id: id) {
            return "\(formatPlaybackTime(span.start)) - \(formatPlaybackTime(span.end))"
        }
        return "No active segment"
    }

    private var selectionAccent: Color {
        if edits.selectedClipIndex != nil {
            return Theme.timelineHandle
        }
        if edits.selectedCameraClipID != nil {
            return Theme.timelineCamera
        }
        return edits.selectedKind?.accent ?? Theme.accent
    }

    private var selectionSymbolName: String {
        if edits.selectedClipIndex != nil {
            return "rectangle.on.rectangle"
        }

        if edits.selectedCameraClipID != nil {
            return "camera.fill"
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

    private func zoomAnimationPresetBinding(id: TimelineRegionID) -> Binding<TimelineZoomAnimationPreset> {
        Binding(
            get: { edits.zoomRegions.first(where: { $0.id == id })?.animationPreset ?? .balanced },
            set: { edits.updateZoomAnimationPreset(id: id, preset: $0) }
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

    private func cameraEnabledBinding(id: TimelineRegionID) -> Binding<Bool> {
        cameraBinding(id: id, keyPath: \.enabled, default: true)
    }

    private func cameraSizeBinding(id: TimelineRegionID) -> Binding<Double> {
        cameraBinding(id: id, keyPath: \.size, default: defaultFacecamSettings(enabled: true).size)
    }

    private func cameraBorderWidthBinding(id: TimelineRegionID) -> Binding<Double> {
        cameraBinding(id: id, keyPath: \.borderWidth, default: defaultFacecamSettings(enabled: true).borderWidth)
    }

    private func cameraMarginBinding(id: TimelineRegionID) -> Binding<Double> {
        cameraBinding(id: id, keyPath: \.margin, default: defaultFacecamSettings(enabled: true).margin)
    }

    private func cameraAnchorBinding(id: TimelineRegionID) -> Binding<String> {
        cameraBinding(id: id, keyPath: \.anchor, default: FacecamAnchor.bottomRight.rawValue)
    }

    private func cameraBinding<Value: Equatable>(
        id: TimelineRegionID,
        keyPath: WritableKeyPath<FacecamSettings, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                edits.cameraClips.first(where: { $0.id == id })?.settings[keyPath: keyPath] ?? defaultValue
            },
            set: { value in
                guard var settings = edits.cameraClips.first(where: { $0.id == id })?.settings else { return }
                guard settings[keyPath: keyPath] != value else { return }
                settings[keyPath: keyPath] = value
                edits.updateCameraClipSettings(id: id, settings: settings)
            }
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.fg)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.overlay, in: Rectangle())
        .overlay {
            Rectangle()
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }
}

private struct TimelineSelectionActionButton: View {
    var title: String
    var symbolName: String
    var isDestructive = false
    var isEnabled = true
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.btnHeightSm)
            .foregroundStyle(isDestructive ? Color.red.opacity(isEnabled ? 0.95 : 0.36) : (isHovering ? Color.white : Theme.fgMuted))
            .background(
                isDestructive ? Color.red.opacity(isHovering ? 0.18 : 0.10) : (isHovering ? Color.white.opacity(0.08) : Theme.overlay),
                in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(isDestructive ? Color.red.opacity(0.30) : (isHovering ? Theme.borderStrong : Theme.borderSubtle), lineWidth: 1)
            }
        }
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct TimelineClipSpeedPicker: View {
    @Binding var speed: Double

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TimelineClipSpeed.values, id: \.self) { value in
                let isSelected = TimelineClipSpeed.normalized(speed) == value
                StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                    speed = value
                } label: {
                    Text(TimelineClipSpeed.label(value))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .foregroundStyle(isSelected ? Theme.timelineClipForeground : Color.secondary)
                        .background(isSelected ? Theme.timelineHandle.opacity(0.92) : Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                .stroke(isSelected ? Theme.timelineClipBorder : Theme.overlay, lineWidth: isSelected ? 1.5 : 1)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                Spacer()
                Text(TimelineZoomDepth.label(depth))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }

            HStack(spacing: 4) {
                ForEach(TimelineZoomDepth.values, id: \.self) { value in
                    let isSelected = abs(depth - value) < 0.001
                    StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                        if !isSelected {
                            depth = value
                        }
                    } label: {
                        Text(TimelineZoomDepth.label(value))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundStyle(isSelected ? Color.white : Theme.fgMuted)
                            .background(
                                isSelected ? Theme.accent : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                    .stroke(isSelected ? Theme.accent.opacity(0.80) : Theme.borderSubtle, lineWidth: 1)
                            }
                            .shadow(color: isSelected ? Theme.accent.opacity(0.30) : Color.clear, radius: 4, y: 1)
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

private struct TimelineZoomStylePicker: View {
    @Binding var preset: TimelineZoomAnimationPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Style")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                Spacer()
                Text(preset.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            HStack(spacing: 4) {
                ForEach(TimelineZoomAnimationPreset.allCases) { value in
                    let isSelected = preset == value
                    StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                        if !isSelected {
                            preset = value
                        }
                    } label: {
                        Text(value.shortTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundStyle(isSelected ? Color.white : Theme.fgMuted)
                            .background(
                                isSelected ? Theme.accent : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                    .stroke(isSelected ? Theme.accent.opacity(0.80) : Theme.borderSubtle, lineWidth: 1)
                            }
                            .shadow(color: isSelected ? Theme.accent.opacity(0.30) : Color.clear, radius: 4, y: 1)
                    }
                    .help("Set zoom style to \(value.title)")
                    .accessibilityLabel("Set zoom style to \(value.title)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
