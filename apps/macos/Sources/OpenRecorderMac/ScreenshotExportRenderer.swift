import AppKit
import CoreGraphics
import Foundation

struct ScreenshotExportConfiguration {
    var background: BackgroundStyle
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
        drawImage(cgImage, in: imageRect, context: context)
        context.restoreGState()

        guard let exportedImage = context.makeImage() else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: exportedImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func drawExportBackground(in context: CGContext, rect: CGRect) {
        let shouldDrawBackground = !configuration.background.isTransparent

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

        switch configuration.background {
        case .transparent:
            break
        case let .solid(color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case let .gradient(preset):
            drawGradient(preset, in: context, rect: rect)
        case let .wallpaper(preset):
            drawWallpaper(preset, in: context, rect: rect)
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

    private func drawGradient(_ preset: GradientPreset, in context: CGContext, rect: CGRect) {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let stops = preset.sortedStops
        let cgColors = stops.map { $0.color.cgColor } as CFArray
        let locations = stops.map { CGFloat($0.position) }
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations) else {
            return
        }

        switch preset.kind {
        case .linear:
            let endpoints = preset.endpoints(in: rect)
            context.drawLinearGradient(
                gradient,
                start: endpoints.start,
                end: endpoints.end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        case .radial:
            let endpoints = preset.endpoints(in: rect)
            let endRadius = preset.radialRadius(in: rect)
            context.drawRadialGradient(
                gradient,
                startCenter: endpoints.start,
                startRadius: 0,
                endCenter: endpoints.end,
                endRadius: endRadius,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    private func drawWallpaper(_ preset: WallpaperPreset, in context: CGContext, rect: CGRect) {
        guard let url = preset.fullURL, let cgImage = WallpaperImageCache.cgImage(for: url) else {
            context.setFillColor(NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor)
            context.fill(rect)
            return
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        guard imageWidth > 0, imageHeight > 0 else { return }

        let scale = max(rect.width / imageWidth, rect.height / imageHeight)
        let drawSize = CGSize(width: imageWidth * scale, height: imageHeight * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        drawImage(cgImage, in: drawRect, context: context)
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

    private func drawImage(_ cgImage: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
