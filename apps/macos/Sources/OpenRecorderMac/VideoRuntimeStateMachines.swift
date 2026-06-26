import AVFoundation
import CoreGraphics
import Foundation
import Observation
import SwiftUI

enum VideoPlaybackSpeeds {
    static let values: [Double] = [1.0, 2.0, 4.0, 8.0]
    static let defaultSpeed = values[0]
}

struct VideoPlaybackState: Equatable {
    var currentURL: URL?
    var currentTime = 0.0
    var duration = 0.0
    var isPlaying = false
    var naturalVideoSize = CGSize.zero
    var previewPlaybackSpeed = VideoPlaybackSpeeds.defaultSpeed
    var timelineEdits = TimelineEditSnapshot.empty

    var previewPlaybackSpeedLabel: String {
        "\(Int(previewPlaybackSpeed.rounded()))x"
    }

    func effectivePlaybackRate(at time: Double? = nil) -> Double {
        let playbackTime = time ?? currentTime
        return timelineEdits.activeSpeed(at: playbackTime, duration: duration) * previewPlaybackSpeed
    }
}

enum VideoPlaybackEvent: Equatable {
    case load(URL)
    case metadataLoaded(URL, duration: Double, naturalSize: CGSize)
    case clear
    case playToggled
    case paused
    case seekRequested(Double)
    case currentTimeChanged(Double)
    case didPlayToEnd
    case previewSpeedCycled
    case timelineEditsChanged(TimelineEditSnapshot)
}

enum VideoPlaybackEffect: Equatable {
    case loadPlayer(URL)
    case clearPlayer
    case play(rate: Double)
    case pause
    case seek(Double)
    case loadMetadata(URL)
}

extension VideoPlaybackState {
    mutating func applying(_ event: VideoPlaybackEvent) -> [VideoPlaybackEffect] {
        switch event {
        case .load(let url):
            guard currentURL != url else { return [] }
            currentURL = url
            currentTime = 0
            duration = 0
            isPlaying = false
            naturalVideoSize = .zero
            previewPlaybackSpeed = VideoPlaybackSpeeds.defaultSpeed
            return [.clearPlayer, .loadPlayer(url), .loadMetadata(url)]

        case .metadataLoaded(let url, let loadedDuration, let naturalSize):
            guard currentURL == url else { return [] }
            duration = loadedDuration.isFinite && loadedDuration > 0 ? loadedDuration : 0
            naturalVideoSize = naturalSize
            return []

        case .clear:
            currentURL = nil
            currentTime = 0
            duration = 0
            isPlaying = false
            naturalVideoSize = .zero
            previewPlaybackSpeed = VideoPlaybackSpeeds.defaultSpeed
            timelineEdits = .empty
            return [.clearPlayer]

        case .playToggled:
            guard currentURL != nil else { return [] }
            if isPlaying {
                isPlaying = false
                return [.pause]
            }
            var effects: [VideoPlaybackEffect] = []
            if duration > 0, currentTime >= duration {
                currentTime = 0
                effects.append(.seek(0))
            }
            isPlaying = true
            effects.append(.play(rate: effectivePlaybackRate()))
            return effects

        case .paused:
            guard isPlaying else { return [.pause] }
            isPlaying = false
            return [.pause]

        case .seekRequested(let seconds):
            let upperBound = duration > 0 ? duration : max(seconds, 0)
            let clamped = min(max(seconds, 0), upperBound)
            currentTime = clamped
            return [.seek(clamped)]

        case .currentTimeChanged(let seconds):
            guard seconds.isFinite else { return [] }
            currentTime = seconds
            if let trimEnd = timelineEdits.nextTrimEnd(containing: seconds), trimEnd > seconds {
                let nextTime = min(trimEnd, duration)
                currentTime = nextTime
                return [.seek(nextTime)]
            }
            return isPlaying ? [.play(rate: effectivePlaybackRate())] : []

        case .didPlayToEnd:
            isPlaying = false
            currentTime = 0
            return [.pause, .seek(0)]

        case .previewSpeedCycled:
            let currentIndex = VideoPlaybackSpeeds.values
                .enumerated()
                .min { abs($0.element - previewPlaybackSpeed) < abs($1.element - previewPlaybackSpeed) }?
                .offset ?? 0
            let nextIndex = (currentIndex + 1) % VideoPlaybackSpeeds.values.count
            previewPlaybackSpeed = VideoPlaybackSpeeds.values[nextIndex]
            return isPlaying ? [.play(rate: effectivePlaybackRate())] : []

        case .timelineEditsChanged(let edits):
            guard timelineEdits != edits else { return [] }
            timelineEdits = edits
            var effects = applying(.currentTimeChanged(currentTime))
            if isPlaying {
                effects.append(.play(rate: effectivePlaybackRate()))
            }
            return effects
        }
    }
}

