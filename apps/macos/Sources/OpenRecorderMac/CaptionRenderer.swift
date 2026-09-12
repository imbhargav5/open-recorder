import CoreGraphics
import CoreText
import SwiftUI

/// One Core Text layout for native preview and exported frames. Coordinates use a bottom-left origin.
enum CaptionRenderer {
    struct Key: Hashable { var text: String; var style: CaptionStyle; var width: Int; var height: Int }
    struct Image { var image: CGImage; var frame: CGRect }

    static func render(text: String, style: CaptionStyle, canvas: CGSize) -> Image? {
        guard !text.isEmpty, canvas.width >= 2, canvas.height >= 2 else { return nil }
        let scale = min(canvas.width, canvas.height) / 1080
        let padding = max(2, 12 * scale)
        let maxWidth = max(1, canvas.width * 0.86 - padding * 2)
        var fontSize = max(1, min(64, max(20, style.fontSize)) * scale)
        var lines: [CTLine] = []
        var lineHeight: CGFloat = 0
        // Shrink unusually long edited captions until all text fits in two lines; never truncate speech.
        for _ in 0..<60 {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(style.textHex, alpha: 1)
            ])
            let typesetter = CTTypesetterCreateWithAttributedString(string)
            var offset = 0
            lines = []
            while offset < string.length && lines.count < 3 {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, maxWidth))
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count)))
                offset += count
            }
            lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + 3 * scale)
            if lines.count <= 2 && offset >= string.length { break }
            fontSize *= 0.9
        }
        let width = ceil(min(canvas.width, max(1, lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0) + padding * 2))
        let height = ceil(lineHeight * CGFloat(lines.count) + padding * 2)
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(color(style.backgroundHex, alpha: min(1, max(0, style.backgroundOpacity))))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerWidth: padding * 0.65, cornerHeight: padding * 0.65, transform: nil))
        context.fillPath()
        for (index, line) in lines.enumerated() {
            var descent: CGFloat = 0
            let textWidth = CTLineGetTypographicBounds(line, nil, &descent, nil)
            context.textPosition = CGPoint(x: (width - textWidth) / 2,
                                           y: height - padding - lineHeight * CGFloat(index + 1) + descent + 2 * scale)
            CTLineDraw(line, context)
        }
        guard let image = context.makeImage() else { return nil }
        let margin = canvas.height * 0.06
        let y = style.position == .bottom ? margin : canvas.height - margin - height
        return Image(image: image, frame: CGRect(x: (canvas.width - width) / 2, y: y, width: width, height: height))
    }

    private static func color(_ hex: String, alpha: Double) -> CGColor {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        return CGColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
}

struct CaptionPreviewOverlay: View, Equatable {
    var segment: CaptionSegment?
    var style: CaptionStyle
    var size: CGSize

    var body: some View {
        if let segment, let raster = CaptionRenderer.render(text: segment.text, style: style, canvas: size) {
            Image(decorative: raster.image, scale: 1)
                .resizable()
                .frame(width: raster.frame.width, height: raster.frame.height)
                .position(x: raster.frame.midX, y: size.height - raster.frame.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
