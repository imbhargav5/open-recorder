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
    var background: BackgroundStyle = .transparent
    var padding: Double = 0
    var borderRadius: Double = 0
    var shadow: Double = 0
    var backgroundBlur: Double = 0
    var onRequestClearSelection: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if videoURL != nil {
                    AspectRatioFitContainer(aspectRatio: PreviewStageLayout.videoAspectRatio) {
                        styledStage
                    } overlay: {
                        recordingSessionBadges
                    }
                    .padding(16)
                } else {
                    EmptyEditorState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .rectangularHitTarget()
        .simultaneousGesture(
            TapGesture().onEnded {
                onRequestClearSelection()
            }
        )
    }

    private func syncPlaybackURL(_ url: URL?) {
        if let url {
            playback.load(url: url)
        } else {
            playback.clear()
        }
    }

    private var styledStage: some View {
        ZStack {
            BackgroundFillView(style: background)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: CGFloat(backgroundBlur))
                .clipped()
            PlaybackPreview(playback: playback, edits: timelineEdits.snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(borderRadius), style: .continuous))
                .shadow(
                    color: Color.black.opacity(0.55 * shadow),
                    radius: 38 * CGFloat(shadow),
                    y: 18 * CGFloat(shadow)
                )
                .padding(CGFloat(padding))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var recordingSessionBadges: some View {
        if let recordingSession, recordingSession.facecamVideoPath != nil {
            Label("Facecam captured", systemImage: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(Color.white)
                .padding(12)
        }
    }
}

enum PreviewStageLayout {
    static let videoAspectRatio: CGFloat = 16.0 / 9.0

    static func fittedSize(forAspectRatio aspectRatio: CGFloat, in availableSize: CGSize) -> CGSize {
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              availableSize.width.isFinite,
              availableSize.height.isFinite,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let availableAspectRatio = availableSize.width / availableSize.height
        if availableAspectRatio > aspectRatio {
            let height = availableSize.height
            return CGSize(width: height * aspectRatio, height: height)
        }

        let width = availableSize.width
        return CGSize(width: width, height: width / aspectRatio)
    }
}

private struct AspectRatioFitContainer<Content: View, Overlay: View>: View {
    var aspectRatio: CGFloat
    var alignment: Alignment = .bottomTrailing
    @ViewBuilder var content: () -> Content
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        GeometryReader { proxy in
            let fittedSize = PreviewStageLayout.fittedSize(forAspectRatio: aspectRatio, in: proxy.size)

            ZStack(alignment: alignment) {
                content()
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .clipped()

                overlay()
                    .frame(width: fittedSize.width, height: fittedSize.height, alignment: alignment)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
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
        guard player != nil else { return }

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
