import AppKit
import AVFoundation
import AVKit
import SwiftUI

struct BackgroundPickerView: View {
    @Binding var selection: BackgroundStyle
    var includeTransparent: Bool
    var showsTopDivider: Bool

    @State private var activeKind: BackgroundStylePresetKind
    @State private var hoveredKind: BackgroundStylePresetKind?

    private let tileCornerRadius: CGFloat = 6
    private let tileHeight: CGFloat = 34
    private let tileSpacing: CGFloat = 6

    init(selection: Binding<BackgroundStyle>, includeTransparent: Bool = true, showsTopDivider: Bool = true) {
        self._selection = selection
        self.includeTransparent = includeTransparent
        self.showsTopDivider = showsTopDivider
        self._activeKind = State(initialValue: selection.wrappedValue.presetKind)
    }

    private var availableKinds: [BackgroundStylePresetKind] {
        if includeTransparent {
            BackgroundStylePresetKind.allCases
        } else {
            BackgroundStylePresetKind.allCases.filter { $0 != .transparent }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("BACKGROUND")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.fgSubtle)

                Spacer(minLength: 0)

                StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                    withAnimation(.snappy(duration: 0.28)) {
                        selection = BackgroundPresets.default
                        activeKind = .wallpaper
                    }
                } label: {
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.fgSubtle)
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 12) {
                // Clean icon-only tab switcher + inline Upload button
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        ForEach(availableKinds) { kind in
                            let isSelected = activeKind == kind
                            StudioButton(hitTarget: .rounded(6), help: kind.helpText) {
                                activate(kind)
                            } label: {
                                Image(systemName: kind.symbolName)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(
                                        isSelected
                                            ? Color.white
                                            : (hoveredKind == kind ? Color.white : Theme.fgMuted)
                                    )
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .onHover { isHovering in
                                hoveredKind = isHovering ? kind : (hoveredKind == kind ? nil : hoveredKind)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    StudioButton(hitTarget: .rounded(6), help: "Upload custom background image or video") {
                        chooseCustomFile()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.fgMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }

                // Content Grid
                switch activeKind {
                case .wallpaper:
                    wallpaperGrid
                        .transaction { $0.animation = nil }
                case .video:
                    videoGrid
                        .transaction { $0.animation = nil }
                case .color:
                    colorGrid
                        .transaction { $0.animation = nil }
                case .gradient:
                    gradientGrid
                        .transaction { $0.animation = nil }
                case .transparent:
                    transparentNote
                        .transaction { $0.animation = nil }
                }
            }
            .padding(.bottom, 18)
            .animation(.snappy(duration: 0.34), value: activeKind)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selection) { _, newValue in
            let incoming = newValue.presetKind
            if activeKind != incoming {
                withAnimation(.snappy(duration: 0.34)) {
                    activeKind = incoming
                }
            }
        }
    }

    private func chooseCustomFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .movie, .quickTimeMovie, .mpeg4Movie, .png, .jpeg]
        if panel.runModal() == .OK, let url = panel.url {
            let isVideo = ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
            let customPreset = WallpaperPreset(
                id: "custom-\(UUID().uuidString)",
                label: url.deletingPathExtension().lastPathComponent,
                fullAssetName: "",
                thumbAssetName: "",
                customURL: url,
                isVideo: isVideo
            )
            withAnimation(.snappy(duration: 0.28)) {
                selection = .wallpaper(customPreset)
                activeKind = isVideo ? .video : .wallpaper
            }
        }
    }

    private func activate(_ kind: BackgroundStylePresetKind) {
        withAnimation(.snappy(duration: 0.34)) {
            activeKind = kind
            switch kind {
            case .gradient:
                if case .gradient = selection { return }
                selection = .gradient(BackgroundPresets.gradients[0])
            case .color:
                if case .solid = selection { return }
                selection = .solid(BackgroundPresets.solidColors[0])
            case .wallpaper:
                if case let .wallpaper(preset) = selection, !preset.isVideo { return }
                if let first = BackgroundPresets.wallpapers.first {
                    selection = .wallpaper(first)
                }
            case .video:
                if case let .wallpaper(preset) = selection, preset.isVideo { return }
                if let first = BackgroundPresets.videoLoops.first {
                    selection = .wallpaper(first)
                }
            case .transparent:
                selection = .transparent
            }
        }
    }

    private var selectedGradientID: String? {
        if case let .gradient(preset) = selection { return preset.id }
        return nil
    }

    private var selectedColor: SerializableColor? {
        if case let .solid(color) = selection { return color }
        return nil
    }

    private var selectedWallpaperID: String? {
        if case let .wallpaper(preset) = selection { return preset.id }
        return nil
    }

    private var gradientGrid: some View {
        LazyVGrid(columns: fourColumnGridItems, spacing: tileSpacing) {
            ForEach(BackgroundPresets.gradients) { preset in
                StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                    selection = .gradient(preset)
                } label: {
                    GradientSwatch(preset: preset)
                        .frame(maxWidth: .infinity)
                        .frame(height: tileHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                .stroke(
                                    selectedGradientID == preset.id ? Color.white : Theme.borderStrong.opacity(0.55),
                                    lineWidth: selectedGradientID == preset.id ? 2 : 1
                                )
                        }
                        .shadow(color: selectedGradientID == preset.id ? Color.white.opacity(0.35) : Color.clear, radius: 4, y: 1)
                }
                .help(preset.id.replacingOccurrences(of: "-", with: " ").capitalized)
            }
        }
    }

    private var colorGrid: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: fourColumnGridItems, spacing: tileSpacing) {
                ForEach(BackgroundPresets.solidColors.indices, id: \.self) { index in
                    let swatch = BackgroundPresets.solidColors[index]
                    StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                        selection = .solid(swatch)
                    } label: {
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .fill(swatch.color)
                            .frame(maxWidth: .infinity)
                            .frame(height: tileHeight)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                    .stroke(
                                        selectedColor == swatch ? Color.white : Theme.borderStrong.opacity(0.55),
                                        lineWidth: selectedColor == swatch ? 2 : 1
                                    )
                            }
                            .shadow(color: selectedColor == swatch ? Color.white.opacity(0.35) : Color.clear, radius: 4, y: 1)
                    }
                    .help(swatch.hexString)
                }
            }

            HStack(spacing: 8) {
                ColorPicker("Custom Solid Color", selection: Binding(
                    get: { selectedColor?.color ?? Color.black },
                    set: { newColor in
                        selection = .solid(SerializableColor(NSColor(newColor)))
                    }
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
            }
            .padding(.top, 4)
        }
    }

    private var videoGrid: some View {
        LazyVGrid(columns: fourColumnGridItems, spacing: tileSpacing) {
            ForEach(BackgroundPresets.videoLoops) { preset in
                StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                    selection = .wallpaper(preset)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        WallpaperThumbnail(preset: preset)
                            .frame(maxWidth: .infinity)
                            .frame(height: tileHeight)

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .padding(3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .stroke(
                                selectedWallpaperID == preset.id ? Color.white : Theme.borderStrong.opacity(0.55),
                                lineWidth: selectedWallpaperID == preset.id ? 2 : 1
                            )
                    }
                    .shadow(color: selectedWallpaperID == preset.id ? Color.white.opacity(0.35) : Color.clear, radius: 4, y: 1)
                }
                .help(preset.label)
            }
        }
    }

    private var wallpaperGrid: some View {
        LazyVGrid(columns: fourColumnGridItems, spacing: tileSpacing) {
            ForEach(BackgroundPresets.wallpapers) { preset in
                StudioButton(hitTarget: .rounded(Theme.radiusSm)) {
                    selection = .wallpaper(preset)
                } label: {
                    WallpaperThumbnail(preset: preset)
                        .frame(maxWidth: .infinity)
                        .frame(height: tileHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                                .stroke(
                                    selectedWallpaperID == preset.id ? Color.white : Theme.borderStrong.opacity(0.55),
                                    lineWidth: selectedWallpaperID == preset.id ? 2 : 1
                                )
                        }
                        .shadow(color: selectedWallpaperID == preset.id ? Color.white.opacity(0.35) : Color.clear, radius: 4, y: 1)
                }
                .help(preset.label)
            }
        }
    }

    private var fourColumnGridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 44), spacing: tileSpacing), count: 4)
    }

    private var transparentNote: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), help: "Transparent background") {
            selection = .transparent
        } label: {
            HStack(spacing: 11) {
                Checkerboard()
                    .frame(width: 56, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                            .stroke(Theme.borderStrong.opacity(0.72), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("No background")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.fg.opacity(0.92))
                    Text("Exports preserve alpha")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.fgMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.overlay.opacity(0.72), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(Color.white.opacity(0.60), lineWidth: 1)
            }
        }
    }
}

