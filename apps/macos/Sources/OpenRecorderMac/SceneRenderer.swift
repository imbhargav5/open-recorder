import CoreImage
import CoreGraphics

struct SceneMockupLayout {
    var frame: CGRect
    var content: CGRect
    var radius: CGFloat

    static func make(in rect: CGRect, mediaAspect: CGFloat, style: MockupStyle, radius: CGFloat, toolbarFrac: CGFloat = 0.085) -> Self {
        guard style != .none else { return Self(frame: rect, content: rect, radius: radius) }
        let aspect: CGFloat
        switch style {
        case .phone: aspect = 0.5
        case .tablet: aspect = 0.75
        default: aspect = mediaAspect
        }
        let refDim = min(rect.width, rect.height)
        let edgeFrac: CGFloat = style == .phone || style == .tablet ? 0.045 : 0.015
        let topFrac: CGFloat = style == .browser || style == .window ? toolbarFrac : edgeFrac
        let edge = refDim * edgeFrac
        let top = refDim * topFrac
        let availW = max(1, rect.width - 2 * edge)
        let availH = max(1, rect.height - edge - top)
        let contentSize = CGSize(
            width: min(availW, availH * aspect),
            height: min(availH, availW / aspect)
        )
        let frameSize = CGSize(
            width: contentSize.width + 2 * edge,
            height: contentSize.height + edge + top
        )
        let frame = CGRect(x: rect.midX - frameSize.width / 2, y: rect.midY - frameSize.height / 2,
                           width: frameSize.width, height: frameSize.height)
        let content = CGRect(x: frame.minX + edge, y: frame.minY + edge,
                             width: contentSize.width, height: contentSize.height)
        return Self(frame: frame, content: content, radius: min(frameSize.width, frameSize.height) * (style == .phone || style == .tablet ? 0.1 : 0.025))
    }
}

/// Owned by one rendering queue. Caches are bounded to the current frame style and size.
final class SceneRenderer {
    private struct ArtworkKey: Equatable {
        var frame: CGRect
        var style: MockupStyle
        var dark: Bool
        var highlight: Bool
        var radius: CGFloat
        var browserURL: String
        var browserURLAlignment: BrowserURLAlignment
        var browserToolbarStyle: BrowserToolbarStyle
        var browserShowTrafficLights: Bool
        var browserShowNavButtons: Bool
        var browserShowLock: Bool
    }
    private var artworkCache: (ArtworkKey, CIImage)?
    private var maskCache: (CGRect, CGFloat, CIImage)?

