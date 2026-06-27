import CoreGraphics
import Foundation

enum VideoCropSizing: Equatable, Hashable, Codable {
    case preset(VideoExportResolution)
    case custom(width: Int, height: Int)

    var title: String {
        switch self {
        case .preset(let resolution):
            resolution.title
        case .custom:
            "Custom"
        }
    }

    var customSize: CGSize? {
        switch self {
        case .preset:
            nil
        case .custom(let width, let height):
            CGSize(width: width, height: height)
        }
    }
}

struct VideoCropSelection: Equatable, Hashable, Codable {
    static let minimumPixelLength: CGFloat = 8
    static let defaultSourceSize = CGSize(width: 1920, height: 1080)

    var normalizedRect: CGRect
    var sizing: VideoCropSizing

    init(normalizedRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), sizing: VideoCropSizing = .preset(.source)) {
        self.normalizedRect = Self.clampedNormalizedRect(normalizedRect)
        self.sizing = sizing
    }

    static let fullFrame = VideoCropSelection()

    var isFullFrame: Bool {
        abs(normalizedRect.minX) < 0.0001 &&
            abs(normalizedRect.minY) < 0.0001 &&
            abs(normalizedRect.width - 1) < 0.0001 &&
            abs(normalizedRect.height - 1) < 0.0001
    }

    var isPassthrough: Bool {
        guard isFullFrame else { return false }
        if case .preset(.source) = sizing {
            return true
        }
        return false
    }

    func pixelRect(in sourceSize: CGSize) -> CGRect {
        let safeSize = Self.safeSourceSize(sourceSize)
        return CGRect(
            x: normalizedRect.minX * safeSize.width,
            y: normalizedRect.minY * safeSize.height,
            width: normalizedRect.width * safeSize.width,
            height: normalizedRect.height * safeSize.height
        )
    }

    func sourceCropSize(in sourceSize: CGSize) -> CGSize {
        pixelRect(in: sourceSize).standardized.size
    }

    func previewAspectRatio(in sourceSize: CGSize) -> CGFloat {
        let cropSize = sourceCropSize(in: sourceSize)
        guard cropSize.width.isFinite,
              cropSize.height.isFinite,
              cropSize.width > 0,
              cropSize.height > 0 else {
            return PreviewStageLayout.videoAspectRatio
        }
        return cropSize.width / cropSize.height
    }

    func withPixelRect(_ pixelRect: CGRect, in sourceSize: CGSize) -> VideoCropSelection {
        var copy = self
        copy.normalizedRect = Self.normalizedRect(for: pixelRect, in: sourceSize)
        return copy
    }

    func withSizing(_ sizing: VideoCropSizing) -> VideoCropSelection {
        var copy = self
        copy.sizing = sizing
        return copy
    }

    static func normalizedRect(for pixelRect: CGRect, in sourceSize: CGSize) -> CGRect {
        let safeSize = safeSourceSize(sourceSize)
        let clamped = clampedPixelRect(pixelRect, in: safeSize)
        return clampedNormalizedRect(CGRect(
            x: clamped.minX / safeSize.width,
            y: clamped.minY / safeSize.height,
            width: clamped.width / safeSize.width,
            height: clamped.height / safeSize.height
        ))
    }

    static func clampedPixelRect(_ rect: CGRect, in sourceSize: CGSize) -> CGRect {
        let safeSize = safeSourceSize(sourceSize)
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite else {
            return CGRect(origin: .zero, size: safeSize)
        }

        let standardized = rect.standardized
        let minWidth = min(Self.minimumPixelLength, safeSize.width)
        let minHeight = min(Self.minimumPixelLength, safeSize.height)
        let width = min(max(standardized.width, minWidth), safeSize.width)
        let height = min(max(standardized.height, minHeight), safeSize.height)
        let x = min(max(standardized.minX, 0), max(0, safeSize.width - width))
        let y = min(max(standardized.minY, 0), max(0, safeSize.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func clampedNormalizedRect(_ rect: CGRect) -> CGRect {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let standardized = rect.standardized
        let width = min(max(standardized.width, 0.0001), 1)
        let height = min(max(standardized.height, 0.0001), 1)
        let x = min(max(standardized.minX, 0), 1 - width)
        let y = min(max(standardized.minY, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func safeSourceSize(_ sourceSize: CGSize) -> CGSize {
        CGSize(
            width: sourceSize.width.isFinite && sourceSize.width > 0 ? sourceSize.width : defaultSourceSize.width,
            height: sourceSize.height.isFinite && sourceSize.height > 0 ? sourceSize.height : defaultSourceSize.height
        )
    }
}

enum VideoCropGeometry {
    static func fittedVideoFrame(sourceSize: CGSize, in availableSize: CGSize) -> CGRect {
        guard availableSize.width.isFinite,
              availableSize.height.isFinite,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return .zero
        }

        let safeSourceSize = VideoCropSelection.safeSourceSize(sourceSize)
        let fittedSize = PreviewStageLayout.fittedSize(
            forAspectRatio: safeSourceSize.width / safeSourceSize.height,
            in: availableSize
        )
        return CGRect(
            x: (availableSize.width - fittedSize.width) / 2,
            y: (availableSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func displayRect(for pixelRect: CGRect, sourceSize: CGSize, videoFrame: CGRect) -> CGRect {
        let safeSourceSize = VideoCropSelection.safeSourceSize(sourceSize)
        let clamped = VideoCropSelection.clampedPixelRect(pixelRect, in: safeSourceSize)
        return CGRect(
            x: videoFrame.minX + clamped.minX / safeSourceSize.width * videoFrame.width,
            y: videoFrame.minY + clamped.minY / safeSourceSize.height * videoFrame.height,
            width: clamped.width / safeSourceSize.width * videoFrame.width,
            height: clamped.height / safeSourceSize.height * videoFrame.height
        )
    }

    static func pixelRect(for displayRect: CGRect, sourceSize: CGSize, videoFrame: CGRect) -> CGRect {
        let safeSourceSize = VideoCropSelection.safeSourceSize(sourceSize)
        guard videoFrame.width.isFinite,
              videoFrame.height.isFinite,
              videoFrame.width > 0,
              videoFrame.height > 0 else {
            return CGRect(origin: .zero, size: safeSourceSize)
        }
        return VideoCropSelection.clampedPixelRect(
            CGRect(
                x: (displayRect.minX - videoFrame.minX) / videoFrame.width * safeSourceSize.width,
                y: (displayRect.minY - videoFrame.minY) / videoFrame.height * safeSourceSize.height,
                width: displayRect.width / videoFrame.width * safeSourceSize.width,
                height: displayRect.height / videoFrame.height * safeSourceSize.height
            ),
            in: safeSourceSize
        )
    }

    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, floor(max(2, size.width) / 2) * 2),
            height: max(2, floor(max(2, size.height) / 2) * 2)
        )
    }
}