@Observable
@MainActor
final class VideoPlaybackDriver {
    nonisolated static let previewPlaybackSpeeds = VideoPlaybackSpeeds.values

    var state = VideoPlaybackState()
    var player: AVPlayer?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    var currentTime: Double {
        get { state.currentTime }
        set { state.currentTime = newValue }
    }

    var duration: Double {
        get { state.duration }
        set { state.duration = newValue }
    }

    var isPlaying: Bool {
        get { state.isPlaying }
        set { state.isPlaying = newValue }
    }

    var naturalVideoSize: CGSize {
        get { state.naturalVideoSize }
        set { state.naturalVideoSize = newValue }
    }

    var previewPlaybackSpeed: Double {
        get { state.previewPlaybackSpeed }
        set { state.previewPlaybackSpeed = newValue }
    }

    func load(url: URL) {
        send(.load(url))
    }

    func clear() {
        send(.clear)
    }

    func togglePlayback() {
        send(.playToggled)
    }

    func pause() {
        send(.paused)
    }

    func cyclePreviewPlaybackSpeed() {
        send(.previewSpeedCycled)
    }

    func previewPlaybackSpeedLabel() -> String {
        state.previewPlaybackSpeedLabel
    }

    func effectivePlaybackRate(at time: Double? = nil) -> Double {
        state.effectivePlaybackRate(at: time)
    }

    func setTimelineEdits(_ edits: TimelineEditSnapshot) {
        send(.timelineEditsChanged(edits))
    }

    func seek(to seconds: Double) {
        send(.seekRequested(seconds))
    }

    func send(_ event: VideoPlaybackEvent) {
        perform(state.applying(event))
    }

    private func perform(_ effects: [VideoPlaybackEffect]) {
        for effect in effects {
            switch effect {
            case .loadPlayer(let url):
                loadPlayer(url)
            case .clearPlayer:
                teardownPlayer()
            case .play(let rate):
                player?.rate = Float(max(0.05, rate))
            case .pause:
                player?.pause()
            case .seek(let seconds):
                player?.seek(
                    to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            case .loadMetadata(let url):
                Task { [weak self] in
                    await self?.loadMetadata(for: url)
                }
            }
        }
    }

    private func loadPlayer(_ url: URL) {
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
                self?.send(.didPlayToEnd)
            }
        }
    }

    private func loadMetadata(for url: URL) async {
        let asset = AVURLAsset(url: url)
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
            send(.metadataLoaded(url, duration: seconds, naturalSize: loadedVideoSize))
        }
    }

    private func attachTimeObserver(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor in
                guard let self else { return }
                self.send(.currentTimeChanged(seconds))

                let itemDuration = self.player?.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite, itemDuration > 0, self.state.duration == 0, let url = self.state.currentURL {
                    self.send(.metadataLoaded(url, duration: itemDuration, naturalSize: self.state.naturalVideoSize))
                }
            }
        }
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

typealias VideoPlaybackController = VideoPlaybackDriver

struct VideoCropState: Equatable {
    var draftSelection: VideoCropSelection
    var sourceSize: CGSize
    var aspect: VideoCropAspect = .any
    var isShortcutDropdownPresented = false

    var effectiveSourceSize: CGSize {
        VideoCropSelection.safeSourceSize(sourceSize)
    }

    var currentPixelRect: CGRect {
        draftSelection.pixelRect(in: effectiveSourceSize)
    }
}

enum VideoCropEvent: Equatable {
    case sourceSizeLoaded(CGSize)
    case draftSelectionChanged(VideoCropSelection)
    case aspectSelected(VideoCropAspect)
    case keyboardAdjusted(VideoCropKeyboardAdjustment)
    case sizeChanged(width: Int? = nil, height: Int? = nil)
    case positionChanged(x: Int? = nil, y: Int? = nil)
    case reset
    case shortcutsPresented(Bool)
    case confirmRequested
    case cancelRequested
}

enum VideoCropEffect: Equatable {
    case confirm(VideoCropSelection)
    case cancel
}

extension VideoCropState {
    mutating func applying(_ event: VideoCropEvent) -> [VideoCropEffect] {
        switch event {
        case .sourceSizeLoaded(let loadedSize):
            sourceSize = VideoCropSelection.safeSourceSize(loadedSize)
            draftSelection = draftSelection.withPixelRect(currentPixelRect, in: effectiveSourceSize)
            return []

        case .draftSelectionChanged(let selection):
            draftSelection = selection
            return []

        case .aspectSelected(let option):
            aspect = option
            guard let ratio = option.ratio(for: draftSelection, sourceSize: effectiveSourceSize) else { return [] }
            draftSelection = draftSelection.withPixelRect(aspectAdjustedRect(currentPixelRect, ratio: ratio), in: effectiveSourceSize)
            return []

        case .keyboardAdjusted(let adjustment):
            switch adjustment {
            case .move(let dx, let dy):
                let nextRect = currentPixelRect.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy))
                draftSelection = draftSelection.withPixelRect(nextRect, in: effectiveSourceSize)
            case .resize(let widthDelta, let heightDelta):
                setCropSize(width: currentPixelRect.width + CGFloat(widthDelta), height: currentPixelRect.height + CGFloat(heightDelta))
            }
            return []

