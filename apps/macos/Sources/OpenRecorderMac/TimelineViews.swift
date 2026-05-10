import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum TimelineMetrics {
    static let rulerHeight: CGFloat = 24
    static let clipHeight: CGFloat = 42
    static let layerHeight: CGFloat = 34
    static let playheadWidth: CGFloat = 1.5
}

struct TimelinePanel: View {
    var videoURL: URL?
    @ObservedObject var playback: VideoPlaybackController
    @ObservedObject var edits: TimelineEditController

    var body: some View {
        VStack(spacing: 0) {
            timelineToolbar

            Rectangle().fill(Color.studioBorder).frame(height: 1)

            ZStack(alignment: .top) {
                Color.clear
                    .rectangularHitTarget()
                    .onTapGesture {
                        edits.clearSelection()
                    }

                TimelineTrackContent(videoURL: videoURL, playback: playback, edits: edits)
                    .padding(12)
            }
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.studioBorder) }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 10)
        .focusable()
        .onKeyPress { press in
            if press.key == .delete || press.key == .deleteForward {
                edits.deleteSelection()
                return .handled
            }

            switch press.characters.lowercased() {
            case "z": edits.add(.zoom, at: playback.currentTime, duration: playback.duration); return .handled
            case "t": edits.addClipSplit(at: playback.currentTime, duration: playback.duration); return .handled
            case "s": edits.add(.speed, at: playback.currentTime, duration: playback.duration); return .handled
            default: return .ignored
            }
        }
    }

    private var timelineToolbar: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("16:9")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.studioBorder) }

                Spacer()

                if edits.snapshot.hasEdits {
                    Button("Clear") { edits.reset() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            TimelinePlaybackControl(playback: playback)
        }
        .padding(12)
    }
}

struct TimelineTrackContent: View {
    var videoURL: URL?
    @ObservedObject var playback: VideoPlaybackController
    @ObservedObject var edits: TimelineEditController

    var body: some View {
        VStack(spacing: 0) {
            TimelineRuler(duration: playback.duration)
                .rectangularHitTarget()
                .onTapGesture {
                    edits.clearSelection()
                }
            TimelineClipRow(videoURL: videoURL, duration: playback.duration, splitTimes: edits.clipSplitTimes, selectedClipIndex: edits.selectedClipIndex, seek: playback.seek(to:), edits: edits)
            TimelineLayerRow(kind: .zoom, duration: playback.duration, regions: edits.zoomRegions.map { TimelineRegionRenderData(id: $0.id, span: $0.span, label: "\(String(format: "%.1f", $0.depth))×") }, selectedID: edits.selectedKind == .zoom ? edits.selectedID : nil, edits: edits)
            TimelineLayerRow(kind: .trim, duration: playback.duration, regions: edits.trimRegions.map { TimelineRegionRenderData(id: $0.id, span: $0.span, label: "Cut") }, selectedID: edits.selectedKind == .trim ? edits.selectedID : nil, edits: edits)
            TimelineLayerRow(kind: .speed, duration: playback.duration, regions: edits.speedRegions.map { TimelineRegionRenderData(id: $0.id, span: $0.span, label: "\(String(format: "%.2g", $0.speed))×") }, selectedID: edits.selectedKind == .speed ? edits.selectedID : nil, edits: edits)
        }
        .overlay(alignment: .topLeading) { TimelinePlayhead(duration: playback.duration, currentTime: playback.currentTime) }
    }
}


private struct TimelinePlaybackControl: View {
    @ObservedObject var playback: VideoPlaybackController
    @State private var isHovering = false

    var body: some View {
        let title = playback.isPlaying ? "Pause" : "Play"

        StudioButton(hitTarget: .circle, help: title) {
            playback.togglePlayback()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .offset(x: playback.isPlaying ? 0 : 1)
                .background {
                    Circle()
                        .fill(playback.isPlaying ? Color.brand.opacity(isHovering ? 0.95 : 0.86) : Color.white.opacity(isHovering ? 0.14 : 0.09))
                }
                .overlay {
                    Circle()
                        .stroke(playback.isPlaying ? Color.brand.opacity(0.48) : Color.white.opacity(isHovering ? 0.24 : 0.12), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 3)
        }
        .disabled(playback.player == nil)
        .opacity(playback.player == nil ? 0.42 : 1)
        .accessibilityLabel(title)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct TimelineRuler: View {
    var duration: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(TimelineRulerTickBuilder.ticks(duration: displayDuration)) { tick in
                    let x = tickPosition(for: tick.time, width: proxy.size.width)
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 6).position(x: x, y: 4)
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

    private func tickPosition(for time: Double, width: CGFloat) -> CGFloat { width * CGFloat(min(max(time / displayDuration, 0), 1)) }
    private func labelPosition(for x: CGFloat, width: CGFloat) -> CGFloat { min(max(x, 22), max(22, width - 22)) }
    private var displayDuration: Double { duration.isFinite && duration > 0 ? duration : 6 }
}

struct TimelinePlayhead: View {
    var duration: Double
    var currentTime: Double

    var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * playheadFraction
            Rectangle()
                .fill(Color(red: 0.40, green: 0.31, blue: 1.0).opacity(0.98))
                .frame(width: TimelineMetrics.playheadWidth, height: proxy.size.height)
                .offset(x: x - TimelineMetrics.playheadWidth / 2)
        }
        .allowsHitTesting(false)
    }

    private var playheadFraction: CGFloat {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }
}

struct TimelineClipRow: View {
    var videoURL: URL?
    var duration: Double
    var splitTimes: [Double]
    var selectedClipIndex: Int?
    var seek: (Double) -> Void
    @ObservedObject var edits: TimelineEditController
    @State private var waveformSamples = TimelineAudioWaveformLoader.quietSamples()

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
        .overlay(alignment: .bottom) { Rectangle().fill(Color.studioBorder).frame(height: 1) }
        .task(id: videoURL) { await loadWaveform() }
    }