struct GradientSwatch: View {
    let preset: GradientPreset

    var body: some View {
        switch preset.kind {
        case .linear:
            let endpoints = preset.unitEndpoints()
            return AnyView(
                Rectangle().fill(
                    LinearGradient(
                        gradient: Gradient(stops: preset.swiftUIStops),
                        startPoint: endpoints.start,
                        endPoint: endpoints.end
                    )
                )
            )
        case let .radial(cx, cy):
            return AnyView(
                GeometryReader { proxy in
                    let endRadius = max(proxy.size.width, proxy.size.height)
                    Rectangle().fill(
                        RadialGradient(
                            gradient: Gradient(stops: preset.swiftUIStops),
                            center: UnitPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: endRadius
                        )
                    )
                }
            )
        }
    }
}

struct WallpaperThumbnail: View {
    let preset: WallpaperPreset

    var body: some View {
        GeometryReader { proxy in
            thumbnailContent
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let url = preset.thumbURL, let image = WallpaperImageCache.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.secondary)
                }
        }
    }
}

struct BackgroundFillView: View {
    let style: BackgroundStyle

    var body: some View {
        switch style {
        case .transparent:
            Checkerboard()
        case let .solid(color):
            color.color
        case let .gradient(preset):
            GeometryReader { proxy in
                gradientView(for: preset, in: proxy.size)
            }
        case let .wallpaper(preset):
            WallpaperFill(preset: preset)
        }
    }

