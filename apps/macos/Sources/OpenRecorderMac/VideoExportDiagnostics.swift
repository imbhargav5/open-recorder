import CoreImage
import CoreVideo
import Foundation

/// Opt-in, per-export measurements. Never logs media paths or changes encoder settings.
final class VideoExportDiagnostics: @unchecked Sendable {
    struct Snapshot: Codable {
        var renderedFrames = 0
        var preparationSeconds = 0.0
        var kernelSeconds = 0.0
        var renderPasses = 0
        var processedPixels = 0
    }
    let detailed: Bool
    let frameObserver: (@Sendable (CVPixelBuffer, Double) -> Void)?
    private let lock = NSLock()
    private var values = Snapshot()

    init(detailed: Bool = false, frameObserver: (@Sendable (CVPixelBuffer, Double) -> Void)? = nil) {
        self.detailed = detailed
        self.frameObserver = frameObserver
    }

    func record(preparationSeconds: Double = 0, info: CIRenderInfo? = nil) {
        lock.lock()
        defer { lock.unlock() }
        values.renderedFrames += 1
        values.preparationSeconds += preparationSeconds
        if let info {
            values.kernelSeconds += info.kernelExecutionTime
            values.renderPasses += info.passCount
            values.processedPixels += info.pixelsProcessed
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
