import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct VideoPreviewPanel: View {
    var videoURL: URL?
    var recordingSession: RecordingSession?
    @ObservedObject var playback: VideoPlaybackController
    @ObservedObject var timelineEdits: TimelineEditController

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if videoURL != nil {
                    ZStack(alignment: .bottomTrailing) {
                        PlaybackPreview(playback: playback, edits: timelineEdits.snapshot)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        recordingSessionBadges
                    }
                    .padding(16)
                } else {
                    EmptyEditorState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack {
                Spacer(minLength: 0)
                PlaybackControlStrip(playback: playback)
                    .frame(maxWidth: 700)
                Spacer(minLength: 0)
            }
                .frame(height: 54)
                .padding(.horizontal, 12)
        }
        .background(Color.studioPanel.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 14)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            syncPlaybackURL(videoURL)
        }
        .onChange(of: videoURL) { _, newURL in
            syncPlaybackURL(newURL)
        }
    }

    private func syncPlaybackURL(_ url: URL?) {
        if let url {
            playback.load(url: url)
        } else {
            playback.clear()
        }
    }

    @ViewBuilder
    private var recordingSessionBadges: some View {
        if let recordingSession {
            VStack(alignment: .trailing, spacing: 6) {
                if recordingSession.facecamVideoPath != nil {
                    Label("Facecam captured", systemImage: "video.fill")
                }
                if recordingSession.cursorTelemetryPath != nil {
                    Label("Cursor telemetry", systemImage: "cursorarrow.motionlines")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(Color.white)
            .padding(12)
        }
    }
}

@MainActor
final class VideoPlaybackController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var currentTime = 0.0
    @Published var duration = 0.0
    @Published var isPlaying = false
    private var timelineEdits = TimelineEditSnapshot.empty

    private var currentURL: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        if currentURL == url, player != nil {
            return
        }

        teardownPlayer()
        currentURL = url
        currentTime = 0
        duration = 0
        isPlaying = false

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        attachTimeObserver(to: player)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }

        let asset = AVURLAsset(url: url)
        Task { [weak self] in
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds ?? 0
            await MainActor.run {
                guard let self, self.currentURL == url else { return }
                self.duration = seconds.isFinite && seconds > 0 ? seconds : 0
            }
        }
    }

    func clear() {
        teardownPlayer()
        currentURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            pause()
        } else {
            if duration > 0, currentTime >= duration {
                seek(to: 0)
            }
            applyPlaybackRate()
            isPlaying = true
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func setTimelineEdits(_ edits: TimelineEditSnapshot) {
        timelineEdits = edits
        enforceTimelineEdits(at: currentTime)
        if isPlaying { applyPlaybackRate() }
    }

    func seek(to seconds: Double) {
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let clamped = min(max(seconds, 0), upperBound)
        currentTime = clamped
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func attachTimeObserver(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self, seconds.isFinite else { return }
                self.currentTime = seconds
                self.enforceTimelineEdits(at: seconds)

                let itemDuration = self.player?.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite, itemDuration > 0, self.duration == 0 {
                    self.duration = itemDuration
                }
            }
        }
    }

    private func enforceTimelineEdits(at seconds: Double) {
        if let trimEnd = timelineEdits.nextTrimEnd(containing: seconds), trimEnd > seconds {
            seek(to: min(trimEnd, duration))
            return
        }
        if isPlaying {
            applyPlaybackRate()
        }
    }

    private func applyPlaybackRate() {
        guard let player else { return }
        let rate = Float(timelineEdits.activeSpeed(at: currentTime)?.speed ?? 1)
        player.rate = max(0.05, rate)
    }

    private func teardownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        player?.pause()
        player = nil
    }

}

struct EmptyEditorState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundStyle(Color.brand)
                .frame(width: 66, height: 66)
                .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.brand.opacity(0.22))
                }
            Text("No Recording Open")
                .font(.system(size: 18, weight: .semibold))
            Text("Start a recording or open a project to edit and export.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

struct PlaybackControlStrip: View {
    @ObservedObject var playback: VideoPlaybackController

    var body: some View {
        HStack(spacing: 12) {
            StudioButton(hitTarget: .circle) {
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(playback.isPlaying ? Color.white.opacity(0.10) : Color.white, in: Circle())
                    .foregroundStyle(playback.isPlaying ? Color.white : Color.black)
            }
            .disabled(playback.player == nil)
            .opacity(playback.player == nil ? 0.45 : 1)

            Text(formatPlaybackTime(playback.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.76))
                .frame(width: 42, alignment: .trailing)

            ElasticSlider(
                value: Binding(
                    get: { playback.currentTime },
                    set: { playback.seek(to: $0) }
                ),
                range: 0...max(playback.duration, 0.01),
                step: 0.01
            )
            .accessibilityLabel("Playback position")
            .disabled(playback.player == nil)

            Text(formatPlaybackTime(playback.duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))
                .frame(width: 42, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.58), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 14, y: 8)
    }
}

func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else {
        return "0:00"
    }

    let minutes = Int(seconds) / 60
    let remainingSeconds = Int(seconds) % 60
    return "\(minutes):\(String(format: "%02d", remainingSeconds))"
}

struct PlaybackPreview: View {
    @ObservedObject var playback: VideoPlaybackController
    var edits: TimelineEditSnapshot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            NativeVideoPlayer(playback: playback)
                .scaleEffect(activeZoomScale, anchor: activeZoomAnchor)
                .animation(.easeInOut(duration: 0.18), value: activeZoomScale)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.studioBorder)
                }

            ForEach(edits.annotations(at: playback.currentTime)) { annotation in
                Text(annotation.text)
                    .font(.system(size: annotation.fontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
                    .position(x: annotation.x * 640, y: annotation.y * 360)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            }

            StudioButton(hitTarget: .capsule) {
                playback.togglePlayback()
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 34)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.64), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .foregroundStyle(.white)
            }
            .disabled(playback.player == nil)
            .opacity(playback.player == nil ? 0.45 : 1)
            .padding(14)
        }
        .onChange(of: edits) { _, newValue in
            playback.setTimelineEdits(newValue)
        }
        .onAppear { playback.setTimelineEdits(edits) }
    }

    private var activeZoomScale: CGFloat {
        CGFloat(edits.activeZoom(at: playback.currentTime)?.depth ?? 1)
    }

    private var activeZoomAnchor: UnitPoint {
        guard let zoom = edits.activeZoom(at: playback.currentTime) else { return .center }
        return UnitPoint(x: zoom.focusX, y: zoom.focusY)
    }
}

final class PlayerLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            preconditionFailure("PlayerLayerView requires an AVPlayerLayer backing layer.")
        }
        return playerLayer
    }
}

struct NativeVideoPlayer: NSViewRepresentable {
    @ObservedObject var playback: VideoPlaybackController

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = playback.player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.playerLayer.player = playback.player
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}

