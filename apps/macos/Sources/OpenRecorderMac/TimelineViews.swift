import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum TimelineMetrics {
    static let panelPadding: CGFloat = 12
    static let trackTopPadding: CGFloat = 8
    static let toolbarControlHeight: CGFloat = 34
    static let rulerHeight: CGFloat = 24
    static let clipHeight: CGFloat = 73.5
    static let layerHeight: CGFloat = 59.5
    static let regionItemHeight: CGFloat = 42
    static let playheadWidth: CGFloat = 1.5
    static let compactPanelHeight: CGFloat = toolbarControlHeight
        + panelPadding * 2
        + 1
        + trackTopPadding
        + rulerHeight
        + clipHeight
        + layerHeight
}

struct TimelinePanel: View {
    var videoURL: URL?
    var playback: VideoPlaybackController
    var edits: TimelineEditDriver
    @State private var timelineViewport = TimelineViewport(duration: 0)
    @State private var isDraggingTimelineZoom = false

    var body: some View {
        VStack(spacing: 0) {
            timelineToolbar

            Rectangle().fill(Theme.border).frame(height: 1)

            ZStack(alignment: .top) {
                Color.clear
                    .rectangularHitTarget()
                    .onTapGesture {
                        edits.clearSelection()
                    }

                TimelineTrackContent(videoURL: videoURL, playback: playback, edits: edits, viewport: $timelineViewport)
                    .padding(.horizontal, TimelineMetrics.panelPadding)
                    .padding(.top, TimelineMetrics.trackTopPadding)
            }
        }
        .studioEditorPaneChrome()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in
            if press.key == .delete || press.key == .deleteForward {
                edits.deleteSelection()
                return .handled
            }

            switch press.characters.lowercased() {
            case "z": edits.add(.zoom, at: playback.currentTime, duration: playback.duration); return .handled
            case "s": edits.cycleClipSpeed(at: playback.currentTime, duration: playback.duration); return .handled
            case "t": edits.addClipSplit(at: playback.currentTime, duration: playback.duration); return .handled
            default: return .ignored
            }
        }
        .onAppear {
            syncTimelineViewportDuration(playback.duration)
        }
        .onChange(of: playback.duration) { _, newDuration in
            syncTimelineViewportDuration(newDuration)
        }
        .onChange(of: playback.currentTime) { _, newTime in
            updateTimelineViewport(for: newTime)
        }
        .onChange(of: playback.isPlaying) { _, isPlaying in
            guard isPlaying else { return }
            timelineViewport = timelineViewport.following(time: playback.currentTime)
        }
    }

    private var timelineToolbar: some View {
        ZStack {
            HStack(spacing: 8) {
                TimelineTimeDisplay(currentTime: playback.currentTime, duration: playback.duration)

                Spacer()

                TimelineEditToolButton(
                    symbolName: "scissors",
                    title: "Split at playhead",
                    isEnabled: playback.player != nil && playback.duration > 0
                ) {
                    edits.addClipSplit(at: playback.currentTime, duration: playback.duration)
                }

                Rectangle()
                    .fill(Theme.borderStrong.opacity(0.46))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 3)

                TimelinePreviewSpeedButton(playback: playback)

                TimelineZoomSlider(
                    viewport: $timelineViewport,
                    duration: playback.duration,
                    currentTime: playback.currentTime,
                    isDragging: $isDraggingTimelineZoom
                )
            }

            TimelineTransportControls(playback: playback)
        }
        .padding(TimelineMetrics.panelPadding)
        .zIndex(1)
    }

    private func syncTimelineViewportDuration(_ duration: Double) {
        timelineViewport = TimelineViewport.reconciled(
            duration: duration,
            previous: timelineViewport,
            currentTime: playback.currentTime
        )
    }

    private func updateTimelineViewport(for currentTime: Double) {
        if playback.isPlaying {
            timelineViewport = timelineViewport.following(time: currentTime)
        } else if !timelineViewport.contains(currentTime) {
            timelineViewport = timelineViewport.keepingVisible(time: currentTime)
        }
    }
}

struct TimelineTrackContent: View {
    var videoURL: URL?
    var playback: VideoPlaybackController
    var edits: TimelineEditDriver
    @Binding var viewport: TimelineViewport
    @State private var timelineSize = CGSize.zero

