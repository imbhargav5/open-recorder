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

    var ratioLabel: String {
        switch self {
        case .auto: "Auto"
        case .wide: "16:9"
        case .square: "1:1"
        case .classic: "4:3"
        case .vertical: "9:16"
        case .tall: "3:4"
        case .portrait: "4:5"
        }
    }

    var menuLabel: String {
        switch self {
        case .auto: "Source"
        case .wide: "Widescreen"
        case .square: "Square"
        case .classic: "Classic"
        case .vertical: "Vertical"
        case .tall: "Tall"
        case .portrait: "Portrait"
        }
    }

    var menuAspectRatio: CGFloat {
        fixedAspectRatio ?? 1.35
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
    var playback: VideoPlaybackController
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
    var cameraTimelineFallback: FacecamSettings?
    @Binding var previewAspectPreset: VideoPreviewAspectPreset
    var onCropVideo: () -> Void = {}
    var onRequestClearSelection: () -> Void = {}
    @State private var isPreviewAspectDropdownPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if videoURL != nil {
                previewControlRow
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
                    .padding(.bottom, 7)
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
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1, height: 20)
            previewAspectMenu
        }
        .padding(4)
        .background(Theme.scrim.opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }

    private var cropButton: some View {
        StudioButton(hitTarget: .capsule, help: "Crop", action: onCropVideo) {
            Label("Crop", systemImage: "crop")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.86))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Color.white.opacity(0.001), in: Capsule())
        }
    }

    private var previewAspectMenu: some View {
        StudioButton(hitTarget: .capsule, help: "Preview aspect ratio") {
            isPreviewAspectDropdownPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                PreviewAspectGlyph(preset: previewAspectPreset, isSelected: true)
                    .frame(width: 17, height: 17)
                Text(previewAspectPreset.ratioLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.58))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.86))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.white.opacity(0.001), in: Capsule())
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
            let zoomEffect = timelineEdits.snapshot.activeZoomEffect(at: playback.currentTime)
            let facecamZoomTransform = PreviewStageLayout.previewFullStageZoomTransform(
                effect: zoomEffect,
                stageSize: proxy.size,
                recordingFrame: recordingFrame,
                sourceSize: playback.naturalVideoSize,
                cropSelection: cropSelection,
                inset: inset,
                insetBalance: insetBalance
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

                if let facecamVideoURL,
                   let facecamSettings = activeFacecamSettings {
                    FacecamPlaybackOverlay(
                        facecamURL: facecamVideoURL,
                        screenPlayback: playback,
                        offsetMs: recordingSession?.facecamOffsetMs,
                        settings: facecamSettings
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transformEffect(facecamZoomTransform)
                }
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
        return (cameraTimelineFallback ?? facecamSettings ?? recordingSession?.facecamSettings ?? defaultFacecamSettings(enabled: true)).clamped
    }

    private var activeFacecamSettings: FacecamSettings? {
        timelineEdits.snapshot.activeCameraSettings(
            at: playback.currentTime,
            duration: playback.duration,
            fallback: resolvedFacecamSettings
        )
    }

    @ViewBuilder
    private var recordingSessionBadges: some View {
        if let recordingSession,
           recordingSession.hasRecordedCamera,
           activeFacecamSettings?.enabled != true {
            Label("Facecam captured", systemImage: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
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

    static func fullStageZoomAnchor(
        effect: TimelineZoomEffect?,
        stageSize: CGSize,
        recordingFrame: CGRect,
        sourceSize: CGSize,
        cropSelection: VideoCropSelection,
        inset: Double,
        insetBalance: VideoInsetBalance
    ) -> UnitPoint {
        guard let effect,
              stageSize.width.isFinite,
              stageSize.height.isFinite,
              stageSize.width > 0,
              stageSize.height > 0,
              recordingFrame.width.isFinite,
              recordingFrame.height.isFinite,
              recordingFrame.width > 0,
              recordingFrame.height > 0 else {
            return .center
        }

        let safeSourceSize = VideoCropSelection.safeSourceSize(sourceSize)
        let cropRect = cropSelection.pixelRect(in: safeSourceSize)
        guard cropRect.width > 0, cropRect.height > 0 else { return .center }

        let insetLayout = VideoInsetGeometry.layout(
            in: CGRect(origin: .zero, size: recordingFrame.size),
            amountRatio: VideoInsetGeometry.amountRatio(fromValue: inset.rounded()),
            balance: insetBalance
        )
        let contentRect = insetLayout.contentRect
        guard contentRect.width > 0, contentRect.height > 0 else { return .center }

        let scale = min(
            contentRect.width / max(cropRect.width, 1),
            contentRect.height / max(cropRect.height, 1)
        )
        let placedCropRect = CGRect(
            x: recordingFrame.minX + contentRect.minX + (contentRect.width - cropRect.width * scale) / 2,
            y: recordingFrame.minY + contentRect.minY + (contentRect.height - cropRect.height * scale) / 2,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        let focusPoint = CGPoint(
            x: placedCropRect.minX + (safeSourceSize.width * CGFloat(effect.focusX) - cropRect.minX) * scale,
            y: placedCropRect.minY + (safeSourceSize.height * CGFloat(effect.focusY) - cropRect.minY) * scale
        )

        return UnitPoint(
            x: min(max(focusPoint.x / stageSize.width, 0), 1),
            y: min(max(focusPoint.y / stageSize.height, 0), 1)
        )
    }

    static func previewSourceZoomTransform(effect: TimelineZoomEffect?, sourceDisplaySize: CGSize) -> CGAffineTransform {
        TimelineZoomCanvasTransform.transform(
            for: effect,
            in: CGRect(origin: .zero, size: sourceDisplaySize)
        )
    }

    static func previewFullStageZoomTransform(
        effect: TimelineZoomEffect?,
        stageSize: CGSize,
        recordingFrame: CGRect,
        sourceSize: CGSize,
        cropSelection: VideoCropSelection,
        inset: Double,
        insetBalance: VideoInsetBalance
    ) -> CGAffineTransform {
        guard let effect else { return .identity }
        let anchor = fullStageZoomAnchor(
            effect: effect,
            stageSize: stageSize,
            recordingFrame: recordingFrame,
            sourceSize: sourceSize,
            cropSelection: cropSelection,
            inset: inset,
            insetBalance: insetBalance
        )
        let normalizedEffect = TimelineZoomEffect(
            depth: effect.depth,
            focusX: Double(anchor.x),
            focusY: Double(anchor.y)
        )
        return TimelineZoomCanvasTransform.transform(
            for: normalizedEffect,
            in: CGRect(origin: .zero, size: stageSize)
        )
    }

    static func previewViewportZoomTransform(
        effect: TimelineZoomEffect?,
        viewportSize: CGSize,
        sourceSize: CGSize,
        cropSelection: VideoCropSelection
    ) -> CGAffineTransform {
        guard let effect,
              viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return .identity
        }

        let safeSourceSize = VideoCropSelection.safeSourceSize(sourceSize)
        let cropRect = cropSelection.pixelRect(in: safeSourceSize)
        guard cropRect.width > 0, cropRect.height > 0 else { return .identity }

        let scale = min(
            viewportSize.width / max(cropRect.width, 1),
            viewportSize.height / max(cropRect.height, 1)
        )
        let fittedCropSize = CGSize(width: cropRect.width * scale, height: cropRect.height * scale)
        let origin = CGPoint(
            x: (viewportSize.width - fittedCropSize.width) / 2,
            y: (viewportSize.height - fittedCropSize.height) / 2
        )
        let sourceFocus = CGPoint(
            x: safeSourceSize.width * CGFloat(effect.focusX),
            y: safeSourceSize.height * CGFloat(effect.focusY)
        )
        let viewportFocus = CGPoint(
            x: origin.x + (sourceFocus.x - cropRect.minX) * scale,
            y: origin.y + (sourceFocus.y - cropRect.minY) * scale
        )
        let normalizedEffect = TimelineZoomEffect(
            depth: effect.depth,
            focusX: Double(min(max(viewportFocus.x / viewportSize.width, 0), 1)),
            focusY: Double(min(max(viewportFocus.y / viewportSize.height, 0), 1))
        )

        return TimelineZoomCanvasTransform.transform(
            for: normalizedEffect,
            in: CGRect(origin: .zero, size: viewportSize)
        )
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
struct EmptyEditorState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 32))
                .foregroundStyle(Theme.accent)
                .frame(width: 66, height: 66)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.accent.opacity(0.22))
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
    var playback: VideoPlaybackController
    var edits: TimelineEditSnapshot
    var cursorTelemetryURL: URL?
    var cursorSettings: CursorOverlaySettings = .hidden
    var cropSelection: VideoCropSelection = .fullFrame
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
            let zoomEffect = edits.activeZoomEffect(at: playback.currentTime)
            let sourceZoomTransform = PreviewStageLayout.previewSourceZoomTransform(
                effect: zoomEffect,
                sourceDisplaySize: sourceDisplaySize
            )

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    NativeVideoPlayer(playback: playback, zoomTransform: sourceZoomTransform)
                        .frame(width: sourceDisplaySize.width, height: sourceDisplaySize.height)

                    sourceOverlays(size: sourceDisplaySize)
                        .frame(width: sourceDisplaySize.width, height: sourceDisplaySize.height)
                        .transformEffect(sourceZoomTransform)
                }
                    .frame(width: sourceDisplaySize.width, height: sourceDisplaySize.height)
                    .offset(contentOffset)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .background(letterboxFill.color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border)
            }
        }
        .onChange(of: edits) { _, newValue in
            playback.setTimelineEdits(newValue)
        }
        .onAppear { playback.setTimelineEdits(edits) }
    }

    private func sourceOverlays(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            CursorOverlayView(
                playback: playback,
                telemetryURL: cursorTelemetryURL,
                settings: cursorSettings
            )
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
    var screenPlayback: VideoPlaybackController
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
        VStack(alignment: .leading, spacing: 1) {
            ForEach(VideoPreviewAspectPreset.allCases) { option in
                Button {
                    selection = option
                    onSelect()
                } label: {
                    HStack(spacing: 12) {
                        PreviewAspectGlyph(preset: option, isSelected: selection == option)
                            .frame(width: 19, height: 19)
                        Text(option.ratioLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.95))
                            .frame(width: 38, alignment: .leading)
                            .lineLimit(1)
                        Text(option.menuLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selection == option ? Color.primary.opacity(0.92) : Theme.fgMuted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == option ? Color.white.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(7)
        .frame(width: 224)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.borderStrong, lineWidth: 1)
        }
    }
}

private struct PreviewAspectGlyph: View {
    var preset: VideoPreviewAspectPreset
    var isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let maxHeight = proxy.size.height
            let ratio = preset.menuAspectRatio
            let width = ratio >= 1 ? maxWidth : maxHeight * ratio
            let height = ratio >= 1 ? maxWidth / ratio : maxHeight
            let resolvedWidth = min(width, maxWidth)
            let resolvedHeight = min(height, maxHeight)

            RoundedRectangle(cornerRadius: min(resolvedWidth, resolvedHeight) * 0.22, style: .continuous)
                .fill(preset == .auto ? Color.clear : (isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.22)))
                .overlay {
                    if preset == .auto {
                        RoundedRectangle(cornerRadius: min(resolvedWidth, resolvedHeight) * 0.22, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.95 : 0.34), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    }
                }
                .frame(width: resolvedWidth, height: resolvedHeight)
                .frame(width: maxWidth, height: maxHeight, alignment: .center)
        }
    }
}

