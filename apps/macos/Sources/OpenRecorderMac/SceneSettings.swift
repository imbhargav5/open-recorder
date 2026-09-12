import CoreGraphics
import Foundation

struct ScenePose: Codable, Equatable, Hashable {
    var tiltX = 0.0
    var tiltY = 0.0
    var rotation = 0.0
    var scale = 1.0
    var x = 0.0
    var y = 0.0
    var perspective = 0.5

    static let identity = ScenePose()

    var clamped: Self {
        Self(tiltX: sceneClamp(tiltX, -60...60), tiltY: sceneClamp(tiltY, -60...60),
             rotation: sceneClamp(rotation, -180...180), scale: sceneClamp(scale, 0.25...2, fallback: 1),
             x: sceneClamp(x, -1...1), y: sceneClamp(y, -1...1),
             perspective: sceneClamp(perspective, 0...1, fallback: 0.5))
    }

    var isIdentity: Bool {
        let p = clamped
        return p.tiltX == 0 && p.tiltY == 0 && p.rotation == 0 && p.scale == 1 && p.x == 0 && p.y == 0
    }

    static func interpolate(_ start: Self, _ end: Self, progress: Double) -> Self {
        let a = start.clamped, b = end.clamped, t = sceneClamp(progress, 0...1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return Self(tiltX: mix(a.tiltX, b.tiltX), tiltY: mix(a.tiltY, b.tiltY),
                    rotation: mix(a.rotation, b.rotation), scale: mix(a.scale, b.scale),
                    x: mix(a.x, b.x), y: mix(a.y, b.y), perspective: mix(a.perspective, b.perspective))
    }
}

enum ScenePosePreset: String, CaseIterable, Identifiable {
    case flat = "Flat", left = "Tilt Left", right = "Tilt Right", elevated = "Elevated"
    var id: String { rawValue }
    var pose: ScenePose {
        switch self {
        case .flat: .identity
        case .left: ScenePose(tiltX: 8, tiltY: -24, rotation: -4, scale: 0.85)
        case .right: ScenePose(tiltX: 8, tiltY: 24, rotation: 4, scale: 0.85)
        case .elevated: ScenePose(tiltX: 28, tiltY: -12, rotation: -6, scale: 0.85)
        }
    }
}

enum MockupStyle: String, Codable, CaseIterable, Identifiable {
    case none = "None", browser = "Browser", window = "Desktop Window", phone = "Phone", tablet = "Tablet"
    var id: String { rawValue }
}

enum SceneEasing: String, Codable, CaseIterable, Identifiable {
    case linear = "Linear", easeIn = "Ease In", easeOut = "Ease Out", easeInOut = "Ease In Out"
    var id: String { rawValue }
    func evaluate(_ progress: Double) -> Double {
        let t = sceneClamp(progress, 0...1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t * t * (3 - 2 * t)
        }
    }
}

enum SceneMotionPreset: String, CaseIterable, Identifiable {
    case pushIn = "Push In", pullOut = "Pull Out", tiltReveal = "Tilt Reveal", sideSweep = "Side Sweep"
    var id: String { rawValue }
    var poses: (ScenePose, ScenePose) {
        switch self {
        case .pushIn: (ScenePose(scale: 0.75), ScenePose(scale: 1))
        case .pullOut: (ScenePose(scale: 1), ScenePose(scale: 0.75))
        case .tiltReveal: (ScenePosePreset.left.pose, ScenePose(scale: 0.95))
        case .sideSweep: (ScenePose(tiltY: -20, scale: 0.8, x: -0.12), ScenePose(tiltY: 20, scale: 0.8, x: 0.12))
        }
    }
}

struct SceneMotion: Codable, Equatable, Hashable {
    var enabled = false
    var startTime = 0.0
    var endTime = 3.0
    var startPose = ScenePose(scale: 0.8)
    var endPose = ScenePose.identity
    var easing = SceneEasing.easeInOut

    func clamped(to duration: Double) -> Self {
        var next = self
        let duration = sceneClamp(duration, 0...86400)
        let minimum = min(0.05, duration)
        next.startTime = sceneClamp(startTime, 0...max(0, duration - minimum))
        next.endTime = sceneClamp(endTime, (next.startTime + minimum)...duration, fallback: duration)
        next.startPose = startPose.clamped
        next.endPose = endPose.clamped
        return next
    }

    func pose(at time: Double) -> ScenePose {
        let progress = (time - startTime) / max(0.001, endTime - startTime)
        return .interpolate(startPose, endPose, progress: easing.evaluate(progress))
    }
}

struct SceneSettings: Codable, Equatable, Hashable {
    var pose = ScenePose.identity
    var mockup = MockupStyle.none
    var darkMockup = true
    var edgeHighlight = false
    var motion = SceneMotion()
    var imageDuration = 3.0

    static let identity = SceneSettings()
    var isActive: Bool { !pose.isIdentity || mockup != .none || edgeHighlight || motion.enabled }
    func pose(at time: Double) -> ScenePose { motion.enabled ? motion.pose(at: time) : pose.clamped }
    func clamped(to duration: Double) -> Self {
        var next = self
        next.pose = pose.clamped
        next.imageDuration = sceneClamp(imageDuration, 0.25...60, fallback: 3)
        next.motion = motion.clamped(to: duration)
        return next
    }
    /// A still snapshot retains the displayed animated pose without changing editor state.
    func still(at time: Double) -> Self {
        var next = self
        next.pose = pose(at: time)
        next.motion.enabled = false
        return next
    }
}

func sceneClamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double {
    min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
}

/// Canonical geometry uses bottom-left image coordinates; position Y is positive downward in the UI.
struct SceneGeometry {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
    var bounds: CGRect

    static func evaluate(frame: CGRect, canvas: CGSize, pose: ScenePose) -> Self {
        let p = pose.clamped
        let rx = p.tiltX * .pi / 180, ry = p.tiltY * .pi / 180, rz = p.rotation * .pi / 180
        let distance = max(frame.width, frame.height) * (4 - 2.5 * p.perspective)
        func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let xx = x * cos(ry) + y * sin(rx) * sin(ry)
            let yy = y * cos(rx)
            let z = -x * sin(ry) + y * sin(rx) * cos(ry)
            let factor = distance / max(distance * 0.1, distance - z)
            return CGPoint(x: frame.midX + (xx * cos(rz) - yy * sin(rz)) * factor * p.scale + p.x * canvas.width,
                           y: frame.midY + (xx * sin(rz) + yy * cos(rz)) * factor * p.scale - p.y * canvas.height)
        }
        let tl = project(-frame.width / 2, frame.height / 2), tr = project(frame.width / 2, frame.height / 2)
        let bl = project(-frame.width / 2, -frame.height / 2), br = project(frame.width / 2, -frame.height / 2)
        let xs = [tl.x, tr.x, bl.x, br.x], ys = [tl.y, tr.y, bl.y, br.y]
        return Self(topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br,
                    bounds: CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
    }
}