    var body: some View {
        VStack(spacing: 0) {
            TimelineRuler(viewport: viewport)
                .rectangularHitTarget()
                .onTapGesture {
                    edits.clearSelection()
                }
            TimelineClipRow(videoURL: videoURL, duration: playback.duration, viewport: viewport, splitTimes: edits.clipSplitTimes, clipSpeeds: edits.clipSpeeds, selectedClipIndex: edits.selectedClipIndex, seek: playback.seek(to:), edits: edits)
            TimelineLayerRow(kind: .zoom, duration: playback.duration, viewport: viewport, regions: edits.zoomRegions.map(TimelineRegionRenderData.zoom), selectedID: edits.selectedKind == .zoom ? edits.selectedID : nil, edits: edits)
        }
        .overlay(alignment: .topLeading) { TimelinePlayhead(viewport: viewport, currentTime: playback.currentTime) }
        .readSize { timelineSize = $0 }
        .rectangularHitTarget()
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                hoverSeek(at: location.x)
            case .ended:
                break
            }
        }
    }

    private func hoverSeek(at x: CGFloat) {
        guard videoURL != nil, !playback.isPlaying else { return }
        guard let time = TimelineSeekMapper.time(forX: x, viewport: viewport, width: timelineSize.width) else { return }
        playback.seek(to: time)
        if !viewport.contains(time) {
            viewport = viewport.keepingVisible(time: time)
        }
    }
}


private struct TimelineTransportControls: View {
    var playback: VideoPlaybackController

    var body: some View {
        HStack(spacing: 10) {
            TimelineToolbarIconButton(symbolName: "backward.end.fill", title: "Jump to start", isEnabled: isEnabled) {
                playback.seek(to: 0)
            }
            TimelineToolbarIconButton(symbolName: "gobackward.10", title: "Back 10 frames", isEnabled: isEnabled) {
                stepFrames(-10)
            }
            TimelinePlayPauseButton(playback: playback)
            TimelineToolbarIconButton(symbolName: "goforward.10", title: "Forward 10 frames", isEnabled: isEnabled) {
                stepFrames(10)
            }
            TimelineToolbarIconButton(symbolName: "forward.end.fill", title: "Jump to end", isEnabled: isEnabled) {
                playback.seek(to: playback.duration)
            }
        }
    }

    private var isEnabled: Bool {
        playback.player != nil
    }

    private func stepFrames(_ frameCount: Int) {
        let frameDuration = 1.0 / 30.0
        let target = playback.currentTime + Double(frameCount) * frameDuration
        playback.seek(to: target)
    }
}

private struct TimelinePlayPauseButton: View {
    var playback: VideoPlaybackController
    @State private var isHovering = false

    var body: some View {
        let title = playback.isPlaying ? "Pause" : "Play"
        StudioButton(hitTarget: .rounded(10)) {
            playback.togglePlayback()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .offset(x: playback.isPlaying ? 0 : 1)
                .background {
                    Circle()
                        .fill(playback.isPlaying ? Theme.accent.opacity(isHovering ? 0.95 : 0.86) : Color.white.opacity(isHovering ? 0.14 : 0.09))
                }
                .overlay {
                    Circle()
                        .stroke(playback.isPlaying ? Theme.accent.opacity(0.48) : Color.white.opacity(isHovering ? 0.24 : 0.12), lineWidth: 1)
                }
                .shadow(color: Theme.scrim, radius: 8, y: 3)
        }
        .disabled(playback.player == nil)
        .opacity(playback.player == nil ? 0.42 : 1)
        .accessibilityLabel(title)
        .overlay(alignment: .top) {
            TimelineToolbarTooltip(title: title, isVisible: isHovering && playback.player != nil)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct TimelineToolbarIconButton: View {
    var symbolName: String
    var title: String
    var isEnabled = true
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        StudioButton(hitTarget: .rounded(10), action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.90 : 0.35))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(isHovering && isEnabled ? 0.10 : 0.001), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .overlay(alignment: .top) {
            TimelineToolbarTooltip(title: title, isVisible: isHovering && isEnabled)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct TimelineToolbarTooltip: View {
    var title: String
    var isVisible: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.fg.opacity(0.94))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Theme.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.borderStrong.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 10, y: 5)
            .opacity(isVisible ? 1 : 0)
            .offset(y: -34)
            .allowsHitTesting(false)
            .animation(.snappy(duration: 0.14), value: isVisible)
            .zIndex(20)
    }
}

private struct TimelineEditToolButton: View {
    var symbolName: String
    var title: String
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        TimelineToolbarIconButton(symbolName: symbolName, title: title, isEnabled: isEnabled, action: action)
    }
}