private struct CursorOverlayView: View {
    var playback: VideoPlaybackController
    var telemetryURL: URL?
    var settings: CursorOverlaySettings
    @State private var track: CursorTelemetryTrack?
    @State private var loadedTelemetryPath: String?

    var body: some View {
        GeometryReader { proxy in
            if let point = currentPoint(in: proxy.size) {
                let resolvedSettings = settings.clamped
                CursorGlyphView(
                    styleID: resolvedSettings.styleID,
                    scale: resolvedSettings.size,
                    glyphSize: cursorGlyphSize(in: proxy.size, settings: resolvedSettings),
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

    private func cursorGlyphSize(in size: CGSize, settings: CursorOverlaySettings) -> CGFloat? {
        guard size.width > 0,
              size.height > 0,
              let track else {
            return nil
        }

        let sourceRect = CGRect(
            origin: .zero,
            size: CGSize(width: CGFloat(max(track.width, 1)), height: CGFloat(max(track.height, 1)))
        )
        return CursorOverlayGeometry.glyphSize(
            contentRect: CGRect(origin: .zero, size: size),
            cropRect: sourceRect,
            settings: settings
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
    private let rootLayer = CALayer()
    private let contentLayer = CALayer()
    private let playbackLayer = AVPlayerLayer()
    private var zoomTransform = CGAffineTransform.identity

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    var playerLayer: AVPlayerLayer {
        playbackLayer
    }

    func update(player: AVPlayer?, zoomTransform: CGAffineTransform = .identity) {
        playbackLayer.player = player
        self.zoomTransform = Self.sanitized(zoomTransform)
        layoutPlayerLayers()
    }

    override func layout() {
        super.layout()
        layoutPlayerLayers()
    }

    private func configureLayers() {
        wantsLayer = true
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.masksToBounds = true
        rootLayer.isGeometryFlipped = true

        contentLayer.anchorPoint = .zero
        contentLayer.position = .zero
        contentLayer.isGeometryFlipped = true

        playbackLayer.videoGravity = .resizeAspect
        playbackLayer.backgroundColor = NSColor.clear.cgColor

        layer = rootLayer
        rootLayer.addSublayer(contentLayer)
        contentLayer.addSublayer(playbackLayer)
    }

    private func layoutPlayerLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let layerBounds = CGRect(origin: .zero, size: bounds.size)
        rootLayer.bounds = layerBounds
        contentLayer.bounds = layerBounds
        contentLayer.anchorPoint = .zero
        contentLayer.position = .zero
        contentLayer.setAffineTransform(zoomTransform)
        playbackLayer.frame = layerBounds

        CATransaction.commit()
    }

    private static func sanitized(_ transform: CGAffineTransform) -> CGAffineTransform {
        guard transform.a.isFinite,
              transform.b.isFinite,
              transform.c.isFinite,
              transform.d.isFinite,
              transform.tx.isFinite,
              transform.ty.isFinite else {
            return .identity
        }
        return transform
    }
}

struct NativeVideoPlayer: NSViewRepresentable {
    var playback: VideoPlaybackController
    var zoomTransform: CGAffineTransform = .identity

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.update(player: playback.player, zoomTransform: zoomTransform)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.update(player: playback.player, zoomTransform: zoomTransform)
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}

struct FacecamPlayerView: NSViewRepresentable {
    var player: AVPlayer?

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.update(player: player)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.update(player: player)
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}