    static func roundedMask(in rect: CGRect, radius: CGFloat) -> CIImage {
        let filter = CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect), "inputRadius": max(0, radius), "inputColor": CIColor.white
        ])!
        return filter.outputImage!.cropped(to: rect)
    }

    func mask(_ image: CIImage, in rect: CGRect, radius: CGFloat) -> CIImage {
        let shape: CIImage
        if let cache = maskCache, cache.0 == rect, cache.1 == radius { shape = cache.2 }
        else {
            shape = Self.roundedMask(in: rect, radius: radius)
            maskCache = (rect, radius, shape)
        }
        return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: shape
        ]).cropped(to: rect)
    }

    func render(media: CIImage, mediaRect: CGRect, frame: CGRect, canvas: CGSize,
                settings: SceneSettings, time: Double, radius: CGFloat, shadow: Double,
                referenceFrame: CGRect? = nil) -> CIImage {
        let tbFrac = settings.mockup == .browser ? settings.browserToolbarStyle.heightFraction : 0.085
        let layout = SceneMockupLayout.make(in: frame, mediaAspect: mediaRect.width / max(1, mediaRect.height), style: settings.mockup, radius: radius, toolbarFrac: tbFrac)
        let sx = layout.content.width / max(1, mediaRect.width), sy = layout.content.height / max(1, mediaRect.height)
        let fitted = media.cropped(to: mediaRect)
            .transformed(by: CGAffineTransform(translationX: -mediaRect.minX, y: -mediaRect.minY))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: layout.content.minX, y: layout.content.minY))
        var card = mask(fitted, in: layout.content, radius: settings.mockup == .none ? radius : min(radius, layout.radius / 2))
        let artwork = frameArtwork(layout: layout, settings: settings)
        card = card.composited(over: artwork).cropped(to: layout.frame)
        if settings.edgeHighlight {
            card = edgeStroke(in: layout.frame, radius: layout.radius).composited(over: card)
        }
        let projected = project(card, canvas: canvas, pose: settings.pose(at: time),
                                referenceFrame: referenceFrame ?? layout.frame)
        guard shadow > 0 else { return projected }
        let amount = sceneClamp(shadow, 0...1)
        let unit = min(canvas.width, canvas.height) / 1080
        let drop = projected.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: amount * 0.55)
        ]).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 38 * amount * unit])
            .transformed(by: CGAffineTransform(translationX: 0, y: -18 * amount * unit))
        return projected.composited(over: drop)
    }

    /// Project each layer through the same plane, keeping gaps and relative positions
    /// intact. Use its full extent so shadows and tilted corners are not clipped.
    func project(_ image: CIImage, canvas: CGSize, pose: ScenePose, referenceFrame: CGRect) -> CIImage {
        guard !pose.isIdentity, !image.extent.isEmpty else { return image }
        let geometry = SceneGeometry.evaluate(frame: image.extent, canvas: canvas, pose: pose,
                                              referenceFrame: referenceFrame)
        return image.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(cgPoint: geometry.topLeft), "inputTopRight": CIVector(cgPoint: geometry.topRight),
            "inputBottomLeft": CIVector(cgPoint: geometry.bottomLeft), "inputBottomRight": CIVector(cgPoint: geometry.bottomRight)
        ])
    }

    private func frameArtwork(layout: SceneMockupLayout, settings: SceneSettings) -> CIImage {
        let isBrowser = settings.mockup == .browser
        let key = ArtworkKey(frame: layout.frame, style: settings.mockup, dark: settings.darkMockup,
                             highlight: settings.edgeHighlight, radius: layout.radius,
                             browserURL: isBrowser ? settings.browserURL : "",
                             browserURLAlignment: settings.browserURLAlignment,
                             browserToolbarStyle: settings.browserToolbarStyle,
                             browserShowTrafficLights: settings.browserShowTrafficLights,
                             browserShowNavButtons: settings.browserShowNavButtons,
                             browserShowLock: settings.browserShowLock)
        if let cache = artworkCache, cache.0 == key { return cache.1 }
        let rect = layout.frame
        let image: CIImage
        if settings.mockup == .none {
            image = CIImage.empty()
        } else if isBrowser {
            image = Self.renderBrowserChrome(in: rect, radius: layout.radius, dark: settings.darkMockup,
                url: settings.browserURL, alignment: settings.browserURLAlignment,
                toolbarStyle: settings.browserToolbarStyle, showTrafficLights: settings.browserShowTrafficLights,
                showNavButtons: settings.browserShowNavButtons, showLock: settings.browserShowLock)
        } else {
            image = Self.renderSimpleChrome(in: rect, radius: layout.radius, dark: settings.darkMockup, isWindow: settings.mockup == .window)
        }
        artworkCache = (key, image)
        return image
    }

    private static func renderSimpleChrome(in rect: CGRect, radius: CGFloat, dark: Bool, isWindow: Bool) -> CIImage {
        let gray: CGFloat = dark ? 0.12 : 0.92
        var image = CIImage(color: CIColor(red: gray, green: gray, blue: gray)).cropped(to: rect)
        if isWindow {
            let r = min(rect.width, rect.height) * 0.009
            for (index, color) in [CIColor(red: 1, green: 0.36, blue: 0.32), CIColor(red: 1, green: 0.75, blue: 0.2), CIColor(red: 0.22, green: 0.78, blue: 0.35)].enumerated() {
                let dot = CGRect(x: rect.minX + r * (3 + CGFloat(index) * 3), y: rect.maxY - r * 5, width: r * 2, height: r * 2)
                image = CIImage(color: color).cropped(to: dot).applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: roundedMask(in: dot, radius: r)
                ]).composited(over: image)
            }
        }
        return image.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: roundedMask(in: rect, radius: radius)
        ])
    }

    private static func renderBrowserChrome(in rect: CGRect, radius: CGFloat, dark: Bool, url: String,
            alignment: BrowserURLAlignment = .left, toolbarStyle: BrowserToolbarStyle = .standard,
            showTrafficLights: Bool = true, showNavButtons: Bool = true, showLock: Bool = true) -> CIImage {
        let scale = min(rect.width, rect.height) / 1080
        let w = Int(ceil(rect.width)), h = Int(ceil(rect.height))
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return CIImage.empty()
        }
        let toolbarH = min(rect.width, rect.height) * toolbarStyle.heightFraction

        let bodyGray: CGFloat = dark ? 0.12 : 0.92
        ctx.setFillColor(CGColor(red: bodyGray, green: bodyGray, blue: bodyGray, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()

        let tbTop = CGFloat(h) - toolbarH
        let tbGrayTop: CGFloat = dark ? 0.16 : 0.96
        let tbGrayBot: CGFloat = dark ? 0.11 : 0.88
        let colors = [CGColor(red: tbGrayTop, green: tbGrayTop, blue: tbGrayTop, alpha: 1),
                      CGColor(red: tbGrayBot, green: tbGrayBot, blue: tbGrayBot, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: tbTop, width: CGFloat(w), height: toolbarH))
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: tbTop), options: [])
            ctx.restoreGState()
        }

        let divGray: CGFloat = dark ? 0.22 : 0.78
        ctx.setFillColor(CGColor(red: divGray, green: divGray, blue: divGray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: tbTop, width: CGFloat(w), height: max(1, scale)))

        let dotR = max(4, 6 * scale)
        let dotY = tbTop + toolbarH / 2
        var leftEdge = 16 * scale

        if showTrafficLights {
            let dotColors: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.36, 0.32), (1, 0.75, 0.2), (0.22, 0.78, 0.35)]
            for (i, c) in dotColors.enumerated() {
                let cx = leftEdge + CGFloat(i) * (dotR * 2 + 6 * scale) + dotR
                ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: cx - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
            }
            leftEdge += 3 * (dotR * 2 + 6 * scale) + 12 * scale
        }

        if showNavButtons {
            let chevronSize = max(6, 8 * scale)
            let chevronStroke = max(1.5, 2 * scale)
            let navGray: CGFloat = dark ? 0.55 : 0.45
            ctx.setStrokeColor(CGColor(red: navGray, green: navGray, blue: navGray, alpha: 1))
            ctx.setLineWidth(chevronStroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let backCX = leftEdge + chevronSize
            ctx.beginPath()
            ctx.move(to: CGPoint(x: backCX + chevronSize * 0.4, y: dotY - chevronSize * 0.5))
            ctx.addLine(to: CGPoint(x: backCX - chevronSize * 0.4, y: dotY))
            ctx.addLine(to: CGPoint(x: backCX + chevronSize * 0.4, y: dotY + chevronSize * 0.5))
            ctx.strokePath()
            let fwdCX = backCX + chevronSize * 2
            ctx.beginPath()
            ctx.move(to: CGPoint(x: fwdCX - chevronSize * 0.4, y: dotY - chevronSize * 0.5))
            ctx.addLine(to: CGPoint(x: fwdCX + chevronSize * 0.4, y: dotY))
            ctx.addLine(to: CGPoint(x: fwdCX - chevronSize * 0.4, y: dotY + chevronSize * 0.5))
            ctx.strokePath()
            leftEdge = fwdCX + chevronSize * 2
        }

        let barLeft = leftEdge
        let barRight = CGFloat(w) - 16 * scale
        let barH = max(20, toolbarH * 0.48)
        let barY = dotY - barH / 2
        let barRadius = barH * 0.35
        let barBG: CGFloat = dark ? 0.08 : 0.98
        ctx.setFillColor(CGColor(red: barBG, green: barBG, blue: barBG, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: barLeft, y: barY, width: max(1, barRight - barLeft), height: barH),
                           cornerWidth: barRadius, cornerHeight: barRadius, transform: nil))
        ctx.fillPath()

        let barStroke: CGFloat = dark ? 0.24 : 0.72
        ctx.setStrokeColor(CGColor(red: barStroke, green: barStroke, blue: barStroke, alpha: 1))
        ctx.setLineWidth(max(0.5, scale * 0.8))
        ctx.addPath(CGPath(roundedRect: CGRect(x: barLeft, y: barY, width: max(1, barRight - barLeft), height: barH),
                           cornerWidth: barRadius, cornerHeight: barRadius, transform: nil))
        ctx.strokePath()

        var textLeftEdge = barLeft + 10 * scale

        if showLock {
            let lockSize = max(8, 10 * scale)
            let lockGray: CGFloat = dark ? 0.4 : 0.55
            ctx.setStrokeColor(CGColor(red: lockGray, green: lockGray, blue: lockGray, alpha: 1))
            ctx.setLineWidth(max(1, 1.5 * scale))
            let lockBodyH = lockSize * 0.55
            let lockBodyY = dotY - lockBodyH / 2 + lockSize * 0.1
            ctx.addPath(CGPath(roundedRect: CGRect(x: textLeftEdge, y: lockBodyY, width: lockSize * 0.7, height: lockBodyH),
                               cornerWidth: lockSize * 0.1, cornerHeight: lockSize * 0.1, transform: nil))
            ctx.strokePath()
            let archW = lockSize * 0.45
            ctx.addArc(center: CGPoint(x: textLeftEdge + lockSize * 0.35, y: lockBodyY + lockBodyH),
                       radius: archW / 2, startAngle: .pi, endAngle: 0, clockwise: false)
            ctx.strokePath()
            textLeftEdge += lockSize + 8 * scale
        }

        let urlText = url.isEmpty ? "https://example.com" : url
        let fontSize = max(10, min(14, 12 * scale))
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let urlGray: CGFloat = dark ? 0.52 : 0.42
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: CGColor(red: urlGray, green: urlGray, blue: urlGray, alpha: 1)
        ]
        let attrString = NSAttributedString(string: urlText, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrString)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let barInnerWidth = barRight - textLeftEdge - 10 * scale
        let textX: CGFloat
        switch alignment {
        case .left:
            textX = textLeftEdge
        case .center:
            textX = textLeftEdge + max(0, (barInnerWidth - textWidth) / 2)
        }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: textLeftEdge, y: barY, width: max(0, barInnerWidth), height: barH))
        ctx.textPosition = CGPoint(x: textX, y: dotY - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        guard let cgImage = ctx.makeImage() else { return CIImage.empty() }
        let ciImage = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return ciImage.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: roundedMask(in: rect, radius: radius)
        ])
    }

    private func edgeStroke(in rect: CGRect, radius: CGFloat) -> CIImage {
        let outer = Self.roundedMask(in: rect, radius: radius)
        let edge = max(1, min(rect.width, rect.height) / 400)
        let inner = Self.roundedMask(in: rect.insetBy(dx: edge, dy: edge), radius: max(0, radius - edge))
        return outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.35)])
    }
}
