import AppKit
import CoreGraphics
import Foundation

struct ScreenshotExportConfiguration {
    var backgroundMode: ScreenshotBackgroundMode
    var gradientColors: [NSColor]
    var solidColor: NSColor
    var padding: Double
    var backgroundRoundness: Double
    var backgroundShadow: Double
    var imageRoundness: Double
    var imageShadow: Double
}

struct ScreenshotExportRenderer {
    var configuration: ScreenshotExportConfiguration

    static func suggestedFileName(for screenshotURL: URL?) -> String {
        let baseName = screenshotURL?.deletingPathExtension().lastPathComponent ?? "screenshot"
        return "\(baseName)-export.png"
    }

    func renderPNG(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let exportPadding = max(CGFloat(configuration.padding), 0)
        let shadowMargin = max(CGFloat(configuration.backgroundShadow), CGFloat(configuration.imageShadow)) > 0
            ? ceil(max(CGFloat(configuration.backgroundShadow), CGFloat(configuration.imageShadow)) * 56)
            : 0
        let backgroundRect = CGRect(
            x: shadowMargin,
            y: shadowMargin,
            width: imageSize.width + exportPadding * 2,
            height: imageSize.height + exportPadding * 2
        )
        let imageRect = CGRect(
            x: backgroundRect.minX + exportPadding,
            y: backgroundRect.minY + exportPadding,
            width: imageSize.width,
            height: imageSize.height
        )
        let width = max(Int(ceil(backgroundRect.width + shadowMargin * 2)), 1)
        let height = max(Int(ceil(backgroundRect.height + shadowMargin * 2)), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        drawExportBackground(in: context, rect: backgroundRect)
        drawExportImageShadow(in: context, rect: imageRect)

        context.saveGState()
        context.addPath(CGPath(
            roundedRect: imageRect,
            cornerWidth: CGFloat(configuration.imageRoundness),
            cornerHeight: CGFloat(configuration.imageRoundness),
            transform: nil
        ))
        context.clip()
        context.draw(cgImage, in: imageRect)
        context.restoreGState()

        guard let exportedImage = context.makeImage() else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: exportedImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func drawExportBackground(in context: CGContext, rect: CGRect) {
        let shouldDrawBackground = configuration.backgroundMode != .transparent

        if configuration.backgroundShadow > 0, shouldDrawBackground {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: 14 * CGFloat(configuration.backgroundShadow)),
                blur: 34 * CGFloat(configuration.backgroundShadow),
                color: NSColor.black.withAlphaComponent(0.45 * configuration.backgroundShadow).cgColor
            )
            context.setFillColor(NSColor.black.withAlphaComponent(0.01).cgColor)
            context.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: CGFloat(configuration.backgroundRoundness),
                cornerHeight: CGFloat(configuration.backgroundRoundness),
                transform: nil
            ))
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: CGFloat(configuration.backgroundRoundness),
            cornerHeight: CGFloat(configuration.backgroundRoundness),
            transform: nil
        ))
        context.clip()

        switch configuration.backgroundMode {
        case .gradient:
            let colors = configuration.gradientColors.map { $0.cgColor } as CFArray
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: nil) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: []
                )
            }
        case .color:
            context.setFillColor(configuration.solidColor.cgColor)
            context.fill(rect)
        case .transparent:
            break
        }

        context.restoreGState()

        if shouldDrawBackground {
            context.saveGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            context.setLineWidth(1)
            context.addPath(CGPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                cornerWidth: CGFloat(configuration.backgroundRoundness),
                cornerHeight: CGFloat(configuration.backgroundRoundness),
                transform: nil
            ))
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawExportImageShadow(in context: CGContext, rect: CGRect) {
        guard configuration.imageShadow > 0 else { return }

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 18 * CGFloat(configuration.imageShadow)),
            blur: 38 * CGFloat(configuration.imageShadow),
            color: NSColor.black.withAlphaComponent(0.55 * configuration.imageShadow).cgColor
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.01).cgColor)
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: CGFloat(configuration.imageRoundness),
            cornerHeight: CGFloat(configuration.imageRoundness),
            transform: nil
        ))
        context.fillPath()
        context.restoreGState()
    }
}
