import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI

struct SerializableColor: Equatable, Hashable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String, alpha: Double = 1) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        var raw: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&raw)
        let r = Double((raw >> 16) & 0xFF) / 255
        let g = Double((raw >> 8) & 0xFF) / 255
        let b = Double(raw & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    init(_ nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            alpha: Double(converted.alphaComponent)
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    var cgColor: CGColor {
        nsColor.cgColor
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        let redValue = Int((max(0, min(red, 1)) * 255).rounded())
        let greenValue = Int((max(0, min(green, 1)) * 255).rounded())
        let blueValue = Int((max(0, min(blue, 1)) * 255).rounded())
        return String(format: "#%02X%02X%02X", redValue, greenValue, blueValue)
    }
}

struct GradientStop: Equatable, Hashable, Codable {
    var color: SerializableColor
    var position: Double
}

enum GradientKind: Equatable, Hashable, Codable {
    case linear(angleDegrees: Double)
    case radial(centerX: Double, centerY: Double)
}

struct GradientPreset: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var kind: GradientKind
    var stops: [GradientStop]
}

struct WallpaperPreset: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var label: String
    var fullAssetName: String
    var thumbAssetName: String
    var customURL: URL? = nil
    var isVideo: Bool = false

    var fullURL: URL? {
        if let customURL { return customURL }
        if isVideo, let videoURL = OpenRecorderResources.url(forResource: fullAssetName, withExtension: "mp4", subdirectory: "Wallpapers") {
            return videoURL
        }
        return OpenRecorderResources.url(forResource: fullAssetName, withExtension: "jpg", subdirectory: "Wallpapers")
    }

    var thumbURL: URL? {
        if let customURL { return customURL }
        return OpenRecorderResources.url(forResource: thumbAssetName, withExtension: "jpg", subdirectory: "Wallpapers/thumbs")
            ?? OpenRecorderResources.url(forResource: thumbAssetName, withExtension: "jpg", subdirectory: "Wallpapers")
    }
}

enum BackgroundStyle: Equatable, Hashable, Codable {
    case transparent
    case solid(SerializableColor)
    case gradient(GradientPreset)
    case wallpaper(WallpaperPreset)

    var isTransparent: Bool {
        if case .transparent = self { return true }
        return false
    }
}

enum BackgroundPresets {
    static let solidColors: [SerializableColor] = [
        SerializableColor(hex: "#090A0F"), // Deep Black / Obsidian
        SerializableColor(hex: "#12141C"), // Midnight Navy
        SerializableColor(hex: "#18181B"), // Zinc Dark
        SerializableColor(hex: "#0F172A"), // Slate Dark
        SerializableColor(hex: "#1C1917"), // Stone Dark
        SerializableColor(hex: "#022C22"), // Forest Dark
        SerializableColor(hex: "#1E1B4B"), // Indigo Dark
        SerializableColor(hex: "#2E1065"), // Purple Dark
        SerializableColor(hex: "#2563EB"), // Blue
        SerializableColor(hex: "#7C3AED"), // Violet
        SerializableColor(hex: "#DB2777"), // Rose
        SerializableColor(hex: "#EA580C"), // Orange
        SerializableColor(hex: "#16A34A"), // Emerald
        SerializableColor(hex: "#0D9488"), // Teal
        SerializableColor(hex: "#FFFFFF"), // Pure White
        SerializableColor(hex: "#64748B")  // Muted Slate
    ]

