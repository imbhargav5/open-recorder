import CoreGraphics
import Foundation

/// One presentation value drives both panels, including cropping and decorations.
/// Preview and export sample exactly the same timeline motion.
struct CameraLayoutPresentation: Equatable, Sendable {
    var screen: CGRect
    var camera: CGRect
    var screenRadius: CGFloat
    var cameraRadius: CGFloat
    var borderWidth: CGFloat
    var screenOpacity: CGFloat
    var cameraOpacity: CGFloat
    var faceCentering: CGFloat
    var overlayAmount: CGFloat
    var transitionActive = false
    var transitionBlur: CGFloat = 0
    var transitionFade: CGFloat = 0

    static func layout(_ settings: FacecamSettings?, canvas: CGSize, crop: CGRect,
                       styling: VideoBackgroundStyling) -> Self {
        let settings = (settings ?? defaultFacecamSettings(enabled: false)).clamped
        let base = min(canvas.width, canvas.height)
        let pad = styling.paddingRatio * base
        let inner = CGSize(width: max(2, canvas.width - 2 * pad), height: max(2, canvas.height - 2 * pad))
        let fitted = PreviewStageLayout.fittedSize(forAspectRatio: crop.width / max(1, crop.height), in: inner)
        let regularScreen = CGRect(x: (canvas.width - fitted.width) / 2, y: (canvas.height - fitted.height) / 2,
                                   width: fitted.width, height: fitted.height)
        let isOverlay = !settings.enabled || settings.resolvedLayout == .overlay
        let panels = CameraLayoutGeometry.frames(in: canvas, screenAspectRatio: crop.width / max(1, crop.height), settings: settings)
        var visible = settings
        visible.enabled = true
        let camera = FacecamOverlayLayout.frame(in: canvas, settings: visible)
        let scale = CameraLayoutGeometry.decorationScale(in: canvas, settings: settings)
        let radius = settings.isCircle ? min(camera.width, camera.height) / 2 : CGFloat(settings.cornerRadius) * scale
        return Self(screen: isOverlay ? regularScreen : (panels.screen.isEmpty ? regularScreen : panels.screen),
                    camera: camera,
                    screenRadius: isOverlay
                        ? (settings.enabled ? settings.overlayScreenCornerRadius.map { CGFloat($0) } : nil) ?? styling.borderRadiusRatio * base
                        : CameraLayoutGeometry.screenCornerRadius(in: canvas, settings: settings),
                    cameraRadius: min(radius, min(camera.width, camera.height) / 2),
                    borderWidth: CGFloat(settings.borderWidth) * scale,
                    screenOpacity: settings.enabled && settings.resolvedLayout == .cameraOnly ? 0 : 1,
                    cameraOpacity: settings.enabled ? 1 : 0,
                    faceCentering: settings.keepsFaceCentered ? 1 : 0,
                    overlayAmount: isOverlay ? 1 : 0)
    }

    func interpolated(to other: Self, progress: Double) -> Self {
        if progress == 0 { return self }
        if progress == 1 { return other }
        let t = CGFloat(progress)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        func rect(_ a: CGRect, _ b: CGRect) -> CGRect {
            CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY),
                   width: max(2, mix(a.width, b.width)), height: max(2, mix(a.height, b.height)))
        }
        return Self(screen: rect(screen, other.screen), camera: rect(camera, other.camera),
                    screenRadius: max(0, mix(screenRadius, other.screenRadius)), cameraRadius: max(0, mix(cameraRadius, other.cameraRadius)),
                    borderWidth: max(0, mix(borderWidth, other.borderWidth)), screenOpacity: min(1, max(0, mix(screenOpacity, other.screenOpacity))),
                    cameraOpacity: min(1, max(0, mix(cameraOpacity, other.cameraOpacity))), faceCentering: min(1, max(0, mix(faceCentering, other.faceCentering))),
                    overlayAmount: min(1, max(0, mix(overlayAmount, other.overlayAmount))),
                    transitionActive: transitionActive || other.transitionActive,
                    transitionBlur: mix(transitionBlur, other.transitionBlur), transitionFade: mix(transitionFade, other.transitionFade))
    }
}

enum CameraLayoutMotion {
    static let duration = CameraLayoutTransition().duration