private struct TimelineTimeDisplay: View {
    var currentTime: Double
    var duration: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(formatPlaybackTime(currentTime))
                .foregroundStyle(Theme.fg.opacity(0.90))
            Text("/")
                .foregroundStyle(Theme.fgSubtle)
            Text(formatPlaybackTime(duration))
                .foregroundStyle(Theme.fgMuted)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Theme.overlay.opacity(0.86), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
        .accessibilityLabel("Playback time \(formatPlaybackTime(currentTime)) of \(formatPlaybackTime(duration))")
    }
}

private struct TimelinePreviewSpeedButton: View {
    var playback: VideoPlaybackController
    @State private var isHovering = false

    var body: some View {
        StudioButton(hitTarget: .rounded(7), help: "Preview playback speed") {
            playback.cyclePreviewPlaybackSpeed()
        } label: {
            Text(playback.previewPlaybackSpeedLabel())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.92 : 0.48))
                .frame(width: 42, height: 28)
                .background(Color.white.opacity(isHovering && isEnabled ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(isHovering && isEnabled ? 0.20 : 0.10), lineWidth: 1)
                }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("Preview playback speed \(playback.previewPlaybackSpeedLabel())")
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var isEnabled: Bool {
        playback.player != nil
    }
}

private struct TimelineZoomSlider: View {
    @Binding var viewport: TimelineViewport
    var duration: Double
    var currentTime: Double
    @Binding var isDragging: Bool

    var body: some View {
        ElasticSlider(
            value: sliderValue,
            range: 0...1,
            step: 0.01,
            onEditingChanged: { editing in
                withAnimation(.easeOut(duration: 0.12)) {
                    isDragging = editing
                }
            },
            trackHeight: 7,
            hitHeight: 28,
            fillColor: Color.primary.opacity(0.92),
            dragFillColor: Color(red: 0.48, green: 0.48, blue: 0.50),
            setsValueFromPointerLocation: true
        )
        .frame(width: 132)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel("Timeline zoom")
        .help("Timeline zoom")
        .overlay(alignment: .top) {
            if isDragging, isEnabled {
                Text(visibleDurationText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                    .offset(y: 27)
                    .allowsHitTesting(false)
            }
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: {
                TimelineViewport.sliderValue(forVisibleDuration: viewport.visibleDuration, duration: duration)
            },
            set: { value in
                let visibleDuration = TimelineViewport.visibleDuration(forSliderValue: value, duration: duration)
                viewport = TimelineViewport(
                    duration: duration,
                    visibleStart: viewport.visibleStart,
                    visibleDuration: viewport.visibleDuration
                )
                .withVisibleDuration(visibleDuration, centeredOn: currentTime)
            }
        )
    }

    private var isEnabled: Bool {
        TimelineViewport.isZoomEnabled(duration: duration)
    }

    private var visibleDurationText: String {
        "\(Int(max(0, viewport.visibleDuration).rounded()))s visible"
    }
}

struct TimelineViewport: Equatable {
    static let minimumVisibleDuration = 2.0

    var duration: Double
    var visibleStart: Double
    var visibleDuration: Double

    var visibleEnd: Double { min(duration, visibleStart + visibleDuration) }
    var isZoomEnabled: Bool { Self.isZoomEnabled(duration: duration) }
    var isFullDuration: Bool {
        duration <= 0 || abs(visibleDuration - duration) < 0.001
    }

    init(duration: Double, visibleStart: Double = 0, visibleDuration: Double? = nil) {
        let safeDuration = Self.safeDuration(duration)
        self.duration = safeDuration

        let requestedVisibleDuration = visibleDuration ?? safeDuration
        self.visibleDuration = Self.clampedVisibleDuration(requestedVisibleDuration, duration: safeDuration)
        self.visibleStart = Self.clampedStart(visibleStart, duration: safeDuration, visibleDuration: self.visibleDuration)
    }

    static func full(duration: Double) -> TimelineViewport {
        TimelineViewport(duration: duration)
    }