    static let gradients: [GradientPreset] = [
        GradientPreset(
            id: "studio-blue",
            kind: .linear(angleDegrees: 135),
            stops: [
                GradientStop(color: SerializableColor(red: 0.11, green: 0.17, blue: 0.25), position: 0),
                GradientStop(color: SerializableColor(red: 0.03, green: 0.04, blue: 0.06), position: 1)
            ]
        ),
        GradientPreset(
            id: "studio-purple",
            kind: .linear(angleDegrees: 135),
            stops: [
                GradientStop(color: SerializableColor(red: 0.12, green: 0.10, blue: 0.19), position: 0),
                GradientStop(color: SerializableColor(red: 0.02, green: 0.03, blue: 0.05), position: 1)
            ]
        ),
        GradientPreset(
            id: "studio-green",
            kind: .linear(angleDegrees: 135),
            stops: [
                GradientStop(color: SerializableColor(red: 0.10, green: 0.18, blue: 0.14), position: 0),
                GradientStop(color: SerializableColor(red: 0.03, green: 0.04, blue: 0.04), position: 1)
            ]
        ),
        GradientPreset(
            id: "studio-amber",
            kind: .linear(angleDegrees: 135),
            stops: [
                GradientStop(color: SerializableColor(red: 0.20, green: 0.18, blue: 0.14), position: 0),
                GradientStop(color: SerializableColor(red: 0.05, green: 0.04, blue: 0.04), position: 1)
            ]
        ),
        GradientPreset(
            id: "sunrise",
            kind: .linear(angleDegrees: 111.6),
            stops: [
                GradientStop(color: SerializableColor(red: 114/255, green: 167/255, blue: 232/255), position: 0.094),
                GradientStop(color: SerializableColor(red: 253/255, green: 129/255, blue: 82/255), position: 0.439),
                GradientStop(color: SerializableColor(red: 253/255, green: 129/255, blue: 82/255), position: 0.548),
                GradientStop(color: SerializableColor(red: 249/255, green: 202/255, blue: 86/255), position: 0.863)
            ]
        ),
        GradientPreset(
            id: "fresh-grass",
            kind: .linear(angleDegrees: 120),
            stops: [
                GradientStop(color: SerializableColor(hex: "#d4fc79"), position: 0),
                GradientStop(color: SerializableColor(hex: "#96e6a1"), position: 1)
            ]
        ),
        GradientPreset(
            id: "magenta-burst",
            kind: .radial(centerX: 0.032, centerY: 0.496),
            stops: [
                GradientStop(color: SerializableColor(red: 80/255, green: 12/255, blue: 139/255, alpha: 0.87), position: 0),
                GradientStop(color: SerializableColor(red: 161/255, green: 10/255, blue: 144/255, alpha: 0.72), position: 0.836)
            ]
        ),
        GradientPreset(
            id: "ocean-sand",
            kind: .linear(angleDegrees: 111.6),
            stops: [
                GradientStop(color: SerializableColor(red: 0/255, green: 56/255, blue: 68/255), position: 0),
                GradientStop(color: SerializableColor(red: 163/255, green: 217/255, blue: 185/255), position: 0.515),
                GradientStop(color: SerializableColor(red: 231/255, green: 148/255, blue: 6/255), position: 0.886)
            ]
        ),
        GradientPreset(
            id: "warm-citrus",
            kind: .linear(angleDegrees: 107.7),
            stops: [
                GradientStop(color: SerializableColor(red: 235/255, green: 230/255, blue: 44/255, alpha: 0.55), position: 0.084),
                GradientStop(color: SerializableColor(red: 252/255, green: 152/255, blue: 15/255), position: 0.903)
            ]
        ),
        GradientPreset(
            id: "spring-meadow",
            kind: .linear(angleDegrees: 91),
            stops: [
                GradientStop(color: SerializableColor(red: 72/255, green: 154/255, blue: 78/255), position: 0.052),
                GradientStop(color: SerializableColor(red: 251/255, green: 206/255, blue: 70/255), position: 0.959)
            ]
        ),
        GradientPreset(
            id: "deep-teal",
            kind: .radial(centerX: 0.10, centerY: 0.20),
            stops: [
                GradientStop(color: SerializableColor(red: 2/255, green: 37/255, blue: 78/255), position: 0),
                GradientStop(color: SerializableColor(red: 4/255, green: 56/255, blue: 126/255), position: 0.197),
                GradientStop(color: SerializableColor(red: 85/255, green: 245/255, blue: 221/255), position: 1)
            ]
        ),
        GradientPreset(
            id: "midnight-cyan",
            kind: .linear(angleDegrees: 109.6),
            stops: [
                GradientStop(color: SerializableColor(red: 15/255, green: 2/255, blue: 2/255), position: 0.112),
                GradientStop(color: SerializableColor(red: 36/255, green: 163/255, blue: 190/255), position: 0.911)
            ]
        ),
        GradientPreset(
            id: "peach-blue",
            kind: .linear(angleDegrees: 135),
            stops: [
                GradientStop(color: SerializableColor(hex: "#FBC8B4"), position: 0),
                GradientStop(color: SerializableColor(hex: "#2447B1"), position: 1)
            ]
        ),
        GradientPreset(
            id: "magenta-lime",
            kind: .linear(angleDegrees: 109.6),
            stops: [
                GradientStop(color: SerializableColor(hex: "#F635A6"), position: 0),
                GradientStop(color: SerializableColor(hex: "#36D860"), position: 1)
            ]
        ),
        GradientPreset(
            id: "red-green",
            kind: .linear(angleDegrees: 90),
            stops: [
                GradientStop(color: SerializableColor(hex: "#FF0101"), position: 0),
                GradientStop(color: SerializableColor(hex: "#4DFF01"), position: 1)
            ]
        ),
        GradientPreset(
            id: "crimson-violet",
            kind: .linear(angleDegrees: 315),
            stops: [
                GradientStop(color: SerializableColor(hex: "#EC0101"), position: 0),
                GradientStop(color: SerializableColor(hex: "#5044A9"), position: 1)
            ]
        ),
        GradientPreset(
            id: "blush",
            kind: .linear(angleDegrees: 45),
            stops: [
                GradientStop(color: SerializableColor(hex: "#ff9a9e"), position: 0),
                GradientStop(color: SerializableColor(hex: "#fad0c4"), position: 0.99),
                GradientStop(color: SerializableColor(hex: "#fad0c4"), position: 1)
            ]
        ),
        GradientPreset(
            id: "lavender-rose",
            kind: .linear(angleDegrees: 0),
            stops: [
                GradientStop(color: SerializableColor(hex: "#a18cd1"), position: 0),
                GradientStop(color: SerializableColor(hex: "#fbc2eb"), position: 1)
            ]
        ),
        GradientPreset(
            id: "coral-spectrum",
            kind: .linear(angleDegrees: 90),
            stops: [
                GradientStop(color: SerializableColor(hex: "#ff8177"), position: 0),
                GradientStop(color: SerializableColor(hex: "#ff867a"), position: 0),
                GradientStop(color: SerializableColor(hex: "#ff8c7f"), position: 0.21),
                GradientStop(color: SerializableColor(hex: "#f99185"), position: 0.52),
                GradientStop(color: SerializableColor(hex: "#cf556c"), position: 0.78),
                GradientStop(color: SerializableColor(hex: "#b12a5b"), position: 1)
            ]
        ),
        GradientPreset(
            id: "mint-sky",
            kind: .linear(angleDegrees: 120),
            stops: [
                GradientStop(color: SerializableColor(hex: "#84fab0"), position: 0),
                GradientStop(color: SerializableColor(hex: "#8fd3f4"), position: 1)
            ]
        ),
        GradientPreset(
            id: "ocean-current",
            kind: .linear(angleDegrees: 90),
            stops: [
                GradientStop(color: SerializableColor(hex: "#4facfe"), position: 0),
                GradientStop(color: SerializableColor(hex: "#00f2fe"), position: 1)
            ]
        ),
        GradientPreset(
            id: "northern-lights",
            kind: .linear(angleDegrees: 0),
            stops: [
                GradientStop(color: SerializableColor(hex: "#fcc5e4"), position: 0),
                GradientStop(color: SerializableColor(hex: "#fda34b"), position: 0.15),
                GradientStop(color: SerializableColor(hex: "#ff7882"), position: 0.35),
                GradientStop(color: SerializableColor(hex: "#c8699e"), position: 0.52),
                GradientStop(color: SerializableColor(hex: "#7046aa"), position: 0.71),
                GradientStop(color: SerializableColor(hex: "#0c1db8"), position: 0.87),
                GradientStop(color: SerializableColor(hex: "#020f75"), position: 1)
            ]
        ),
        GradientPreset(
            id: "raspberry-lemon",
            kind: .linear(angleDegrees: 90),
            stops: [
                GradientStop(color: SerializableColor(hex: "#fa709a"), position: 0),
                GradientStop(color: SerializableColor(hex: "#fee140"), position: 1)
            ]
        ),
        GradientPreset(
            id: "deep-cosmos",
            kind: .linear(angleDegrees: 0),
            stops: [
                GradientStop(color: SerializableColor(hex: "#30cfd0"), position: 0),
                GradientStop(color: SerializableColor(hex: "#330867"), position: 1)
            ]
        ),
        GradientPreset(
            id: "candy-floss",
            kind: .linear(angleDegrees: 0),
            stops: [
                GradientStop(color: SerializableColor(hex: "#c471f5"), position: 0),
                GradientStop(color: SerializableColor(hex: "#fa71cd"), position: 1)
            ]
        ),
        GradientPreset(
            id: "salmon-stripe",
            kind: .linear(angleDegrees: 90),
            stops: [
                GradientStop(color: SerializableColor(hex: "#f78ca0"), position: 0),
                GradientStop(color: SerializableColor(hex: "#f9748f"), position: 0.19),
                GradientStop(color: SerializableColor(hex: "#fd868c"), position: 0.60),
                GradientStop(color: SerializableColor(hex: "#fe9a8b"), position: 1)
            ]
        ),
        GradientPreset(
            id: "denim-sky",
            kind: .linear(angleDegrees: 0),
            stops: [
                GradientStop(color: SerializableColor(hex: "#48c6ef"), position: 0),
                GradientStop(color: SerializableColor(hex: "#6f86d6"), position: 1)
            ]
        ),
        GradientPreset(
            id: "electric-blue",
            kind: .linear(angleDegrees: 90),
            stops: [
                GradientStop(color: SerializableColor(hex: "#0acffe"), position: 0),
                GradientStop(color: SerializableColor(hex: "#495aff"), position: 1)
            ]
        )
    ]

