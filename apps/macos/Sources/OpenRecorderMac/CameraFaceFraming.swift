import CoreGraphics
import CoreImage
import Vision

/// Ignore detector jitter and ease toward deliberate movement. Time-based smoothing
/// gives preview and export the same framing at different frame rates.
struct CameraFaceFocusMotion {
    private(set) var position = CGPoint(x: 0.5, y: 0.5)
    private var target = CGPoint(x: 0.5, y: 0.5)
    private var lastTime: Double?

    mutating func update(detection: CGPoint?, at time: Double, reset: Bool = false) -> CGPoint {
        if reset { lastTime = nil }
        if let detection {
            let distance = hypot(detection.x - target.x, detection.y - target.y)
            if lastTime == nil || distance > 0.025 { target = detection }
        }
        guard let previous = lastTime else {
            position = target
            lastTime = time
            return position
        }
        let elapsed = max(0, time - previous)
        let blend = 1 - exp(-elapsed / 0.22)
        position.x += (target.x - position.x) * blend
        position.y += (target.y - position.y) * blend
        lastTime = time
        return position
    }
}

/// Each renderer owns a tracker and calls it from its own serial queue.
final class CameraFaceTracker: @unchecked Sendable {
    private var lastSampleTime: Double?
    private var lastFaceTime: Double?
    private var motion = CameraFaceFocusMotion()

    func focus(in image: CIImage, at time: Double) -> CGPoint {
        if let previous = lastSampleTime, time >= previous, time - previous < 0.25 {
            return motion.update(detection: nil, at: time)
        }
        let reset = lastSampleTime.map { time < $0 || time - $0 > 1 } ?? true
        if reset { lastFaceTime = nil; motion = CameraFaceFocusMotion() }
        lastSampleTime = time
        let request = VNDetectFaceRectanglesRequest()
        // Detection needs facial structure, not full-resolution camera pixels.
        let scale = min(1, 640 / max(image.extent.width, image.extent.height))
        let input = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        try? VNImageRequestHandler(ciImage: input, options: [:]).perform([request])
        let face = request.results?.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        var target: CGPoint?
        if let face {
            target = CGPoint(x: face.boundingBox.midX, y: face.boundingBox.midY)
            lastFaceTime = time
        } else if lastFaceTime == nil || time - (lastFaceTime ?? time) > 1.5 {
            target = CGPoint(x: 0.5, y: 0.5)
        }
        return motion.update(detection: target, at: time, reset: reset)
    }
}

enum CameraFaceFraming {
    /// Aspect-fill without blank edges. Focus and target must use the same coordinate origin.
    static func imageFrame(source: CGSize, target: CGRect, focus: CGPoint) -> CGRect {
        guard source.width > 0, source.height > 0, !target.isEmpty else { return target }
        let scale = max(target.width / source.width, target.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        let x = max(target.maxX - size.width, min(target.minX, target.midX - focus.x * size.width))
        let y = max(target.maxY - size.height, min(target.minY, target.midY - focus.y * size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