    static func isZoomEnabled(duration: Double) -> Bool {
        safeDuration(duration) > minimumVisibleDuration
    }

    static func reconciled(duration newDuration: Double, previous: TimelineViewport?, currentTime: Double) -> TimelineViewport {
        let safeDuration = safeDuration(newDuration)
        guard safeDuration > 0 else {
            return TimelineViewport(duration: 0)
        }

        guard isZoomEnabled(duration: safeDuration), let previous, !previous.isFullDuration else {
            return TimelineViewport.full(duration: safeDuration)
        }

        let visibleDuration = clampedVisibleDuration(previous.visibleDuration, duration: safeDuration)
        return TimelineViewport(
            duration: safeDuration,
            visibleStart: previous.visibleStart,
            visibleDuration: visibleDuration
        )
        .keepingVisible(time: currentTime)
    }

    func withVisibleDuration(_ requestedVisibleDuration: Double, centeredOn time: Double) -> TimelineViewport {
        guard isZoomEnabled else {
            return .full(duration: duration)
        }

        let nextVisibleDuration = Self.clampedVisibleDuration(requestedVisibleDuration, duration: duration)
        let anchor = Self.clamp(time.isFinite ? time : visibleStart + visibleDuration / 2, lower: 0, upper: duration)
        return TimelineViewport(
            duration: duration,
            visibleStart: anchor - nextVisibleDuration / 2,
            visibleDuration: nextVisibleDuration
        )
    }

    func following(time: Double) -> TimelineViewport {
        keepingVisible(time: time)
    }

    func keepingVisible(time: Double) -> TimelineViewport {
        guard isZoomEnabled, !isFullDuration, time.isFinite else {
            return self
        }

        if time < visibleStart {
            return TimelineViewport(duration: duration, visibleStart: time, visibleDuration: visibleDuration)
        }
        if time > visibleEnd {
            return TimelineViewport(duration: duration, visibleStart: time - visibleDuration, visibleDuration: visibleDuration)
        }

        return self
    }

    func contains(_ time: Double) -> Bool {
        time.isFinite && time >= visibleStart - 0.001 && time <= visibleEnd + 0.001
    }

    func intersects(_ span: TimelineSpan) -> Bool {
        span.end > visibleStart + 0.001 && span.start < visibleEnd - 0.001
    }

    func time(forX x: CGFloat, width: CGFloat) -> Double? {
        guard visibleDuration > 0, width.isFinite, width > 0, x.isFinite else { return nil }
        let clampedX = min(max(x, 0), width)
        let time = visibleStart + Double(clampedX / width) * visibleDuration
        return Self.clamp(time, lower: 0, upper: duration)
    }

    func x(for time: Double, width: CGFloat, clamped: Bool = false) -> CGFloat? {
        guard visibleDuration > 0, width.isFinite, width > 0, time.isFinite else { return nil }
        let rawFraction = (time - visibleStart) / visibleDuration
        let fraction = clamped ? Self.clamp(rawFraction, lower: 0, upper: 1) : rawFraction
        return width * CGFloat(fraction)
    }

    static func visibleDuration(forSliderValue sliderValue: Double, duration: Double) -> Double {
        let safeDuration = safeDuration(duration)
        guard isZoomEnabled(duration: safeDuration) else { return safeDuration }
        let progress = clamp(sliderValue, lower: 0, upper: 1)
        return safeDuration - progress * (safeDuration - minimumVisibleDuration)
    }

    static func sliderValue(forVisibleDuration visibleDuration: Double, duration: Double) -> Double {
        let safeDuration = safeDuration(duration)
        guard isZoomEnabled(duration: safeDuration), safeDuration > minimumVisibleDuration else { return 0 }
        let safeVisibleDuration = clampedVisibleDuration(visibleDuration, duration: safeDuration)
        return clamp((safeDuration - safeVisibleDuration) / (safeDuration - minimumVisibleDuration), lower: 0, upper: 1)
    }

    private static func safeDuration(_ duration: Double) -> Double {
        duration.isFinite && duration > 0 ? duration : 0
    }