    static let wallpapers: [WallpaperPreset] = [
        WallpaperPreset(id: "wallpaper-10", label: "Midnight Mountain", fullAssetName: "wallpaper10", thumbAssetName: "wallpaper10"),
        WallpaperPreset(id: "mountaintrees", label: "Mountain Trees", fullAssetName: "mountaintrees", thumbAssetName: "mountaintrees"),
        WallpaperPreset(id: "wallpaper-14", label: "Dark Flow", fullAssetName: "wallpaper14", thumbAssetName: "wallpaper14"),
        WallpaperPreset(id: "wallpaper-13", label: "Midnight Swirl", fullAssetName: "wallpaper13", thumbAssetName: "wallpaper13"),
        WallpaperPreset(id: "luisdelrio", label: "Deep Forest", fullAssetName: "luisdelrio", thumbAssetName: "luisdelrio"),
        WallpaperPreset(id: "wallpaper-3", label: "Dusk Dunes", fullAssetName: "wallpaper3", thumbAssetName: "wallpaper3"),
        WallpaperPreset(id: "wallpaper-1", label: "Dark Aurora", fullAssetName: "wallpaper1", thumbAssetName: "wallpaper1"),
        WallpaperPreset(id: "wallpaper-7", label: "Night Sky", fullAssetName: "wallpaper7", thumbAssetName: "wallpaper7"),
        WallpaperPreset(id: "wallpaper-8", label: "Crimson Night", fullAssetName: "wallpaper8", thumbAssetName: "wallpaper8"),
        WallpaperPreset(id: "wallpaper-12", label: "Misty Horizon", fullAssetName: "wallpaper12", thumbAssetName: "wallpaper12"),
        WallpaperPreset(id: "cityscape", label: "Cityscape", fullAssetName: "cityscape", thumbAssetName: "cityscape"),
        WallpaperPreset(id: "farmvalley", label: "Farm Valley", fullAssetName: "farmvalley", thumbAssetName: "farmvalley"),
        WallpaperPreset(id: "levels", label: "Levels", fullAssetName: "levels", thumbAssetName: "levels"),
        WallpaperPreset(id: "wallpaper-2", label: "Wallpaper 2", fullAssetName: "wallpaper2", thumbAssetName: "wallpaper2"),
        WallpaperPreset(id: "wallpaper-4", label: "Wallpaper 4", fullAssetName: "wallpaper4", thumbAssetName: "wallpaper4"),
        WallpaperPreset(id: "wallpaper-5", label: "Wallpaper 5", fullAssetName: "wallpaper5", thumbAssetName: "wallpaper5"),
        WallpaperPreset(id: "wallpaper-6", label: "Wallpaper 6", fullAssetName: "wallpaper6", thumbAssetName: "wallpaper6"),
        WallpaperPreset(id: "wallpaper-9", label: "Wallpaper 9", fullAssetName: "wallpaper9", thumbAssetName: "wallpaper9"),
        WallpaperPreset(id: "wallpaper-11", label: "Wallpaper 11", fullAssetName: "wallpaper11", thumbAssetName: "wallpaper11"),
        WallpaperPreset(id: "wallpaper-15", label: "Wallpaper 15", fullAssetName: "wallpaper15", thumbAssetName: "wallpaper15"),
        WallpaperPreset(id: "wallpaper-16", label: "Wallpaper 16", fullAssetName: "wallpaper16", thumbAssetName: "wallpaper16"),
        WallpaperPreset(id: "wallpaper-17", label: "Wallpaper 17", fullAssetName: "wallpaper17", thumbAssetName: "wallpaper17"),
        WallpaperPreset(id: "wallpaper-18", label: "Wallpaper 18", fullAssetName: "wallpaper18", thumbAssetName: "wallpaper18")
    ]

