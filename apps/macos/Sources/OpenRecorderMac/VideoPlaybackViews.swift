import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum VideoPreviewAspectPreset: String, CaseIterable, Identifiable {
    case auto
    case wide
    case square
    case classic
    case vertical
    case tall
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .wide: "Wide 16:9"
        case .square: "Square 1:1"
        case .classic: "Classic 4:3"
        case .vertical: "Vertical 9:16"
        case .tall: "Tall 3:4"
        case .portrait: "Portrait 4:5"
        }
    }

    func aspectRatio(for cropSelection: VideoCropSelection, sourceSize: CGSize) -> CGFloat {
        fixedAspectRatio ?? cropSelection.previewAspectRatio(in: sourceSize)
    }

    func aspectRatio(forExportSourceSize sourceSize: CGSize) -> CGFloat {
        if let fixedAspectRatio {
            return fixedAspectRatio
        }

        let safeSize = VideoCropSelection.safeSourceSize(sourceSize)
        return safeSize.width / max(safeSize.height, 1)
    }

    private var fixedAspectRatio: CGFloat? {
        switch self {
        case .auto:
            nil
        case .wide:
            16.0 / 9.0
        case .square:
            1
        case .classic:
            4.0 / 3.0
        case .vertical:
            9.0 / 16.0
        case .tall:
            3.0 / 4.0
        case .portrait:
            4.0 / 5.0
        }
    }
}

struct VideoPreviewPanel: View {
    var videoURL: URL?
    var recordingSession: RecordingSession?
    @ObservedObject var playback: VideoPlaybackController
    var timelineEdits: TimelineEditDriver
    var background: BackgroundStyle = .transparent
    var padding: Double = 0
    var borderRadius: Double = 0
    var shadow: Double = 0
    var backgroundBlur: Double = 0
    var inset: Double = 0
    var insetColor: SerializableColor = SerializableColor(hex: "#276FAA")
    var insetOpacity: Double = 1
    var insetBalance: VideoInsetBalance = .centered
    var cursorTelemetryURL: URL?
    var cursorSettings: CursorOverlaySettings = .hidden
    var cropSelection: VideoCropSelection = .fullFrame
    var facecamSettings: FacecamSettings?
    @Binding var previewAspectPreset: VideoPreviewAspectPreset
    var onCropVideo: () -> Void = {}
    var onRequestClearSelection: () -> Void = {}
    @State private var isPreviewAspectDropdownPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if videoURL != nil {
                previewControlRow
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }

            ZStack {
                if videoURL != nil {
                    AspectRatioFitContainer(aspectRatio: previewAspectRatio) {
                        styledStage
                    } overlay: {
                        recordingSessionBadges
                    }
                    .padding(16)
                } else {
                    EmptyEditorState()
                }
            }
            .rectangularHitTarget()
            .simultaneousGesture(
                TapGesture().onEnded {
                    onRequestClearSelection()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .studioEditorPaneChrome()
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

    private var previewControlRow: some View {
        HStack(spacing: 8) {
            cropButton
            previewAspectMenu
        }
    }

    private var cropButton: some View {
        StudioButton(hitTarget: .capsule, help: "Crop", action: onCropVideo) {
            Label("Crop", systemImage: "crop")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.86))
                .padding(.horizontal, 12)
                .frame(height: 32)
        }
    }

    private var previewAspectMenu: some View {
        StudioButton(hitTarget: .capsule, help: "Preview aspect ratio") {
            isPreviewAspectDropdownPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Text(previewAspectPreset.title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.86))
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .popover(isPresented: $isPreviewAspectDropdownPresented, arrowEdge: .top) {
            PreviewAspectDropdown(
                selection: $previewAspectPreset,
                onSelect: {
                    isPreviewAspectDropdownPresented = false
                }
            )
        }
    }

