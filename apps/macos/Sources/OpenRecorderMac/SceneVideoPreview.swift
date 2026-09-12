import AVFoundation
import CoreImage
import MetalKit
import SwiftUI

/// Uses the same compositor as export, with the existing player's clock and decoded frames.
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

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(self)
    }

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
        private var frameTime = 0.0
        private var transform = CGAffineTransform.identity
        private var metadataReady = false
        private var status: String?
        private var dirty = true
        private let compositor = VideoBackgroundCompositor()
        private var context: CIContext?
        private var commandQueue: MTLCommandQueue?

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
            timer?.invalidate(); timer = nil
            metadataTask?.cancel(); metadataTask = nil
            if let output { item?.remove(output) }
            item = nil; output = nil; frame = nil
        }

        func update(_ next: SceneVideoPreview) {
            configuration = next
            guard view?.device != nil else {
                report("Scene preview needs Metal. Reset Scene to use the standard preview.")
                return
            }
            dirty = true
            guard item !== next.player?.currentItem else { tick(); return }
            if let output { item?.remove(output) }
            item = next.player?.currentItem
            frame = nil
            metadataReady = false
            transform = .identity
            let newOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ])
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
                    self.report("Scene preview could not load this video. Reset Scene to use the standard preview.")
                }
            }
            tick()
        }

        private func tick() {
            guard let configuration, let output, let player = configuration.player else { return }
            let time = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time) {
                var displayTime = CMTime.zero
                if let next = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayTime) {
                    frame = next
                    frameTime = displayTime.isNumeric ? displayTime.seconds : time.seconds
                    dirty = true
                }
            }
            guard dirty, frame != nil else { return }
            view?.needsDisplay = true
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { dirty = true }

        func draw(in view: MTKView) {
            guard dirty, metadataReady, let configuration, let frame, let drawable = view.currentDrawable,
                  let context, let buffer = commandQueue?.makeCommandBuffer() else { return }
            let canvas = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            guard canvas.width > 0, canvas.height > 0, configuration.sourceSize.width > 0 else { return }
            let plan = TimelineExportEditPlan.build(duration: configuration.duration, edits: configuration.edits)
            let time = plan.outputTime(forSourceTime: frameTime) ?? 0
            let instruction = VideoBackgroundCompositionInstruction(
                timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: plan.outputDuration, preferredTimescale: 600)),
                trackID: 1, styling: configuration.styling, scene: configuration.settings,
                preferredTransform: transform, normalizedSize: configuration.sourceSize,
                cropRect: configuration.cropSelection.pixelRect(in: configuration.sourceSize),
                renderSize: canvas, edits: configuration.edits, editPlan: plan,
                cursorTrack: configuration.cursorTrack, cursorSettings: configuration.cursorSettings,
                facecamFallbackSettings: configuration.cameraSettings)
            do {
                let image = try compositor.makeComposedImage(source: frame, facecam: nil, instruction: instruction, compositionTime: time)
                SceneMetalDisplay.render(image, context: context, texture: drawable.texture, commandBuffer: buffer)
                buffer.present(drawable)
                buffer.commit()
                dirty = false
                report(nil)
            } catch {
                report("Scene preview could not render this frame. Reset Scene to use the standard preview.")
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

enum SceneMetalDisplay {
    /// Drawable textures scan from the top left; Core Image geometry uses the bottom left.
    static func render(_ image: CIImage, context: CIContext, texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let bounds = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        let displayed = image.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height))
        context.render(displayed, to: texture, commandBuffer: commandBuffer, bounds: bounds,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}