    private static func clampedVisibleDuration(_ visibleDuration: Double, duration: Double) -> Double {
        let safeDuration = safeDuration(duration)
        guard safeDuration > minimumVisibleDuration else {
            return safeDuration
        }

        let requested = visibleDuration.isFinite && visibleDuration > 0 ? visibleDuration : safeDuration
        return clamp(requested, lower: minimumVisibleDuration, upper: safeDuration)
    }

    private static func clampedStart(_ start: Double, duration: Double, visibleDuration: Double) -> Double {
        let safeStart = start.isFinite ? start : 0
        return clamp(safeStart, lower: 0, upper: max(0, duration - visibleDuration))
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

struct TimelineRuler: View {
    var viewport: TimelineViewport

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if shouldShowHalfSecondTicks(width: proxy.size.width) {
                    ForEach(TimelineRulerTickBuilder.halfSecondTicks(visibleStart: viewport.visibleStart, visibleDuration: displayDuration, totalDuration: viewport.duration)) { tick in
                        let x = tickPosition(for: tick.time, width: proxy.size.width)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 1, height: 3)
                            .position(x: x, y: 3)
                    }
                }

                ForEach(TimelineRulerTickBuilder.ticks(visibleStart: viewport.visibleStart, visibleDuration: displayDuration, totalDuration: viewport.duration)) { tick in
                    let x = tickPosition(for: tick.time, width: proxy.size.width)
                    Rectangle().fill(Theme.border).frame(width: 1, height: 6).position(x: x, y: 4)
                    if !tick.label.isEmpty {
                        Text(tick.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary.opacity(0.72))
                            .frame(width: 44)
                            .position(x: labelPosition(for: x, width: proxy.size.width), y: 11)
                    }
                }
            }
        }
        .frame(height: TimelineMetrics.rulerHeight)
    }

    private func tickPosition(for time: Double, width: CGFloat) -> CGFloat { viewport.x(for: time, width: width, clamped: true) ?? 0 }
    private func labelPosition(for x: CGFloat, width: CGFloat) -> CGFloat { min(max(x, 22), max(22, width - 22)) }
    private func shouldShowHalfSecondTicks(width: CGFloat) -> Bool {
        guard width.isFinite, width > 0, displayDuration.isFinite, displayDuration > 0 else { return false }
        return width / CGFloat(displayDuration * 2) >= 4
    }
    private var displayDuration: Double { viewport.visibleDuration > 0 ? viewport.visibleDuration : 6 }
}

struct TimelinePlayhead: View {
    var viewport: TimelineViewport
    var currentTime: Double

    var body: some View {
        GeometryReader { proxy in
            let x = viewport.x(for: currentTime, width: proxy.size.width, clamped: true) ?? 0
            Rectangle()
                .fill(Color(red: 0.40, green: 0.31, blue: 1.0).opacity(0.98))
                .frame(width: TimelineMetrics.playheadWidth, height: proxy.size.height)
                .offset(x: x - TimelineMetrics.playheadWidth / 2)
        }
        .allowsHitTesting(false)
    }
}

enum TimelineSeekMapper {
    static func time(forX x: CGFloat, duration: Double, width: CGFloat) -> Double? {
        guard duration.isFinite, duration > 0, width.isFinite, width > 0, x.isFinite else { return nil }
        return duration * Double(min(max(x / width, 0), 1))
    }

    static func time(forX x: CGFloat, viewport: TimelineViewport, width: CGFloat) -> Double? {
        viewport.time(forX: x, width: width)
    }

    static func x(forTime time: Double, viewport: TimelineViewport, width: CGFloat, clamped: Bool = false) -> CGFloat? {
        viewport.x(for: time, width: width, clamped: clamped)
    }
}

