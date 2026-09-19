import Foundation

/// Stored on the incoming camera segment; absent values preserve existing projects.
struct CameraLayoutTransition: Codable, Hashable, Sendable {
    enum Motion: String, Codable, CaseIterable, Identifiable {
        case ease, spring
        var id: String { rawValue }
        var title: String { self == .ease ? "Ease" : "Spring" }
    }
    enum Easing: String, Codable, CaseIterable, Identifiable {
        case smooth, easeIn, easeOut, linear
        var id: String { rawValue }
        var title: String {
            switch self {
            case .smooth: return "Ease in & out"
            case .easeIn: return "Ease in"
            case .easeOut: return "Ease out"
            case .linear: return "Linear"
            }
        }
    }
    var duration: Double = 0.42
    var motion: Motion = .ease
    var easing: Easing = .smooth
    var bounce: Double = 0.25
    var blur: Double = 0
    var fade: Double = 0

    var clamped: Self {
        var result = self
        result.duration = CameraLayoutGeometry.clamp(duration, to: 0...2, fallback: 0.42)
        result.bounce = CameraLayoutGeometry.clamp(bounce, to: 0...1, fallback: 0.25)
        result.blur = CameraLayoutGeometry.clamp(blur, to: 0...1, fallback: 0)
        result.fade = CameraLayoutGeometry.clamp(fade, to: 0...1, fallback: 0)
        return result
    }

    func progress(at fraction: Double) -> Double {
        let t = max(0, min(1, fraction))
        guard t > 0, t < 1 else { return t }
        switch motion {
        case .ease:
            switch easing {
            case .smooth: return CameraLayoutMotion.ease(t)
            case .easeIn: return t * t * t
            case .easeOut: return 1 - pow(1 - t, 3)
            case .linear: return t
            }
        case .spring:
            // A damped spring with zero initial velocity. Settle its tiny tail
            // smoothly so a timeline boundary always reaches the exact destination.
            let damping = 1 - 0.55 * clamped.bounce
            let frequency = 12.0
            let response: Double
            if damping >= 0.999 {
                response = 1 - (1 + frequency * t) * exp(-frequency * t)
            } else {
                let oscillation = frequency * sqrt(1 - damping * damping)
                response = 1 - exp(-damping * frequency * t)
                    * (cos(oscillation * t) + damping * frequency / oscillation * sin(oscillation * t))
            }
            let settle = CameraLayoutMotion.ease((t - 0.7) / 0.3)
            return response + (1 - response) * settle
        }
    }
}