    private func clipSegments(width: CGFloat) -> some View {
        let segments = TimelineClipSegment.segments(duration: duration, splitTimes: splitTimes)
        return ZStack(alignment: .leading) {
            ForEach(segments) { segment in
                let startX = x(for: segment.start, width: width)
                let endX = x(for: segment.end, width: width)
                let segmentWidth = max(20, endX - startX - (segments.count > 1 ? 3 : 0))
                clipBody(segment: segment, width: segmentWidth, isSelected: selectedClipIndex == segment.index)
                    .frame(width: segmentWidth, height: TimelineMetrics.clipHeight)
                    .position(x: startX + (endX - startX) / 2, y: TimelineMetrics.clipHeight / 2)
            }
        }
    }

    private func clipBody(segment: TimelineClipSegment, width: CGFloat, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.timelineClip.opacity(isSelected ? 0.95 : 1))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? Color.timelineHandle.opacity(0.95) : Color.timelineClipBorder, lineWidth: isSelected ? 2 : 1) }
            .overlay(alignment: .bottom) { TimelineWaveformPreview(samples: waveformSamples).frame(height: 23).padding(.horizontal, 14).padding(.bottom, 4).allowsHitTesting(false) }
            .overlay(alignment: .center) {
                if width > 82 {
                    VStack(spacing: 2) {
                        Label("Clip \(segment.index + 1)", systemImage: "rectangle.on.rectangle")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(formatClipDuration(segment.end - segment.start)) @ 1x")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Color.white.opacity(0.86))
                    .shadow(color: Color.black.opacity(0.28), radius: 4, y: 2)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) { Text(formatPlaybackTime(segment.start)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Color.white.opacity(0.32)).padding(.leading, 9).padding(.bottom, 4) }
            .overlay(alignment: .bottomTrailing) { Text(formatPlaybackTime(segment.end)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Color.white.opacity(0.32)).padding(.trailing, 9).padding(.bottom, 4) }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
    }

    private func seek(to x: CGFloat, width: CGFloat) {
        guard duration.isFinite, duration > 0, width > 0 else { return }
        seek(duration * Double(min(max(x / width, 0), 1)))
    }

    private func selectClip(at x: CGFloat, width: CGFloat) {
        guard videoURL != nil, duration.isFinite, duration > 0, width > 0 else {
            edits.clearSelection()
            return
        }

        let time = duration * Double(min(max(x / width, 0), 1))
        let segments = TimelineClipSegment.segments(duration: duration, splitTimes: splitTimes)
        guard let segment = segments.first(where: { time >= $0.start && (time < $0.end || $0.index == segments.last?.index) }) else {
            edits.clearSelection()
            return
        }

        edits.selectClip(index: segment.index)
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        guard duration.isFinite, duration > 0 else { return 0 }
        return width * CGFloat(min(max(time / duration, 0), 1))
    }

    private func loadWaveform() async {
        guard let videoURL else { waveformSamples = TimelineAudioWaveformLoader.quietSamples(); return }
        waveformSamples = TimelineAudioWaveformLoader.quietSamples()
        let samples = await TimelineAudioWaveformLoader.loadSamples(from: videoURL)
        guard !Task.isCancelled else { return }
        waveformSamples = samples
    }
}

