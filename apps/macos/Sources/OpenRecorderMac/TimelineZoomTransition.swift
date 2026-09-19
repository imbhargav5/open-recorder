import Foundation
import Observation

/// Optional per-zoom overrides. Legacy regions retain their saved preset/path.
struct TimelineZoomTransition: Codable, Hashable {
    var enterDuration = 0.45
    var exitDuration = 0.35
    var motion = CameraLayoutTransition.Motion.ease
    var easing = TimelineZoomEasing.smoothstep
    var bounce = 0.25

    static func defaults(for preset: TimelineZoomAnimationPreset) -> Self {
        let config = preset.configuration
        return Self(enterDuration: config.rampInSeconds, exitDuration: config.rampOutSeconds,
                    easing: config.easing)
    }

    var clamped: Self {
        var next = self
        next.enterDuration = sceneClamp(enterDuration, 0...3, fallback: 0.45)
        next.exitDuration = sceneClamp(exitDuration, 0...3, fallback: 0.35)
        next.bounce = sceneClamp(bounce, 0...1, fallback: 0.25)
        return next
    }

    func durations(in span: TimelineSpan) -> (enter: Double, exit: Double) {
        let value = clamped
        let scale = min(1, max(0, span.duration) / max(0.001, value.enterDuration + value.exitDuration))
        return (value.enterDuration * scale, value.exitDuration * scale)
    }

    func progress(_ fraction: Double) -> Double {
        let t = sceneClamp(fraction, 0...1)
        guard t > 0, t < 1 else { return t }
        guard motion == .spring else { return easing.value(t) }
        // Zoom uses a duration-based spring. The faster layout spring spent most
        // of this interval already at rest, making identical times feel shorter.
        let bounce = clamped.bounce
        let damping = 1 - 0.55 * bounce
        let frequency = 6 + 2 * bounce
        let response: Double
        if damping >= 0.999 {
            response = 1 - (1 + frequency * t) * exp(-frequency * t)
        } else {
            let oscillation = frequency * sqrt(1 - damping * damping)
            response = 1 - exp(-damping * frequency * t)
                * (cos(oscillation * t) + damping * frequency / oscillation * sin(oscillation * t))
        }
        // Finish at the exact endpoint with zero velocity, regardless of bounce.
        let settle = CameraLayoutMotion.ease((t - 0.75) / 0.25)
        let settled = response + (1 - response) * settle
        // Zoom cannot shrink below 1x. Unbounded overshoot gets clipped there,
        // making zoom-out appear finished halfway through its duration. Round
        // that rebound inside the endpoint range, with a smooth vanishing tail.
        let residual = 0.08 * pow(sin(.pi * t), 2)
        return max(0, 1 - sqrt(pow(1 - settled, 2) + residual * residual))
    }

    func envelope(in span: TimelineSpan, at time: Double) -> Double {
        guard span.contains(time) else { return 0 }
        let ramps = durations(in: span)
        if ramps.enter > 0, time < span.start + ramps.enter {
            return progress((time - span.start) / ramps.enter)
        }
        if ramps.exit > 0, time > span.end - ramps.exit {
            return max(0, 1 - progress((time - (span.end - ramps.exit)) / ramps.exit))
        }
        return 1
    }

    /// Keep the generated pan and focus keyframes; retime only their surrounding
    /// entrance/exit and the intervening hold to the requested playback durations.
    func effect(path: AutoZoomCameraPath, span: TimelineSpan, at time: Double) -> TimelineZoomEffect? {
        guard path.keyframes.count >= 3 else { return path.effect(at: time) }
        let frames = path.keyframes, last = frames.count - 1
        let ramps = durations(in: span)
        let enterEnd = span.start + ramps.enter, exitStart = span.end - ramps.exit
        let mapped: Double
        if ramps.enter > 0, time < enterEnd {
            mapped = frames[0].time + (frames[1].time - frames[0].time) * (time - span.start) / ramps.enter
        } else if ramps.exit > 0, time > exitStart {
            mapped = frames[last - 1].time + (frames[last].time - frames[last - 1].time) * (time - exitStart) / ramps.exit
        } else {
            let fraction = (time - enterEnd) / max(0.001, exitStart - enterEnd)
            mapped = frames[1].time + (frames[last - 1].time - frames[1].time) * fraction
        }
        return path.effect(at: mapped, boundaryProgress: progress)
    }
}

/// Separate from camera-layout transitions, so neither clipboard can overwrite the other.
@MainActor @Observable
final class ZoomTransitionStore {
    static let shared = ZoomTransitionStore()
    private(set) var copiedTransition: TimelineZoomTransition?

    func copy(_ transition: TimelineZoomTransition) {
        copiedTransition = transition.clamped
    }
}