    private var styledStage: some View {
        GeometryReader { proxy in
            let recordingFrame = PreviewStageLayout.recordingFrameRect(
                forAspectRatio: previewAspectRatio,
                in: proxy.size,
                paddingValue: padding
            )

            ZStack(alignment: .topLeading) {
                BackgroundFillView(style: background)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: CGFloat(backgroundBlur))
                    .clipped()

                VideoInsetRecordingFrame(
                    inset: inset,
                    insetColor: insetColor,
                    insetOpacity: insetOpacity,
                    insetBalance: insetBalance,
                    cornerRadius: CGFloat(borderRadius)
                ) {
                    PlaybackPreview(
                        playback: playback,
                        edits: timelineEdits.snapshot,
                        cursorTelemetryURL: cursorTelemetryURL,
                        cursorSettings: cursorSettings,
                        cropSelection: cropSelection,
                        facecamURL: facecamVideoURL,
                        facecamOffsetMs: recordingSession?.facecamOffsetMs,
                        facecamSettings: resolvedFacecamSettings,
                        sourceSize: playback.naturalVideoSize,
                        letterboxFill: previewLetterboxFill
                    )
                }
                .frame(width: recordingFrame.width, height: recordingFrame.height)
                .shadow(
                    color: Color.black.opacity(0.55 * shadow),
                    radius: 38 * CGFloat(shadow),
                    y: 18 * CGFloat(shadow)
                )
                .offset(x: recordingFrame.minX, y: recordingFrame.minY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var previewAspectRatio: CGFloat {
        previewAspectPreset.aspectRatio(for: cropSelection, sourceSize: playback.naturalVideoSize)
    }

    private var previewLetterboxFill: VideoPreviewLetterboxFill {
        PreviewStageLayout.letterboxFill(
            background: background,
            inset: inset,
            insetOpacity: insetOpacity
        )
    }

    private var facecamVideoURL: URL? {
        guard let path = recordingSession?.facecamVideoPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private var resolvedFacecamSettings: FacecamSettings? {
        guard facecamVideoURL != nil else {
            return nil
        }
        return (facecamSettings ?? recordingSession?.facecamSettings ?? defaultFacecamSettings(enabled: true)).clamped
    }

    @ViewBuilder
    private var recordingSessionBadges: some View {
        if let recordingSession,
           recordingSession.hasRecordedCamera,
           resolvedFacecamSettings?.enabled != true {
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

private struct VideoInsetRecordingFrame<Content: View>: View {
    var inset: Double
    var insetColor: SerializableColor
    var insetOpacity: Double
    var insetBalance: VideoInsetBalance
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let frameRect = CGRect(origin: .zero, size: proxy.size)
            let amountRatio = VideoInsetGeometry.amountRatio(fromValue: inset.rounded())
            let insetLayout = VideoInsetGeometry.layout(
                in: frameRect,
                amountRatio: amountRatio,
                balance: insetBalance
            )
            let contentRect = insetLayout.contentRect
            let contentCornerRadius = cornerRadius * min(
                contentRect.width / max(insetLayout.frameRect.width, 1),
                contentRect.height / max(insetLayout.frameRect.height, 1)
            )
            let hasInset = amountRatio > 0 && insetOpacity > 0

            ZStack(alignment: .topLeading) {
                if hasInset {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(insetColor.color.opacity(max(0, min(insetOpacity, 1))))
                        .frame(width: insetLayout.frameRect.width, height: insetLayout.frameRect.height)
                        .offset(x: insetLayout.frameRect.minX, y: insetLayout.frameRect.minY)
                }

                content()
                    .frame(width: contentRect.width, height: contentRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: max(0, contentCornerRadius), style: .continuous))
                    .offset(x: contentRect.minX, y: contentRect.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

enum PreviewStageLayout {
    static let videoAspectRatio: CGFloat = 16.0 / 9.0

    static func paddingLength(forValue value: Double, in availableSize: CGSize) -> CGFloat {
        guard value.isFinite,
              availableSize.width.isFinite,
              availableSize.height.isFinite,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return 0
        }

        return CGFloat(max(0, value) / 100 * 0.2) * min(availableSize.width, availableSize.height)
    }

    static func recordingFrameRect(forAspectRatio aspectRatio: CGFloat, in availableSize: CGSize, paddingValue: Double) -> CGRect {
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              availableSize.width.isFinite,
              availableSize.height.isFinite,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let padding = paddingLength(forValue: paddingValue, in: availableSize)
        let paddedSize = CGSize(
            width: max(2, availableSize.width - 2 * padding),
            height: max(2, availableSize.height - 2 * padding)
        )
        let frameSize = fittedSize(forAspectRatio: aspectRatio, in: paddedSize)
        guard frameSize.width > 0, frameSize.height > 0 else { return .zero }

        return CGRect(
            x: (availableSize.width - frameSize.width) / 2,
            y: (availableSize.height - frameSize.height) / 2,
            width: frameSize.width,
            height: frameSize.height
        )
    }

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

    static func letterboxFill(
        background: BackgroundStyle,
        inset: Double,
        insetOpacity: Double
    ) -> VideoPreviewLetterboxFill {
        let hasVisibleBackground = !background.isTransparent
        let hasVisibleInset = VideoInsetGeometry.amountRatio(fromValue: inset.rounded()) > 0 && insetOpacity > 0
        return hasVisibleBackground || hasVisibleInset ? .clear : .black
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
    @Published var naturalVideoSize = CGSize.zero
    @Published var previewPlaybackSpeed = 1.0
    private var timelineEdits = TimelineEditSnapshot.empty

    static let previewPlaybackSpeeds = [1.0, 2.0, 4.0, 8.0]

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
        naturalVideoSize = .zero
        previewPlaybackSpeed = Self.previewPlaybackSpeeds[0]

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
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            let loadedVideoSize: CGSize
            if let track = tracks.first,
               let naturalSize = try? await track.load(.naturalSize),
               let preferredTransform = try? await track.load(.preferredTransform) {
                let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
                loadedVideoSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
            } else {
                loadedVideoSize = .zero
            }
            await MainActor.run {
                guard let self, self.currentURL == url else { return }
                self.duration = seconds.isFinite && seconds > 0 ? seconds : 0
                self.naturalVideoSize = loadedVideoSize
            }
        }
    }

    func clear() {
        teardownPlayer()
        currentURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        naturalVideoSize = .zero
        previewPlaybackSpeed = Self.previewPlaybackSpeeds[0]
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

    func cyclePreviewPlaybackSpeed() {
        let currentIndex = Self.previewPlaybackSpeeds
            .enumerated()
            .min { abs($0.element - previewPlaybackSpeed) < abs($1.element - previewPlaybackSpeed) }?
            .offset ?? 0
        let nextIndex = (currentIndex + 1) % Self.previewPlaybackSpeeds.count
        previewPlaybackSpeed = Self.previewPlaybackSpeeds[nextIndex]
        if isPlaying {
            applyPlaybackRate()
        }
    }

    func previewPlaybackSpeedLabel() -> String {
        "\(Int(previewPlaybackSpeed.rounded()))x"
    }

    func effectivePlaybackRate(at time: Double? = nil) -> Double {
        let playbackTime = time ?? currentTime
        return timelineEdits.activeSpeed(at: playbackTime, duration: duration) * previewPlaybackSpeed
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
        let rate = Float(effectivePlaybackRate())
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
    var cursorTelemetryURL: URL?
    var cursorSettings: CursorOverlaySettings = .hidden
    var cropSelection: VideoCropSelection = .fullFrame
    var facecamURL: URL?
    var facecamOffsetMs: Int?
    var facecamSettings: FacecamSettings?
    var sourceSize: CGSize = .zero
    var letterboxFill: VideoPreviewLetterboxFill = .black

    var body: some View {
        GeometryReader { proxy in
            let sourceSize = VideoCropSelection.safeSourceSize(sourceSize)
            let cropRect = cropSelection.pixelRect(in: sourceSize)
            let scale = min(
                proxy.size.width / max(cropRect.width, 1),
                proxy.size.height / max(cropRect.height, 1)
            )
            let sourceDisplaySize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let centeredOffset = CGPoint(
                x: (proxy.size.width - cropRect.width * scale) / 2,
                y: (proxy.size.height - cropRect.height * scale) / 2
            )
            let contentOffset = CGSize(
                width: centeredOffset.x - cropRect.minX * scale,
                height: centeredOffset.y - cropRect.minY * scale
            )

            ZStack(alignment: .topLeading) {
                fullSourcePreview(size: sourceDisplaySize)
                    .frame(width: sourceDisplaySize.width, height: sourceDisplaySize.height)
                    .offset(contentOffset)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()

                if let facecamURL,
                   let facecamSettings,
                   facecamSettings.clamped.enabled {
                    FacecamPlaybackOverlay(
                        facecamURL: facecamURL,
                        screenPlayback: playback,
                        offsetMs: facecamOffsetMs,
                        settings: facecamSettings
                    )
                }
            }
            .background(letterboxFill.color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.studioBorder)
            }
        }
        .onChange(of: edits) { _, newValue in
            playback.setTimelineEdits(newValue)
        }
        .onAppear { playback.setTimelineEdits(edits) }
    }

    private func fullSourcePreview(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                NativeVideoPlayer(playback: playback)
                    .frame(width: size.width, height: size.height)

                CursorOverlayView(
                    playback: playback,
                    telemetryURL: cursorTelemetryURL,
                    settings: cursorSettings
                )
                .frame(width: size.width, height: size.height)
            }
                .scaleEffect(activeZoomScale, anchor: activeZoomAnchor)
                .animation(.easeInOut(duration: 0.18), value: activeZoomScale)
                .frame(width: size.width, height: size.height)

            ForEach(edits.annotations(at: playback.currentTime)) { annotation in
                Text(annotation.text)
                    .font(.system(size: annotation.fontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
                    .position(x: annotation.x * size.width, y: annotation.y * size.height)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            }
        }
    }

    private var activeZoomScale: CGFloat {
        CGFloat(edits.activeZoomEffect(at: playback.currentTime)?.depth ?? 1)
    }

    private var activeZoomAnchor: UnitPoint {
        guard let effect = edits.activeZoomEffect(at: playback.currentTime) else { return .center }
        return UnitPoint(x: effect.focusX, y: effect.focusY)
    }
}

struct FacecamOverlayLayout {
    static func frame(in containerSize: CGSize, settings: FacecamSettings) -> CGRect {
        let resolved = settings.clamped
        guard resolved.enabled,
              containerSize.width.isFinite,
              containerSize.height.isFinite,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let baseLength = min(containerSize.width, containerSize.height)
        let side = max(1, baseLength * CGFloat(resolved.size / 100))
        let margin = baseLength * CGFloat(resolved.margin / 100)
        let halfSide = side / 2
        let x: CGFloat
        let y: CGFloat

        switch resolved.resolvedAnchor {
        case .topLeft, .left, .bottomLeft:
            x = margin + halfSide
        case .top, .center, .bottom:
            x = containerSize.width / 2
        case .topRight, .right, .bottomRight:
            x = containerSize.width - margin - halfSide
        }

        switch resolved.resolvedAnchor {
        case .topLeft, .top, .topRight:
            y = margin + halfSide
        case .left, .center, .right:
            y = containerSize.height / 2
        case .bottomLeft, .bottom, .bottomRight:
            y = containerSize.height - margin - halfSide
        }

        return CGRect(x: x - halfSide, y: y - halfSide, width: side, height: side)
    }
}

private struct FacecamPlaybackOverlay: View {
    var facecamURL: URL
    @ObservedObject var screenPlayback: VideoPlaybackController
    var offsetMs: Int?
    var settings: FacecamSettings

    @State private var player: AVPlayer?
    @State private var currentURL: URL?
    @State private var duration = 0.0
    @State private var isActiveAtCurrentTime = true

    var body: some View {
        GeometryReader { proxy in
            let resolvedSettings = settings.clamped
            let frame = FacecamOverlayLayout.frame(in: proxy.size, settings: resolvedSettings)
            if let player,
               resolvedSettings.enabled,
               isActiveAtCurrentTime,
               !frame.isEmpty {
                FacecamPlayerView(player: player)
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius(for: frame, settings: resolvedSettings), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius(for: frame, settings: resolvedSettings), style: .continuous)
                            .stroke(
                                SerializableColor(hex: resolvedSettings.borderColor).color,
                                lineWidth: CGFloat(resolvedSettings.borderWidth)
                            )
                    }
                    .shadow(color: Color.black.opacity(0.34), radius: 16, y: 8)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityLabel("Facecam preview")
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            loadFacecam()
            syncPlayback(forceSeek: true)
        }
        .onChange(of: facecamURL) { _, _ in
            loadFacecam()
            syncPlayback(forceSeek: true)
        }
        .onChange(of: screenPlayback.currentTime) { _, _ in
            syncPlayback(forceSeek: false)
        }
        .onChange(of: screenPlayback.isPlaying) { _, _ in
            syncPlayback(forceSeek: true)
        }
        .onChange(of: screenPlayback.previewPlaybackSpeed) { _, _ in
            syncPlayback(forceSeek: false)
        }
        .onChange(of: settings) { _, _ in
            syncPlayback(forceSeek: false)
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadFacecam() {
        guard currentURL != facecamURL else { return }
        currentURL = facecamURL
        duration = 0

        let item = AVPlayerItem(url: facecamURL)
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.isMuted = true
        nextPlayer.automaticallyWaitsToMinimizeStalling = false
        player = nextPlayer

        let asset = AVURLAsset(url: facecamURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds ?? 0
            await MainActor.run {
                guard currentURL == facecamURL else { return }
                duration = seconds.isFinite && seconds > 0 ? seconds : 0
                syncPlayback(forceSeek: true)
            }
        }
    }

    private func syncPlayback(forceSeek: Bool) {
        let targetTime = facecamTime(for: screenPlayback.currentTime)
        let isWithinFacecam = targetTime >= 0 && (duration == 0 || targetTime <= duration + 0.05)
        isActiveAtCurrentTime = isWithinFacecam

        guard let player, isWithinFacecam else {
            player?.pause()
            return
        }

        let clampedTarget = min(max(targetTime, 0), duration > 0 ? duration : targetTime)
        let currentSeconds = player.currentTime().seconds
        if forceSeek || !currentSeconds.isFinite || abs(currentSeconds - clampedTarget) > 0.18 {
            player.seek(
                to: CMTime(seconds: clampedTarget, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        if screenPlayback.isPlaying {
            player.rate = Float(max(0.05, screenPlayback.effectivePlaybackRate()))
        } else {
            player.pause()
        }
    }

    private func facecamTime(for screenTime: Double) -> Double {
        screenTime - (Double(offsetMs ?? 0) / 1000)
    }

    private func cornerRadius(for frame: CGRect, settings: FacecamSettings) -> CGFloat {
        if settings.isCircle {
            return min(frame.width, frame.height) / 2
        }

        return min(CGFloat(settings.cornerRadius), min(frame.width, frame.height) / 2)
    }
}

enum VideoPreviewLetterboxFill: Equatable {
    case black
    case clear

    var color: Color {
        switch self {
        case .black: .black
        case .clear: .clear
        }
    }
}

private struct PreviewAspectDropdown: View {
    @Binding var selection: VideoPreviewAspectPreset
    var onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(VideoPreviewAspectPreset.allCases) { option in
                Button {
                    selection = option
                    onSelect()
                } label: {
                    HStack(spacing: 10) {
                        Text(option.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        if selection == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 28)
                    .padding(.horizontal, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == option ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .frame(width: 164)
        .background(Color.studioPanel)
    }
}

private struct CursorOverlayView: View {
    @ObservedObject var playback: VideoPlaybackController
    var telemetryURL: URL?
    var settings: CursorOverlaySettings
    @State private var track: CursorTelemetryTrack?
    @State private var loadedTelemetryPath: String?

    var body: some View {
        GeometryReader { proxy in
            if let point = currentPoint(in: proxy.size) {
                let resolvedSettings = settings.clamped
                CursorGlyphView(
                    style: resolvedSettings.style,
                    variant: resolvedSettings.variant,
                    scale: resolvedSettings.size,
                    alignsHotspot: true
                )
                    .offset(x: point.x, y: point.y)
                    .allowsHitTesting(false)
            }
        }
        .task(id: telemetryURL?.path) {
            loadTelemetry()
        }
        .onAppear {
            loadTelemetry()
        }
        .allowsHitTesting(false)
    }

    private func currentPoint(in size: CGSize) -> CGPoint? {
        let resolvedSettings = settings.clamped
        guard resolvedSettings.isVisible,
              size.width > 0,
              size.height > 0,
              let track,
              let point = track.point(at: playback.currentTime, settings: resolvedSettings) else {
            return nil
        }

        return CGPoint(
            x: point.x / CGFloat(max(track.width, 1)) * size.width,
            y: point.y / CGFloat(max(track.height, 1)) * size.height
        )
    }

    @MainActor
    private func loadTelemetry() {
        guard let telemetryURL else {
            loadedTelemetryPath = nil
            track = nil
            return
        }
        guard loadedTelemetryPath != telemetryURL.path else { return }
        loadedTelemetryPath = telemetryURL.path
        guard let payload = try? CursorTelemetryPayload.load(from: telemetryURL) else {
            track = nil
            return
        }
        track = CursorTelemetryTrack(payload: payload)
    }
}

final class PlayerLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
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

struct FacecamPlayerView: NSViewRepresentable {
    var player: AVPlayer?

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.playerLayer.player = player
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}