struct TimelineClipRow: View {
    var videoURL: URL?
    var duration: Double
    var viewport: TimelineViewport
    var splitTimes: [Double]
    var clipSpeeds: [Int: Double]
    var selectedClipIndex: Int?
    var seek: (Double) -> Void
    var edits: TimelineEditDriver
    @State private var waveformSamples: [Double]?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.095, green: 0.095, blue: 0.11))
                if videoURL != nil {
                    clipSegments(width: proxy.size.width)
                } else {
                    Text("No clip")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .rectangularHitTarget()
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(to: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { value in
                        selectClip(at: value.location.x, width: proxy.size.width)
                    }
            )
        }
        .frame(height: TimelineMetrics.clipHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .task(id: videoURL) { await loadWaveform() }
    }

    private func clipSegments(width: CGFloat) -> some View {
        let segments = TimelineClipSegment.segments(duration: duration, splitTimes: splitTimes, clipSpeeds: clipSpeeds)
            .filter { viewport.intersects($0.span) }
        return ZStack(alignment: .leading) {
            ForEach(segments) { segment in
                let startX = x(for: segment.start, width: width)
                let endX = x(for: segment.end, width: width)
                let segmentWidth = max(1, endX - startX - (segments.count > 1 ? 3 : 0))
                clipBody(segment: segment, width: segmentWidth, isSelected: selectedClipIndex == segment.index)
                    .frame(width: segmentWidth, height: TimelineMetrics.clipHeight)
                    .position(x: startX + (endX - startX) / 2, y: TimelineMetrics.clipHeight / 2)
            }
        }
    }

    private func clipBody(segment: TimelineClipSegment, width: CGFloat, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.timelineClip.opacity(isSelected ? 0.95 : 1))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? Theme.timelineHandle.opacity(0.95) : Theme.timelineClipBorder, lineWidth: isSelected ? 2 : 1) }
            .overlay(alignment: .bottom) {
                if let waveformSamples, !waveformSamples.isEmpty {
                    TimelineWaveformPreview(samples: waveformSamples)
                        .frame(height: 24)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .center) {
                if width > 82 {
                    VStack(spacing: 2) {
                        Label("Clip \(segment.index + 1)", systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(formatClipDuration(segment.end - segment.start)) @ \(TimelineClipSpeed.label(segment.speed))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.timelineClipForeground)
                    .shadow(color: Theme.borderStrong, radius: 3, y: 1)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) { Text(formatPlaybackTime(segment.start)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Theme.timelineClipForeground.opacity(0.52)).padding(.leading, 9).padding(.bottom, 4) }
            .overlay(alignment: .bottomTrailing) { Text(formatPlaybackTime(segment.end)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Theme.timelineClipForeground.opacity(0.52)).padding(.trailing, 9).padding(.bottom, 4) }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
    }

    private func seek(to x: CGFloat, width: CGFloat) {
        guard let time = TimelineSeekMapper.time(forX: x, viewport: viewport, width: width) else { return }
        seek(time)
    }

    private func selectClip(at x: CGFloat, width: CGFloat) {
        guard videoURL != nil, duration.isFinite, duration > 0, width > 0 else {
            edits.clearSelection()
            return
        }

        guard let time = TimelineSeekMapper.time(forX: x, viewport: viewport, width: width) else {
            edits.clearSelection()
            return
        }
        let segments = TimelineClipSegment.segments(duration: duration, splitTimes: splitTimes, clipSpeeds: clipSpeeds)
        guard let segment = segments.first(where: { time >= $0.start && (time < $0.end || $0.index == segments.last?.index) }) else {
            edits.clearSelection()
            return
        }

        edits.selectClip(index: segment.index)
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        viewport.x(for: time, width: width, clamped: true) ?? 0
    }

    private func loadWaveform() async {
        guard let videoURL else { waveformSamples = nil; return }
        waveformSamples = nil
        let waveform = await TimelineAudioWaveformLoader.loadWaveform(from: videoURL)
        guard !Task.isCancelled else { return }
        waveformSamples = waveform.isAvailable ? waveform.samples : nil
    }
}

struct TimelineResizeHandle: View {
    var style: TimelineRegionKind = .zoom

    var body: some View {
        if style == .zoom {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: 6, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 1)
                }
                .shadow(color: Color.white.opacity(0.34), radius: 6)
                .shadow(color: Color.black.opacity(0.34), radius: 8, y: 3)
        } else {
            Circle()
                .fill(Theme.timelineHandle)
                .frame(width: 20, height: 20)
                .overlay { Image(systemName: "arrow.left.and.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.black.opacity(0.82)) }
                .overlay { Circle().stroke(Theme.scrim, lineWidth: 1) }
                .shadow(color: Color.black.opacity(0.24), radius: 6, y: 3)
        }
    }
}

struct TimelineWaveformPreview: View {
    var samples: [Double]

    var body: some View {
        Canvas { context, size in
            let levels = TimelineWaveformBarRenderer.resampledLevels(from: samples, width: size.width)
            guard !levels.isEmpty, size.width > 0, size.height > 0 else { return }

            let spacing: CGFloat = size.width < 140 ? 1.6 : 2
            let barWidth = max(1.5, (size.width - spacing * CGFloat(levels.count - 1)) / CGFloat(levels.count))
            let maxBarHeight = max(1, size.height - 1)

            for (index, sample) in levels.enumerated() {
                let level = CGFloat(sqrt(max(0, min(sample, 1))))
                let barHeight = max(3, level * maxBarHeight)
                let x = CGFloat(index) * (barWidth + spacing)
                let y = size.height - barHeight
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let barPath = RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous).path(in: rect)
                let sheenRect = CGRect(x: x, y: y, width: max(1, barWidth * 0.38), height: barHeight)
                let sheenPath = RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous).path(in: sheenRect)

                context.fill(
                    barPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.86),
                            Theme.timelineHandle.opacity(0.70),
                            Theme.timelineClipBorder.opacity(0.50)
                        ]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
                context.fill(sheenPath, with: .color(Color.white.opacity(0.16)))
            }
        }
    }
}