        case .sizeChanged(let width, let height):
            setCropSize(
                width: CGFloat(width ?? max(1, Int(currentPixelRect.width.rounded()))),
                height: CGFloat(height ?? max(1, Int(currentPixelRect.height.rounded())))
            )
            return []

        case .positionChanged(let x, let y):
            let rect = currentPixelRect
            let nextRect = CGRect(
                x: CGFloat(x ?? Int(rect.minX.rounded())),
                y: CGFloat(y ?? Int(rect.minY.rounded())),
                width: rect.width,
                height: rect.height
            )
            draftSelection = draftSelection.withPixelRect(nextRect, in: effectiveSourceSize)
            return []

        case .reset:
            aspect = .any
            draftSelection = .fullFrame
            return []

        case .shortcutsPresented(let isPresented):
            isShortcutDropdownPresented = isPresented
            return []

        case .confirmRequested:
            return [.confirm(draftSelection)]

        case .cancelRequested:
            return [.cancel]
        }
    }

    private mutating func setCropSize(width: CGFloat, height: CGFloat) {
        let safeSize = effectiveSourceSize
        let rect = currentPixelRect
        var nextRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(width, VideoCropSelection.minimumPixelLength),
            height: max(height, VideoCropSelection.minimumPixelLength)
        )
        if let ratio = aspect.ratio(for: draftSelection, sourceSize: safeSize) {
            nextRect = aspectAdjustedRect(nextRect, ratio: ratio)
        }
        nextRect = VideoCropSelection.clampedPixelRect(nextRect, in: safeSize)
        draftSelection = draftSelection
            .withPixelRect(nextRect, in: safeSize)
            .withSizing(.custom(width: Int(nextRect.width.rounded()), height: Int(nextRect.height.rounded())))
    }

    private func aspectAdjustedRect(_ rect: CGRect, ratio: CGFloat) -> CGRect {
        guard ratio.isFinite, ratio > 0 else { return rect }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var width = rect.width
        var height = rect.height
        if width / max(height, 1) > ratio {
            width = height * ratio
        } else {
            height = width / ratio
        }
        return VideoCropSelection.clampedPixelRect(
            CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
            in: effectiveSourceSize
        )
    }
}

@Observable
@MainActor
final class VideoCropDriver {
    var state: VideoCropState

    @ObservationIgnored private var onConfirm: (VideoCropSelection) -> Void = { _ in }
    @ObservationIgnored private var onCancel: () -> Void = {}

    init(initialSelection: VideoCropSelection, sourceSize: CGSize) {
        state = VideoCropState(
            draftSelection: initialSelection,
            sourceSize: VideoCropSelection.safeSourceSize(sourceSize)
        )
    }

    func configure(onConfirm: @escaping (VideoCropSelection) -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    func send(_ event: VideoCropEvent) {
        perform(state.applying(event))
    }

    var selectionBinding: Binding<VideoCropSelection> {
        Binding(
            get: { self.state.draftSelection },
            set: { self.send(.draftSelectionChanged($0)) }
        )
    }

    var aspectBinding: Binding<VideoCropAspect> {
        Binding(
            get: { self.state.aspect },
            set: { self.send(.aspectSelected($0)) }
        )
    }

    var shortcutBinding: Binding<Bool> {
        Binding(
            get: { self.state.isShortcutDropdownPresented },
            set: { self.send(.shortcutsPresented($0)) }
        )
    }

    func widthBinding() -> Binding<Int> {
        Binding(
            get: { max(1, Int(self.state.currentPixelRect.width.rounded())) },
            set: { self.send(.sizeChanged(width: $0)) }
        )
    }

    func heightBinding() -> Binding<Int> {
        Binding(
            get: { max(1, Int(self.state.currentPixelRect.height.rounded())) },
            set: { self.send(.sizeChanged(height: $0)) }
        )
    }

    func xBinding() -> Binding<Int> {
        Binding(
            get: { max(0, Int(self.state.currentPixelRect.minX.rounded())) },
            set: { self.send(.positionChanged(x: $0)) }
        )
    }

    func yBinding() -> Binding<Int> {
        Binding(
            get: { max(0, Int(self.state.currentPixelRect.minY.rounded())) },
            set: { self.send(.positionChanged(y: $0)) }
        )
    }

    private func perform(_ effects: [VideoCropEffect]) {
        for effect in effects {
            switch effect {
            case .confirm(let selection):
                onConfirm(selection)
            case .cancel:
                onCancel()
            }
        }
    }
}
