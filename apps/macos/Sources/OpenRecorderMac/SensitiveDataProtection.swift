import CoreImage
import CoreGraphics
import Foundation
import SwiftUI

struct BlurRegion: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var label: String = ""

    var normalizedRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    func pixelRect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    static func fromDrag(start: CGPoint, end: CGPoint, in size: CGSize) -> BlurRegion {
        let nx1 = min(max(start.x / size.width, 0), 1)
        let ny1 = min(max(start.y / size.height, 0), 1)
        let nx2 = min(max(end.x / size.width, 0), 1)
        let ny2 = min(max(end.y / size.height, 0), 1)
        return BlurRegion(
            x: min(nx1, nx2), y: min(ny1, ny2),
            width: abs(nx2 - nx1), height: abs(ny2 - ny1)
        )
    }
}

struct TimelineBlurRegion: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var region: BlurRegion
    var span: TimelineSpan
    var blurRadius: Double = 25

    func isActive(at time: Double) -> Bool { span.contains(time) }
}

struct SensitiveDataConfig: Codable, Equatable, Hashable, Sendable {
    var enabled = false
    var blurRadius: Double = 25
    var regions: [BlurRegion] = []

    static let `default` = SensitiveDataConfig()

    var clamped: SensitiveDataConfig {
        var next = self
        next.blurRadius = max(5, min(60, blurRadius))
        return next
    }
}

enum SensitiveDataBlur {
    static func applyBlur(to image: CIImage, regions: [BlurRegion], blurRadius: Double) -> CIImage {
        guard !regions.isEmpty else { return image }
        let extent = image.extent
        var result = image
        for region in regions {
            let rect = CGRect(
                x: extent.minX + region.x * extent.width,
                y: extent.minY + (1 - region.y - region.height) * extent.height,
                width: region.width * extent.width,
                height: region.height * extent.height
            )
            let expanded = rect.insetBy(dx: -4, dy: -4)
            let blurred = image.cropped(to: expanded)
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
                .cropped(to: expanded)
            result = blurred.composited(over: result)
        }
        return result
    }

    static func applyBlur(to image: CIImage, config: SensitiveDataConfig, contentSize: CGSize) -> CIImage {
        guard config.enabled, !config.regions.isEmpty else { return image }
        return applyBlur(to: image, regions: config.regions, blurRadius: config.blurRadius)
    }

    static func applyTimelineBlur(to image: CIImage, blurRegions: [TimelineBlurRegion], at time: Double) -> CIImage {
        var result = image
        for blur in blurRegions where blur.isActive(at: time) {
            result = applyBlur(to: result, regions: [blur.region], blurRadius: blur.blurRadius)
        }
        return result
    }
}

private struct BlurEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct BlurRegionDrawingOverlay: ViewModifier {
    @Binding var sensitiveData: SensitiveDataConfig
    var edits: TimelineEditDriver?
    var currentTime: Double = 0
    var duration: Double = 0
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    private var allRegions: [BlurRegion] {
        var regions = sensitiveData.regions
        if let edits {
            for blur in edits.snapshot.blurRegions where blur.isActive(at: currentTime) {
                regions.append(blur.region)
            }
        }
        return regions
    }

    func body(content: Content) -> some View {
        content.overlay {
            if sensitiveData.enabled {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        ForEach(allRegions) { region in
                            let w = region.width * size.width
                            let h = region.height * size.height
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Rectangle()
                                        .fill(Color.red.opacity(0.08))
                                        .border(Color.red.opacity(0.6), width: 1.5)
                                }
                                .frame(width: w, height: h)
                                .position(
                                    x: (region.x + region.width / 2) * size.width,
                                    y: (region.y + region.height / 2) * size.height
                                )
                                .allowsHitTesting(false)
                        }

                        if let start = dragStart, let current = dragCurrent {
                            let rect = dragRect(start: start, current: current)
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Rectangle()
                                        .fill(Color.red.opacity(0.15))
                                        .border(Color.red, width: 2)
                                }
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }

                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 4)
                                .onChanged { event in
                                    if dragStart == nil { dragStart = event.startLocation }
                                    dragCurrent = event.location
                                }
                                .onEnded { event in
                                    guard let start = dragStart else { return }
                                    let region = BlurRegion.fromDrag(start: start, end: event.location, in: size)
                                    guard region.width > 0.01, region.height > 0.01 else {
                                        dragStart = nil; dragCurrent = nil; return
                                    }
                                    if let edits, duration > 0 {
                                        let span = TimelineSpan(start: currentTime, end: min(currentTime + 5, duration))
                                        let blurRegion = TimelineBlurRegion(region: region, span: span, blurRadius: sensitiveData.blurRadius)
                                        edits.send(.addBlurRegion(blurRegion))
                                    } else {
                                        sensitiveData.regions.append(region)
                                    }
                                    dragStart = nil
                                    dragCurrent = nil
                                }
                            )
                    }
                }
            }
        }
    }

    private func dragRect(start: CGPoint, current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }
}
