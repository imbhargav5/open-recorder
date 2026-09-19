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
        motion == .spring
            ? CameraLayoutTransition(motion: .spring, bounce: clamped.bounce).progress(at: fraction)
            : easing.value(fraction)
    }

    func envelope(in span: TimelineSpan, at time: Double) -> Double {
        guard span.contains(time) else { return 0 }
        let ramps = durations(in: span)
        if ramps.enter > 0, time < span.start + ramps.enter {
            return progress((time - span.start) / ramps.enter)
        }
        if ramps.exit > 0, time > span.end - ramps.exit {
            return max(0, progress((span.end - time) / ramps.exit))
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