enum TimelineWaveformBarRenderer {
    static func resampledLevels(from samples: [Double], width: CGFloat) -> [Double] {
        guard width > 0, !samples.isEmpty else { return [] }

        let targetCount = max(1, min(samples.count, Int(width / 4.5)))
        guard targetCount < samples.count else {
            return samples.map { min(max($0, 0), 1) }
        }

        return (0..<targetCount).map { bucket in
            let start = Int((Double(bucket) / Double(targetCount)) * Double(samples.count))
            let end = max(start + 1, Int((Double(bucket + 1) / Double(targetCount)) * Double(samples.count)))
            return samples[start..<min(end, samples.count)].reduce(0) { partial, sample in
                max(partial, min(max(sample, 0), 1))
            }
        }
    }
}

func formatClipDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0s" }
    if seconds < 60 { return "\(max(1, Int(seconds.rounded())))s" }
    return formatPlaybackTime(seconds)
}

struct TimelineRegionRenderData: Identifiable {
    var id: TimelineRegionID
    var span: TimelineSpan
    var label: String
    var mode: TimelineZoomMode?

    var showsAutoBadge: Bool {
        mode == .auto
    }

    static func zoom(_ zoom: TimelineZoomRegion) -> TimelineRegionRenderData {
        TimelineRegionRenderData(
            id: zoom.id,
            span: zoom.span,
            label: TimelineZoomDepth.label(zoom.depth),
            mode: zoom.mode
        )
    }
}

struct TimelineLayerRow: View {
    var kind: TimelineRegionKind
    var duration: Double
    var viewport: TimelineViewport
    var regions: [TimelineRegionRenderData]
    var selectedID: TimelineRegionID?
    var edits: TimelineEditDriver

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.095, green: 0.095, blue: 0.11))
                    .rectangularHitTarget()
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleBackgroundTap(at: value.location, width: proxy.size.width)
                            }
                    )
                if regions.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
                ForEach(regions.filter { viewport.intersects($0.span) }) { region in
                    TimelineRegionItem(kind: kind, region: region, duration: duration, viewport: viewport, width: proxy.size.width, isSelected: region.id == selectedID, edits: edits)
                }
            }
            .rectangularHitTarget()
            .clipped()
        }
        .frame(height: TimelineMetrics.layerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var emptyMessage: String {
        switch kind {
        case .zoom:
            "Click or press Z to add zoom"
        case .annotation:
            "Annotations are currently unavailable"
        case .trim:
            "Trim sections are no longer available"
        }
    }

    private func handleBackgroundTap(at location: CGPoint, width: CGFloat) {
        guard kind == .zoom,
              duration.isFinite,
              duration > 0,
              let time = TimelineSeekMapper.time(forX: location.x, viewport: viewport, width: width) else {
            edits.clearSelection()
            return
        }

        edits.add(.zoom, at: time, duration: duration)
    }
}

struct TimelineRegionItem: View {
    var kind: TimelineRegionKind
    var region: TimelineRegionRenderData
    var duration: Double
    var viewport: TimelineViewport
    var width: CGFloat
    var isSelected: Bool
    var edits: TimelineEditDriver
    @State private var dragStartSpan: TimelineSpan?