    static let videoLoops: [WallpaperPreset] = [
        WallpaperPreset(id: "loop-aurora", label: "Aurora", fullAssetName: "wallpaper1", thumbAssetName: "wallpaper1", isVideo: true),
        WallpaperPreset(id: "loop-particles", label: "Particles", fullAssetName: "wallpaper2", thumbAssetName: "wallpaper2", isVideo: true),
        WallpaperPreset(id: "loop-cyber", label: "Cyber Neon", fullAssetName: "wallpaper3", thumbAssetName: "wallpaper3", isVideo: true),
        WallpaperPreset(id: "loop-mesh", label: "Gradient Mesh", fullAssetName: "wallpaper4", thumbAssetName: "wallpaper4", isVideo: true)
    ]

    static let `default`: BackgroundStyle = .wallpaper(wallpapers[0])
}

enum BackgroundStylePresetKind: String, CaseIterable, Identifiable {
    case wallpaper
    case video
    case color
    case gradient
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallpaper: "Image"
        case .video: "Video"
        case .color: "Color"
        case .gradient: "Gradient"
        case .transparent: "None"
        }
    }

    var helpText: String {
        switch self {
        case .wallpaper: "Image Wallpapers"
        case .video: "Video Loops"
        case .color: "Solid Colors"
        case .gradient: "Gradients"
        case .transparent: "Transparent (No background)"
        }
    }

    var symbolName: String {
        switch self {
        case .wallpaper: "photo"
        case .video: "video.fill"
        case .color: "paintpalette.fill"
        case .gradient: "circle.lefthalf.filled.righthalf.striped.horizontal"
        case .transparent: "square.dashed"
        }
    }

    var accentColor: Color {
        switch self {
        case .wallpaper: Color(red: 0.28, green: 0.58, blue: 1.00)  // Sky Blue
        case .video: Color(red: 0.68, green: 0.42, blue: 1.00)      // Vivid Purple
        case .color: Color(red: 1.00, green: 0.62, blue: 0.22)      // Amber Orange
        case .gradient: Color(red: 1.00, green: 0.38, blue: 0.68)   // Rose Pink
        case .transparent: Color(red: 0.70, green: 0.74, blue: 0.82) // Slate
        }
    }
}

