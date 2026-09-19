import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

/// A single drawable presents screen and camera together. Neither panel can lag
/// behind the other when geometry changes, and players survive layout switches.
struct SceneVideoPreview: NSViewRepresentable {
    var player: AVPlayer?
    var sourceSize: CGSize
    var cropSelection: VideoCropSelection
    var settings: SceneSettings
    var styling: VideoBackgroundStyling
    var edits: TimelineEditSnapshot
    var duration: Double
    var cursorTrack: CursorTelemetryTrack?
    var cursorSettings: CursorOverlaySettings
    var cameraSettings: FacecamSettings?
    var usesCameraLayout = false
    var facecamURL: URL?
    var facecamOffsetMs: Int?
    var onPreviewStatus: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) { context.coordinator.update(self) }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.stop()
        view.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        weak var view: MTKView?
        private var configuration: SceneVideoPreview?
        private var item: AVPlayerItem?
        private var output: AVPlayerItemVideoOutput?
        private var timer: Timer?
        private var metadataTask: Task<Void, Never>?
        private var frame: CVPixelBuffer?
        private var transform = CGAffineTransform.identity
        private var metadataReady = false
        private var status: String?
        private var dirty = true
        private var inFlight = false
        private var generation = 0
        private let compositor = VideoBackgroundCompositor()
        private let renderQueue = DispatchQueue(label: "open-recorder.preview-render", qos: .userInteractive)
        private var context: CIContext?
        private var commandQueue: MTLCommandQueue?
        private var plan = TimelineExportEditPlan(segments: [], outputDuration: 0)
        private var cameraPlayer: AVPlayer?
        private var cameraOutput: AVPlayerItemVideoOutput?
        private var cameraURL: URL?
        private var cameraMetadataTask: Task<Void, Never>?
        private var cameraTransform = CGAffineTransform.identity
        private var cameraSize = CGSize.zero
        private var cameraFrame: CVPixelBuffer?
        private var cameraDuration = 0.0
        private var cameraIsVisible = false
        private var cameraSeekPending = false
        private var cameraRequestedTime = -1.0
        private var lastSourceTime = -1.0
        private var lastPresentation: CameraLayoutPresentation?
        private var liveMotion = CameraLayoutLiveMotion()
        private var liveSourceTime: Double?
        private var pendingLiveEdit = false
        private var animateLiveEdit = false

        func start() {
            if let device = view?.device {
                context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
                commandQueue = device.makeCommandQueue()
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }

        func stop() {
            generation += 1
            timer?.invalidate(); timer = nil
            metadataTask?.cancel(); metadataTask = nil
            if let output { item?.remove(output) }
            item = nil; output = nil; frame = nil
            stopCamera()
        }

        private func stopCamera() {
            cameraMetadataTask?.cancel(); cameraMetadataTask = nil
            cameraPlayer?.pause()
            if let cameraOutput { cameraPlayer?.currentItem?.remove(cameraOutput) }
            cameraPlayer = nil; cameraOutput = nil; cameraFrame = nil; cameraURL = nil
            cameraSize = .zero; cameraDuration = 0; cameraIsVisible = false; cameraSeekPending = false
            cameraRequestedTime = -1
        }

        func update(_ next: SceneVideoPreview) {
            let previous = configuration
            let editsChanged = previous?.edits != next.edits || previous?.cameraSettings != next.cameraSettings
            if editsChanged || previous?.duration != next.duration {
                plan = TimelineExportEditPlan.build(duration: next.duration, edits: next.edits)
            }
            if let previous, editsChanged, next.usesCameraLayout {
                let time = next.player?.currentTime().seconds ?? 0
                let before = previous.edits.activeCameraSettings(at: time, duration: previous.duration, fallback: previous.cameraSettings)
                let after = next.edits.activeCameraSettings(at: time, duration: next.duration, fallback: next.cameraSettings)
                if before != after {
                    pendingLiveEdit = true
                    animateLiveEdit = before?.resolvedLayout != after?.resolvedLayout
                        || before?.resolvedScreenFit != after?.resolvedScreenFit
                        || before?.resolvedCameraOnLeft != after?.resolvedCameraOnLeft
                        || before?.resolvedAnchor != after?.resolvedAnchor
                        || before?.normalizedShape != after?.normalizedShape
                        || before?.enabled != after?.enabled
                        || before?.keepsFaceCentered != after?.keepsFaceCentered
                    liveSourceTime = time
                }
            }
            if let previous, next.usesCameraLayout,
               previous.styling != next.styling || previous.cropSelection != next.cropSelection || previous.sourceSize != next.sourceSize {
                pendingLiveEdit = true
                animateLiveEdit = false
                liveSourceTime = next.player?.currentTime().seconds ?? 0
            }
            configuration = next
            guard view?.device != nil else {
                report("Preview needs Metal to render this layout.")
                return
            }
            if cameraURL != next.facecamURL { loadCamera(next.facecamURL) }
            dirty = true
            guard item !== next.player?.currentItem else { tick(); return }
            generation += 1
            if let output { item?.remove(output) }
            item = next.player?.currentItem
            frame = nil
            lastPresentation = nil; liveMotion = CameraLayoutLiveMotion(); liveSourceTime = nil
            metadataReady = false
            transform = .identity
            let newOutput = Self.videoOutput()
            output = newOutput
            item?.add(newOutput)
            metadataTask?.cancel()
            let expected = item
            metadataTask = Task { [weak self] in
                guard let expected else { return }
                do {
                    guard let track = try await expected.asset.loadTracks(withMediaType: .video).first else { throw VideoExportRendererError.missingVideoTrack }
                    let preferred = try await track.load(.preferredTransform)
                    let size = try await track.load(.naturalSize)
                    guard !Task.isCancelled, let self, self.item === expected else { return }
                    let natural = CGRect(origin: .zero, size: size).applying(preferred)
                    self.transform = preferred.concatenating(CGAffineTransform(translationX: -natural.minX, y: -natural.minY))
                    self.metadataReady = true
                    self.dirty = true
                    self.tick()
                } catch {
                    guard !Task.isCancelled, let self, self.item === expected else { return }
                    self.report("Preview could not load this video.")
                }
            }
            tick()
        }

        private static func videoOutput() -> AVPlayerItemVideoOutput {
            AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ])
        }

        private func loadCamera(_ url: URL?) {
            stopCamera()
            guard let url else { return }
            cameraURL = url
            let item = AVPlayerItem(url: url)
            let output = Self.videoOutput()
            item.add(output)
            cameraOutput = output
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.automaticallyWaitsToMinimizeStalling = false
            cameraPlayer = player
            cameraMetadataTask = Task { [weak self] in
                guard let track = try? await item.asset.loadTracks(withMediaType: .video).first,
                      let preferred = try? await track.load(.preferredTransform),
                      let size = try? await track.load(.naturalSize),
                      let duration = try? await item.asset.load(.duration),
                      !Task.isCancelled, let self, self.cameraPlayer === player else { return }
                let rect = CGRect(origin: .zero, size: size).applying(preferred)
                self.cameraTransform = preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                self.cameraSize = rect.size
                self.cameraDuration = duration.seconds
                self.dirty = true
                self.tick()
            }
        }

        private func syncCamera(sourceTime: Double, rate: Float) {
            guard let configuration, let cameraPlayer, let cameraOutput, cameraSize != .zero else { return }
            let target = sourceTime - Double(configuration.facecamOffsetMs ?? 0) / 1000
            cameraIsVisible = target >= 0 && target <= cameraDuration
            guard cameraIsVisible else { cameraPlayer.pause(); return }
            let current = cameraPlayer.currentTime().seconds
            let pausedSeek = rate == 0 && abs(target - cameraRequestedTime) > 0.001
            if !cameraSeekPending && (pausedSeek || !current.isFinite || abs(current - target) > 0.12) {
                cameraSeekPending = true
                cameraRequestedTime = target
                cameraPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak cameraPlayer] _ in
                    Task { @MainActor in
                        guard let self, self.cameraPlayer === cameraPlayer else { return }
                        self.cameraSeekPending = false
                        self.dirty = true
                    }
                }
            }
            if cameraPlayer.rate != rate { cameraPlayer.rate = rate }
            let cameraTime = cameraPlayer.currentTime()
            if cameraOutput.hasNewPixelBuffer(forItemTime: cameraTime),
               let next = cameraOutput.copyPixelBuffer(forItemTime: cameraTime, itemTimeForDisplay: nil) {
                cameraFrame = next
                dirty = true
            }
        }

        private func tick() {
            guard let configuration, let output, let player = configuration.player else { return }
            let time = player.currentTime()
            guard time.isNumeric else { return }
            syncCamera(sourceTime: time.seconds, rate: player.rate)
            if let liveSourceTime, abs(time.seconds - liveSourceTime) > 0.04 {
                self.liveSourceTime = nil
                pendingLiveEdit = false
            }
            if time.seconds != lastSourceTime { dirty = true; lastSourceTime = time.seconds }
            if output.hasNewPixelBuffer(forItemTime: time),
               let next = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                frame = next
                dirty = true
            }
            if liveMotion.isAnimating(at: CACurrentMediaTime()) { dirty = true }
            guard dirty, !inFlight, frame != nil else { return }
            view?.needsDisplay = true
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            dirty = true
            lastPresentation = nil
            if liveSourceTime != nil { pendingLiveEdit = true; animateLiveEdit = false }
        }

        func draw(in view: MTKView) {
            guard dirty, !inFlight, metadataReady, let configuration, let frame, let drawable = view.currentDrawable,
                  let context, let buffer = commandQueue?.makeCommandBuffer() else { return }
            let canvas = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            guard canvas.width > 0, canvas.height > 0, configuration.sourceSize.width > 0 else { return }
            let sourceTime = configuration.player?.currentTime().seconds ?? 0
            let time = plan.outputTime(forSourceTime: sourceTime) ?? 0
            let crop = configuration.cropSelection.pixelRect(in: configuration.sourceSize)
            var presentation: CameraLayoutPresentation?
            if configuration.usesCameraLayout {
                let clock = CACurrentMediaTime()
                let timelinePose = CameraLayoutMotion.presentation(edits: configuration.edits, plan: plan, time: time,
                    duration: configuration.duration, fallback: configuration.cameraSettings, canvas: canvas, crop: crop, styling: configuration.styling)
                if pendingLiveEdit {
                    let settings = configuration.edits.activeCameraSettings(at: sourceTime, duration: configuration.duration, fallback: configuration.cameraSettings)
                    let target = CameraLayoutPresentation.layout(settings, canvas: canvas, crop: crop, styling: configuration.styling)
                    liveMotion.retarget(lastPresentation ?? timelinePose, at: clock, animated: false)
                    liveMotion.retarget(target, at: clock, animated: animateLiveEdit && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                        transition: settings?.resolvedLayoutTransition ?? .init())
                    pendingLiveEdit = false
                }
                presentation = liveSourceTime == nil ? timelinePose : (liveMotion.value(at: clock) ?? timelinePose)
                lastPresentation = presentation
            }
            let instruction = VideoBackgroundCompositionInstruction(
                timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: plan.outputDuration, preferredTimescale: 600)),
                trackID: 1, facecamTrackID: cameraFrame == nil ? nil : 2,
                styling: configuration.styling, scene: configuration.settings,
                preferredTransform: transform, normalizedSize: configuration.sourceSize,
                facecamPreferredTransform: cameraTransform, facecamNormalizedSize: cameraSize,
                cropRect: crop, renderSize: canvas, edits: configuration.edits, editPlan: plan,
                cursorTrack: configuration.cursorTrack, cursorSettings: configuration.cursorSettings,
                facecamFallbackSettings: configuration.cameraSettings,
                cameraLayoutEnabled: configuration.usesCameraLayout, cameraPresentation: presentation)
            let job = RenderJob(source: frame, facecam: cameraIsVisible ? cameraFrame : nil,
                instruction: instruction, time: time, drawable: drawable, buffer: buffer, context: context)
            let generation = generation
            let compositor = compositor
            inFlight = true
            dirty = false
            renderQueue.async { [weak self] in
                var failure: String?
                autoreleasepool {
                    do {
                        let image = try compositor.makeComposedImage(source: job.source, facecam: job.facecam,
                            instruction: job.instruction, compositionTime: job.time)
                        SceneMetalDisplay.render(image, context: job.context, texture: job.drawable.texture, commandBuffer: job.buffer)
                        job.buffer.present(job.drawable)
                        job.buffer.commit()
                        job.buffer.waitUntilCompleted()
                    } catch { failure = "Preview could not render this frame." }
                }
                let message = failure
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inFlight = false
                    guard self.generation == generation else { return }
                    self.report(message)
                    self.tick()
                }
            }
        }

        private func report(_ message: String?) {
            guard status != message else { return }
            status = message
            let callback = configuration?.onPreviewStatus
            Task { @MainActor in callback?(message) }
        }
    }
}

private final class RenderJob: @unchecked Sendable {
    let source: CVPixelBuffer
    let facecam: CVPixelBuffer?
    let instruction: VideoBackgroundCompositionInstruction
    let time: Double
    let drawable: CAMetalDrawable
    let buffer: MTLCommandBuffer
    let context: CIContext

    init(source: CVPixelBuffer, facecam: CVPixelBuffer?, instruction: VideoBackgroundCompositionInstruction,
         time: Double, drawable: CAMetalDrawable, buffer: MTLCommandBuffer, context: CIContext) {
        self.source = source; self.facecam = facecam; self.instruction = instruction
        self.time = time; self.drawable = drawable; self.buffer = buffer; self.context = context
    }
}

enum SceneMetalDisplay {
    /// Core Image's native orientation presents upright in the macOS drawable.
    static func render(_ image: CIImage, context: CIContext, texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let bounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        context.render(image, to: texture, commandBuffer: commandBuffer, bounds: bounds,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}