    @ViewBuilder
    private func gradientView(for preset: GradientPreset, in size: CGSize) -> some View {
        switch preset.kind {
        case .linear:
            let endpoints = preset.unitEndpoints()
            LinearGradient(
                gradient: Gradient(stops: preset.swiftUIStops),
                startPoint: endpoints.start,
                endPoint: endpoints.end
            )
        case let .radial(cx, cy):
            let endRadius = hypot(size.width, size.height)
            RadialGradient(
                gradient: Gradient(stops: preset.swiftUIStops),
                center: UnitPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: endRadius
            )
        }
    }
}

struct VideoBackgroundPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let player = AVQueuePlayer()
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.wantsLayer = true
        view.layer?.addSublayer(playerLayer)

        let item = AVPlayerItem(url: url)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        context.coordinator.looper = looper
        context.coordinator.player = player
        player.isMuted = true
        player.play()

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
            layer.frame = nsView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
}

struct WallpaperFill: View {
    let preset: WallpaperPreset

    var body: some View {
        Group {
            if let url = preset.fullURL {
                let ext = url.pathExtension.lowercased()
                if preset.isVideo && (ext == "mp4" || ext == "mov" || ext == "m4v") {
                    VideoBackgroundPlayerView(url: url)
                } else if let image = WallpaperImageCache.image(for: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Theme.surfaceRaised
                }
            } else {
                Theme.surfaceRaised
            }
        }
        .clipped()
    }
}