    var body: some View {
        let startX = x(for: region.span.start)
        let itemWidth = max(1, x(for: region.span.end) - startX)
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(regionFill)
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(regionStroke, lineWidth: isSelected ? 1.5 : 1) }
            .overlay { regionLabel(width: itemWidth) }
            .overlay(alignment: .leading) {
                if showsLeadingHandle {
                    TimelineResizeHandle(style: kind).offset(x: kind == .zoom ? 0 : -9).gesture(resizeGesture(edge: .leading))
                }
            }
            .overlay(alignment: .trailing) {
                if showsTrailingHandle {
                    TimelineResizeHandle(style: kind).offset(x: kind == .zoom ? 0 : 9).gesture(resizeGesture(edge: .trailing))
                }
            }
            .frame(width: itemWidth, height: TimelineMetrics.regionItemHeight)
            .position(x: startX + itemWidth / 2, y: TimelineMetrics.layerHeight / 2)
            .onTapGesture(count: 2) { performPrimaryEdit() }
            .onTapGesture { edits.select(kind, id: region.id) }
            .gesture(moveGesture())
    }

    private var regionFill: some ShapeStyle {
        if kind == .zoom {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.38, blue: 1.00).opacity(isSelected ? 0.98 : 0.88),
                        Color(red: 0.42, green: 0.75, blue: 1.00).opacity(isSelected ? 0.94 : 0.80)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(kind.accent.opacity(isSelected ? 0.55 : 0.34))
    }

    private var regionStroke: Color {
        if kind == .zoom {
            return Color.white.opacity(isSelected ? 0.72 : 0.42)
        }

        return kind.accent.opacity(isSelected ? 0.95 : 0.65)
    }

    private func regionLabel(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(labelText(width: width))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(kind == .zoom ? Color.white.opacity(0.72) : .white)
                .lineLimit(1)

            if region.showsAutoBadge, width > 52 {
                Text("Auto")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.borderStrong, in: Capsule())
            }
        }
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 7)
        .frame(maxWidth: max(0, width - 8))
    }

    private func labelText(width: CGFloat) -> String {
        guard kind == .zoom else { return region.label }
        return width > 78 ? "Zoom \(region.label)" : region.label
    }

    private enum ResizeEdge { case leading, trailing }

    private var showsLeadingHandle: Bool {
        region.span.start >= viewport.visibleStart - 0.001
    }

    private var showsTrailingHandle: Bool {
        region.span.end <= viewport.visibleEnd + 0.001
    }

    private func moveGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartSpan == nil {
                    edits.beginUndoTransaction()
                    dragStartSpan = region.span
                    edits.select(kind, id: region.id)
                }
                let base = dragStartSpan ?? region.span
                let delta = time(forDeltaX: value.translation.width)
                let length = base.duration
                let start = min(max(base.start + delta, 0), max(0, duration - length))
                edits.updateSpan(kind: kind, id: region.id, span: TimelineSpan(start: start, end: start + length), duration: duration)
            }
            .onEnded { _ in
                edits.endUndoTransaction()
                dragStartSpan = nil
            }
    }

    private func resizeGesture(edge: ResizeEdge) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartSpan == nil {
                    edits.beginUndoTransaction()
                    dragStartSpan = region.span
                    edits.select(kind, id: region.id)
                }
                let base = dragStartSpan ?? region.span
                let delta = time(forDeltaX: value.translation.width)
                switch edge {
                case .leading:
                    edits.updateSpan(kind: kind, id: region.id, span: TimelineSpan(start: base.start + delta, end: base.end), duration: duration)
                case .trailing:
                    edits.updateSpan(kind: kind, id: region.id, span: TimelineSpan(start: base.start, end: base.end + delta), duration: duration)
                }
            }
            .onEnded { _ in
                edits.endUndoTransaction()
                dragStartSpan = nil
            }
    }

    private func performPrimaryEdit() {
        switch kind {
        case .zoom: edits.deepenZoom(id: region.id)
        case .trim, .annotation: break
        }
    }

    private func x(for time: Double) -> CGFloat {
        viewport.x(for: time, width: width, clamped: true) ?? 0
    }

    private func time(forDeltaX deltaX: CGFloat) -> Double {
        guard width > 0, viewport.visibleDuration.isFinite else { return 0 }
        return Double(deltaX / width) * viewport.visibleDuration
    }
}
