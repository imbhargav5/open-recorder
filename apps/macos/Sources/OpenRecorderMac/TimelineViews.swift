import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum TimelineMetrics {
    static let labelWidth: CGFloat = 96
    static let rulerHeight: CGFloat = 24
    static let clipHeight: CGFloat = 42
    static let layerHeight: CGFloat = 34
    static let playheadWidth: CGFloat = 1.5
}

struct TimelinePanel: View {
    var videoURL: URL?
    @ObservedObject var playback: VideoPlaybackController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TimelineTool(title: "Zoom", symbolName: "plus.magnifyingglass")
                TimelineTool(title: "Suggest", symbolName: "sparkles")
                TimelineTool(title: "Trim", symbolName: "scissors")
                TimelineTool(title: "Annotate", symbolName: "text.bubble")
                TimelineTool(title: "Speed", symbolName: "speedometer")
                Spacer()
                Text("16:9")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.studioBorder)
                    }
            }
            .padding(12)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            TimelineTrackContent(videoURL: videoURL, playback: playback)
                .padding(12)
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 10)
    }
}

struct TimelineTrackContent: View {
    var videoURL: URL?
    @ObservedObject var playback: VideoPlaybackController

    var body: some View {
        VStack(spacing: 0) {
            TimelineRuler(duration: playback.duration)
            TimelineClipRow(
                videoURL: videoURL,
                duration: playback.duration,
                seek: playback.seek(to:)
            )
            TimelineLayerRow(
                label: "Zoom",
                hint: "Press Z to add zoom",
                accent: Color.blue
            )
            TimelineLayerRow(
                label: "Trim",
                hint: "Press T to add trim",
                accent: Color.red
            )
            TimelineLayerRow(
                label: "Annotation",
                hint: "Press A to add annotation",
                accent: Color.purple
            )
            TimelineLayerRow(
                label: "Speed",
                hint: "Press S to add speed",
                accent: Color.orange
            )
            TimelineLayerRow(
                label: "Audio",
                hint: "No audio regions",
                accent: Color.green
            )
        }
        .overlay(alignment: .topLeading) {
            TimelinePlayhead(duration: playback.duration, currentTime: playback.currentTime)
        }
    }
}

struct TimelineTool: View {
    var title: String
    var symbolName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .frame(height: 30)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct TimelineRuler: View {
    var duration: Double

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: TimelineMetrics.labelWidth)
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(TimelineRulerTickBuilder.ticks(duration: displayDuration)) { tick in
                        let x = tickPosition(for: tick.time, width: proxy.size.width)

                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 1, height: 6)
                            .position(x: x, y: 4)

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
        }
        .frame(height: TimelineMetrics.rulerHeight)
    }

    private func tickPosition(for time: Double, width: CGFloat) -> CGFloat {
        let fraction = min(max(time / displayDuration, 0), 1)
        return width * CGFloat(fraction)
    }

    private func labelPosition(for x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x, 22), max(22, width - 22))
    }

    private var displayDuration: Double {
        duration.isFinite && duration > 0 ? duration : 6
    }
}

struct TimelinePlayhead: View {
    var duration: Double
    var currentTime: Double

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width - TimelineMetrics.labelWidth, 0)
            let x = TimelineMetrics.labelWidth + trackWidth * playheadFraction

            Rectangle()
                .fill(Color(red: 0.40, green: 0.31, blue: 1.0).opacity(0.98))
                .frame(width: TimelineMetrics.playheadWidth, height: proxy.size.height)
                .offset(x: x - TimelineMetrics.playheadWidth / 2)
        }
        .allowsHitTesting(false)
    }

    private var playheadFraction: CGFloat {
        guard duration.isFinite, duration > 0, currentTime.isFinite else {
            return 0
        }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }
}

struct TimelineClipRow: View {
    var videoURL: URL?
    var duration: Double
    var seek: (Double) -> Void
    @State private var waveformSamples = TimelineAudioWaveformLoader.quietSamples()

    var body: some View {
        HStack(spacing: 0) {
            Color.white.opacity(0.025)
                .frame(width: TimelineMetrics.labelWidth, height: TimelineMetrics.clipHeight)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.095, green: 0.095, blue: 0.11))

                    if videoURL != nil {
                        clipBody
                    } else {
                        Text("No clip")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.64))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .rectangularHitTarget()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            seek(to: value.location.x, width: proxy.size.width)
                        }
                )
            }
            .frame(height: TimelineMetrics.clipHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
        }
        .task(id: videoURL) {
            await loadWaveform()
        }
    }

    private var clipBody: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.timelineClip)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.timelineClipBorder, lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                TimelineWaveformPreview(samples: waveformSamples)
                    .frame(height: 23)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .center) {
                VStack(spacing: 2) {
                    Label("Clip", systemImage: "rectangle.on.rectangle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(formatClipDuration(duration)) @ 1x")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Color.white.opacity(0.86))
                .shadow(color: Color.black.opacity(0.28), radius: 4, y: 2)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                Text("0:00")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .padding(.leading, 9)
                    .padding(.bottom, 4)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(formatPlaybackTime(duration))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .padding(.trailing, 9)
                    .padding(.bottom, 4)
            }
            .overlay(alignment: .leading) {
                TimelineTrimHandle()
                    .offset(x: -12)
            }
            .overlay(alignment: .trailing) {
                TimelineTrimHandle()
                    .offset(x: 12)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
    }

    private func seek(to x: CGFloat, width: CGFloat) {
        guard duration.isFinite, duration > 0, width > 0 else { return }
        let fraction = min(max(x / width, 0), 1)
        seek(duration * Double(fraction))
    }

    private func loadWaveform() async {
        guard let videoURL else {
            waveformSamples = TimelineAudioWaveformLoader.quietSamples()
            return
        }

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
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: "scissors")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
            }
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.20), lineWidth: 1)
            }
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
            var fillPath = Path()
            var strokePath = Path()

            fillPath.move(to: CGPoint(x: 0, y: size.height))

            for (index, sample) in levels.enumerated() {
                let x = CGFloat(index) * step
                let boostedLevel = CGFloat(sqrt(max(0.0, min(sample, 1.0))))
                let height = max(2, boostedLevel * (size.height - 2))
                let point = CGPoint(x: x, y: size.height - height)

                if index == 0 {
                    fillPath.addLine(to: point)
                    strokePath.move(to: point)
                } else {
                    fillPath.addLine(to: point)
                    strokePath.addLine(to: point)
                }
            }

            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .color(Color.white.opacity(0.18)))
            context.stroke(strokePath, with: .color(Color.white.opacity(0.24)), lineWidth: 1)
        }
    }
}

func formatClipDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else {
        return "0s"
    }

    if seconds < 60 {
        return "\(max(1, Int(seconds.rounded())))s"
    }

    return formatPlaybackTime(seconds)
}

struct TimelineLayerRow: View {
    var label: String
    var hint: String
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.86))
                .lineLimit(1)
                .frame(width: TimelineMetrics.labelWidth, height: TimelineMetrics.layerHeight, alignment: .leading)
                .padding(.leading, 10)
                .background(Color.white.opacity(0.025))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.095, green: 0.095, blue: 0.11))

                    Text(hint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.64))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: TimelineMetrics.layerHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)
        }
    }
}