    static func sample(from start: CameraLayoutPresentation, to target: CameraLayoutPresentation,
                       fraction: Double, transition: CameraLayoutTransition, effectiveDuration: Double? = nil) -> CameraLayoutPresentation {
        guard fraction > 0 else { return start }
        guard fraction < 1 else { return target }
        let transition = transition.clamped
        var result = start.interpolated(to: target, progress: transition.progress(at: fraction))
        result.transitionActive = true
        let pulse = CGFloat(pow(sin(.pi * fraction), 2))
        let interval = effectiveDuration ?? transition.duration
        let elapsed = fraction * interval
        // Carry an interrupted live blur briefly, then clear it independently of
        // the new layout's spring settling. It must never leak past the boundary.
        let carry = 1 - ease(elapsed / max(0.001, min(0.12, interval)))
        result.transitionBlur = CGFloat(transition.blur * transition.blurEnvelope(at: elapsed, transitionDuration: interval))
            + start.transitionBlur * CGFloat(carry)
        result.transitionFade += CGFloat(transition.fade) * pulse
        return result
    }

    static func ease(_ progress: Double) -> Double {
        let t = max(0, min(1, progress))
        return t * t * t * (10 + t * (-15 + 6 * t))
    }

    static func presentation(edits: TimelineEditSnapshot, plan: TimelineExportEditPlan, time: Double,
                             duration: Double, fallback: FacecamSettings?, canvas: CGSize, crop: CGRect,
                             styling: VideoBackgroundStyling) -> CameraLayoutPresentation {
        let sourceTime = plan.sourceTime(forOutputTime: time) ?? time
        let settings = edits.activeCameraSettings(at: sourceTime, duration: duration, fallback: fallback)
        let target = CameraLayoutPresentation.layout(settings, canvas: canvas, crop: crop, styling: styling)
        guard !plan.segments.isEmpty else { return target }
        // Output spans account for cuts and speed changes. Transitions last the same
        // amount of playback time regardless of the source clip's speed.
        let fragments = edits.resolvedCameraClips(duration: duration, fallback: fallback).flatMap { clip in
            plan.outputSpans(forSourceSpan: clip.span).map { (span: $0, settings: clip.settings) }
        }.sorted { $0.span.start < $1.span.start }
        var spans: [(span: TimelineSpan, settings: FacecamSettings)] = []
        for fragment in fragments {
            if let last = spans.last, last.settings == fragment.settings,
               abs(last.span.end - fragment.span.start) < 0.001 {
                spans[spans.count - 1].span.end = fragment.span.end
            } else {
                spans.append(fragment)
            }
        }
        guard let index = spans.lastIndex(where: { time >= $0.span.start && time < $0.span.end }), index > 0 else { return target }
        let current = spans[index]
        let previous = spans[index - 1]
        guard abs(previous.span.end - current.span.start) < 0.001 else { return target }
        let transition = current.settings.resolvedLayoutTransition
        let interval = min(transition.duration, current.span.duration)
        guard interval > 0, time < current.span.start + interval else { return target }
        let start = CameraLayoutPresentation.layout(previous.settings, canvas: canvas, crop: crop, styling: styling)
        return sample(from: start, to: target, fraction: (time - current.span.start) / interval, transition: transition, effectiveDuration: interval)
    }
}

/// Retarget from the frame already on screen, never from an obsolete layout.
/// Interactive slider updates are presented immediately as one atomic panel pair.
struct CameraLayoutLiveMotion {
    private var start: CameraLayoutPresentation?
    private(set) var target: CameraLayoutPresentation?
    private var startTime = 0.0
    private var interval = 0.0
    private var transition = CameraLayoutTransition()

    mutating func retarget(_ next: CameraLayoutPresentation, at time: Double, animated: Bool, transition: CameraLayoutTransition = .init()) {
        guard target != next else { return }
        let visible = value(at: time) ?? next
        start = visible
        target = next
        startTime = time
        self.transition = transition.clamped
        interval = animated ? self.transition.duration : 0
    }

    func value(at time: Double) -> CameraLayoutPresentation? {
        guard let target, let start else { return target }
        guard interval > 0 else { return target }
        return CameraLayoutMotion.sample(from: start, to: target, fraction: (time - startTime) / interval, transition: transition, effectiveDuration: interval)
    }

    func isAnimating(at time: Double) -> Bool { interval > 0 && time < startTime + interval }
}