extension BackgroundStyle {
    var presetKind: BackgroundStylePresetKind {
        switch self {
        case .transparent: .transparent
        case .solid: .color
        case .gradient: .gradient
        case let .wallpaper(preset): preset.isVideo ? .video : .wallpaper
        }
    }
}

extension GradientPreset {
    func unitEndpoints() -> (start: UnitPoint, end: UnitPoint) {
        switch kind {
        case let .linear(angle):
            let radians = angle * .pi / 180
            let dx = sin(radians) * 0.5
            let dy = -cos(radians) * 0.5
            return (
                UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
            )
        case let .radial(cx, cy):
            return (UnitPoint(x: cx, y: cy), UnitPoint(x: cx, y: cy))
        }
    }

    func endpoints(in rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        switch kind {
        case let .linear(angle):
            let radians = angle * .pi / 180
            let dx = sin(radians) * 0.5
            let dy = -cos(radians) * 0.5
            let startU = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
            let endU = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
            return (
                CGPoint(x: rect.minX + startU.x * rect.width, y: rect.minY + startU.y * rect.height),
                CGPoint(x: rect.minX + endU.x * rect.width, y: rect.minY + endU.y * rect.height)
            )
        case let .radial(cx, cy):
            let center = CGPoint(x: rect.minX + cx * rect.width, y: rect.minY + cy * rect.height)
            return (center, center)
        }
    }

    func radialRadius(in rect: CGRect) -> CGFloat {
        guard case let .radial(cx, cy) = kind else { return 0 }
        let center = CGPoint(x: rect.minX + cx * rect.width, y: rect.minY + cy * rect.height)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        return corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0
    }

    var sortedStops: [GradientStop] {
        stops.sorted { $0.position < $1.position }
    }

    var swiftUIStops: [Gradient.Stop] {
        sortedStops.map { Gradient.Stop(color: $0.color.color, location: CGFloat($0.position)) }
    }
}

enum WallpaperImageCache {
    private static let storage = CacheStorage()

    static func image(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = storage.imageCache.object(forKey: key) {
            return cached
        }
        if let image = NSImage(contentsOf: url) {
            storage.imageCache.setObject(image, forKey: key)
            return image
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            storage.imageCache.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    static func cgImage(for url: URL) -> CGImage? {
        let key = url.path as NSString
        if let cached = storage.cgImageCache.object(forKey: key) {
            return cached.value
        }
        guard let image = image(for: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        storage.cgImageCache.setObject(CGImageBox(value: cg), forKey: key)
        return cg
    }

    private final class CacheStorage: @unchecked Sendable {
        let imageCache = NSCache<NSString, NSImage>()
        let cgImageCache = NSCache<NSString, CGImageBox>()
    }

    private final class CGImageBox: @unchecked Sendable {
        let value: CGImage
        init(value: CGImage) { self.value = value }
    }
}