struct TimelineTrimHandle: View {
    var body: some View {
        Circle()
            .fill(Color.timelineHandle)
            .frame(width: 20, height: 20)
            .overlay { Image(systemName: "arrow.left.and.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.black.opacity(0.82)) }
            .overlay { Circle().stroke(Color.black.opacity(0.20), lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.24), radius: 6, y: 3)
    }
}

struct TimelineWaveformPreview: View {
    var samples: [Double]

    var body: some View {
        Canvas { context, size in
            let levels = samples.isEmpty ? TimelineAudioWaveformLoader.quietSamples() : samples
            guard !levels.isEmpty, size.width > 0, size.height > 0 else { return }
            let step = size.width / CGFloat(max(levels.count - 1, 1))
            var fillPath = Path(); var strokePath = Path()
            fillPath.move(to: CGPoint(x: 0, y: size.height))
            for (index, sample) in levels.enumerated() {
                let x = CGFloat(index) * step
                let boostedLevel = CGFloat(sqrt(max(0.0, min(sample, 1.0))))
                let height = max(2, boostedLevel * (size.height - 2))
                let point = CGPoint(x: x, y: size.height - height)
                if index == 0 { fillPath.addLine(to: point); strokePath.move(to: point) } else { fillPath.addLine(to: point); strokePath.addLine(to: point) }
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height)); fillPath.closeSubpath()
            context.fill(fillPath, with: .color(Color.white.opacity(0.18)))
            context.stroke(strokePath, with: .color(Color.white.opacity(0.24)), lineWidth: 1)
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
}

struct TimelineLayerRow: View {
    var kind: TimelineRegionKind
    var duration: Double
    var regions: [TimelineRegionRenderData]
    var selectedID: TimelineRegionID?
    @ObservedObject var edits: TimelineEditController

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.095, green: 0.095, blue: 0.11))
                    .rectangularHitTarget()
                    .onTapGesture {
                        edits.clearSelection()
                    }
                if regions.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
                ForEach(regions) { region in
                    TimelineRegionItem(kind: kind, region: region, duration: duration, width: proxy.size.width, isSelected: region.id == selectedID, edits: edits)
                }
            }
            .rectangularHitTarget()
        }
        .frame(height: TimelineMetrics.layerHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.studioBorder).frame(height: 1) }
    }

    private var emptyMessage: String {
        switch kind {
        case .zoom:
            "Press Z to add zoom"
        case .speed:
            "Press S to add speed"
        case .annotation:
            "Annotations are currently unavailable"
        case .trim:
            "Use the toolbar to add trim"
        }
    }
}

struct TimelineRegionItem: View {
    var kind: TimelineRegionKind
    var region: TimelineRegionRenderData
    var duration: Double
    var width: CGFloat
    var isSelected: Bool
    @ObservedObject var edits: TimelineEditController
    @State private var dragStartSpan: TimelineSpan?

    var body: some View {
        let startX = x(for: region.span.start)
        let itemWidth = max(18, x(for: region.span.end) - startX)
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(kind.accent.opacity(isSelected ? 0.55 : 0.34))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(kind.accent.opacity(isSelected ? 0.95 : 0.65), lineWidth: isSelected ? 2 : 1) }
            .overlay { Text(region.label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 8) }
            .overlay(alignment: .leading) { TimelineTrimHandle().offset(x: -9).gesture(resizeGesture(edge: .leading)) }
            .overlay(alignment: .trailing) { TimelineTrimHandle().offset(x: 9).gesture(resizeGesture(edge: .trailing)) }
            .frame(width: itemWidth, height: 24)
            .position(x: startX + itemWidth / 2, y: TimelineMetrics.layerHeight / 2)
            .onTapGesture(count: 2) { performPrimaryEdit() }
            .onTapGesture { edits.select(kind, id: region.id) }
            .gesture(moveGesture())
    }

    private enum ResizeEdge { case leading, trailing }

    private func moveGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartSpan == nil {
                    dragStartSpan = region.span
                    edits.select(kind, id: region.id)
                }
                let base = dragStartSpan ?? region.span
                let delta = time(forDeltaX: value.translation.width)
                let length = base.duration
                let start = min(max(base.start + delta, 0), max(0, duration - length))
                edits.updateSpan(kind: kind, id: region.id, span: TimelineSpan(start: start, end: start + length), duration: duration)
            }
            .onEnded { _ in dragStartSpan = nil }
    }

    private func resizeGesture(edge: ResizeEdge) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartSpan == nil {
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
            .onEnded { _ in dragStartSpan = nil }
    }

    private func performPrimaryEdit() {
        switch kind {
        case .zoom: edits.deepenZoom(id: region.id)
        case .speed: edits.cycleSpeed(id: region.id)
        case .trim, .annotation: break
        }
    }

    private func x(for time: Double) -> CGFloat {
        guard duration.isFinite, duration > 0 else { return 0 }
        return width * CGFloat(min(max(time / duration, 0), 1))
    }

    private func time(forDeltaX deltaX: CGFloat) -> Double {
        guard width > 0, duration.isFinite else { return 0 }
        return Double(deltaX / width) * duration
    }
}
