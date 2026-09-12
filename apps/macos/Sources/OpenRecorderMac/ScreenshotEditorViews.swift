import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI

struct ScreenshotEditorStudioView: View {
    @EnvironmentObject private var model: AppModel
    var screenshotURL: URL?
    var projectPath: String?
    var editorTitle: String?
    var initialScreenshotState: ScreenshotEditorState?
    var editorSessionID: UUID?
    var workspace: EditorWorkspaceDriver
    var editor: ScreenshotEditorDriver
    var exportRequest: EditorExportRequest?
    @State private var sidebarWidth: CGFloat = 320
    @State private var activeInspector: InspectorTab = .appearance
    @State private var sceneEndpoint: SceneEndpoint = .start
    @State private var sceneTool: SceneTool = .tilt
    @State private var image: NSImage?
    @State private var animationPlaying = false
    @State private var animationExportPresented = false
    @State private var animationDraft = VideoExportDraftState()

    var body: some View {
        StudioSplitPane(
            axis: .horizontal,
            secondarySize: sidebarWidth,
            minPrimarySize: 520,
            minSecondarySize: 280,
            maxSecondarySize: 440,
            spacing: 0
        ) {
            VStack(spacing: 0) {
                if activeInspector == .scene { SceneCanvasTools(tool: $sceneTool) }
                Group {
                    if editor.state.screenshot.scene.isActive || editor.state.screenshot.canvasAspect != .auto {
                        SceneScreenshotPreview(image: image, state: editor.state.screenshot, time: editor.scenePreviewTime)
                    } else {
                        ScreenshotCanvas(image: image, background: editor.state.screenshot.background,
                            padding: editor.state.screenshot.padding, backgroundRoundness: editor.state.screenshot.backgroundRoundness,
                            backgroundShadow: editor.state.screenshot.backgroundShadow,
                            imageRoundness: editor.state.screenshot.imageRoundness, imageShadow: editor.state.screenshot.imageShadow)
                    }
                }
                .modifier(SceneCanvasGesture(enabled: activeInspector == .scene, tool: sceneTool,
                    pose: scenePoseBinding(settings: editor.binding(for: \.scene), endpoint: sceneEndpoint),
                    onEditingChanged: handleUndoTransaction))
                if editor.state.screenshot.scene.motion.enabled {
                    HStack {
                        Button { animationPlaying.toggle() } label: {
                            Image(systemName: animationPlaying ? "pause.fill" : "play.fill")
                        }.help(animationPlaying ? "Pause animation" : "Play animation")
                        Slider(value: Binding(get: { editor.scenePreviewTime }, set: { animationPlaying = false; editor.scenePreviewTime = $0 }),
                               in: 0...editor.state.screenshot.scene.imageDuration)
                        Text(String(format: "%.2fs", editor.scenePreviewTime)).monospacedDigit().font(.caption)
                    }.padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } secondary: {
            HStack(spacing: 0) {
                VStack(spacing: 14) {
                    ForEach([InspectorTab.appearance, .scene]) { tab in
                        Button { activeInspector = tab } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tab.symbolName).font(.system(size: 16))
                                Text(tab.shortTitle).font(.system(size: 9.5))
                            }.foregroundStyle(activeInspector == tab ? Theme.fg : Theme.fgMuted)
                                .frame(width: 46, height: 46)
                        }.buttonStyle(.plain).help(tab.helpText)
                    }
                    Spacer()
                }.padding(.top, 14).frame(width: 50).background(Theme.railBg)
                if activeInspector == .scene {
                    VStack(spacing: 0) {
                        ScrollView {
                            SceneInspector(settings: editor.binding(for: \.scene), endpoint: $sceneEndpoint,
                                duration: editor.state.screenshot.scene.imageDuration, isImage: true,
                                seek: { animationPlaying = false; editor.scenePreviewTime = $0 }, onEditingChanged: handleUndoTransaction)
                                .padding(14)
                        }
                        HStack {
                            Button("Copy PNG") { editor.copyComposedPNG(image: image) }
                            Spacer()
                            Menu("Export") {
                                Button("Save PNG…") { editor.saveComposedPNG(image: image, suggestedFileName: suggestedExportFileName, sourceURL: screenshotURL) }
                                Button("Export Animation…") { presentAnimationExport() }
                            }
                        }.controlSize(.small).padding(10)
                    }
                } else {
                    ScreenshotSettingsPanel(
                        background: editor.binding(for: \.background),
                        padding: editor.binding(for: \.padding),
                        backgroundRoundness: editor.binding(for: \.backgroundRoundness),
                        backgroundShadow: editor.binding(for: \.backgroundShadow),
                        imageRoundness: editor.binding(for: \.imageRoundness),
                        imageShadow: editor.binding(for: \.imageShadow),
                        canvasAspect: editor.binding(for: \.canvasAspect),
                        onAnimateExport: { presentAnimationExport() },
                        onEditingChanged: handleUndoTransaction,
                        onRevealFile: {
                            if let screenshotURL {
                                model.reveal(screenshotURL.path)
                            }
                        },
                        onExport: {
                            editor.send(.exportRequested)
                        },
                        onSave: {
                            editor.saveComposedPNG(image: image, suggestedFileName: suggestedExportFileName, sourceURL: screenshotURL)
                        },
                        onCopy: {
                            editor.copyComposedPNG(image: image)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.appBg)
        .sheet(isPresented: editor.exportDialogBinding) {
            ScreenshotExportDialog(
                onSave: {
                    editor.saveComposedPNG(image: image, suggestedFileName: suggestedExportFileName, sourceURL: screenshotURL)
                },
                onCopy: {
                    editor.copyComposedPNG(image: image)
                }
            )
            .frame(width: 420)
        }
        .sheet(isPresented: $animationExportPresented) { animationExportDialog }
        .task(id: screenshotURL) { image = screenshotURL.flatMap { NSImage(contentsOf: $0) }; editor.scenePreviewTime = 0; animationPlaying = false }
        .task(id: animationPlaying) {
            guard animationPlaying else { return }
            if editor.scenePreviewTime >= editor.state.screenshot.scene.imageDuration { editor.scenePreviewTime = 0 }
            let start = Date().timeIntervalSinceReferenceDate - editor.scenePreviewTime
            while !Task.isCancelled && animationPlaying {
                editor.scenePreviewTime = min(editor.state.screenshot.scene.imageDuration, Date().timeIntervalSinceReferenceDate - start)
                if editor.scenePreviewTime >= editor.state.screenshot.scene.imageDuration { animationPlaying = false; break }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        .onChange(of: editor.state.screenshot.scene) { _, _ in animationPlaying = false }
        .onChange(of: editor.state.screenshot.scene.imageDuration) { _, duration in
            editor.binding(for: \.scene).wrappedValue = editor.state.screenshot.scene.clamped(to: duration)
            editor.scenePreviewTime = min(editor.scenePreviewTime, duration)
        }
        .onChange(of: exportRequest?.id) { _, requestID in
            guard requestID != nil, isScreenshotExportRequestTarget else { return }
            editor.send(.exportRequested)
        }
        .onChange(of: screenshotURL) { _, _ in
            syncEditorSession()
        }
        .onChange(of: editorSessionID) { _, _ in
            syncEditorSession()
        }
        .onChange(of: editor.state.screenshot) { _, _ in
            editor.send(.autosaveSnapshotChanged(autosaveSnapshot))
        }
        .onAppear {
            editor.configure(
                saveHandler: { [weak model] snapshot in
                    guard let model else { throw CancellationError() }
                    return try await model.autosaveProject(snapshot)
                },
                statusHandler: { [weak workspace, weak model] status in
                    workspace?.handleProjectAutosaveStatus(status, source: .screenshot)
                    model?.handleProjectAutosaveStatus(status)
                },
                setWorkspaceStatus: { [weak workspace] status in
                    workspace?.send(.statusUpdated(status))
                }
            )
            syncEditorSession()
        }
        .onDisappear {
            editor.send(.disappeared(autosaveSnapshot))
        }
    }

    private func presentAnimationExport() {
        animationPlaying = false
        workspace.videoExport.clear()
        animationDraft = VideoExportDraftState()
        animationExportPresented = true
    }

    private var animationExportDialog: some View {
        let exporter = workspace.videoExport
        return VideoExportDialog(phase: exporter.state.phase, progress: exporter.state.progress,
            errorMessage: exporter.state.errorMessage, exportedFileName: exporter.state.exportedFileName,
            isExporting: exporter.state.isExporting, resolution: $animationDraft.resolution,
            format: Binding(get: { animationDraft.format }, set: { animationDraft.setFormat($0) }),
            frameRate: $animationDraft.frameRate, quality: $animationDraft.quality,
            gifSize: $animationDraft.gifSize, gifLoops: $animationDraft.gifLoops,
            mediaLabel: "Animation",
            onExport: {
                var options = animationDraft.currentOptions
                options.screenshotState = editor.state.screenshot
                exporter.export(sourceURL: screenshotURL, options: options, edits: .empty)
            }, onRetrySave: { exporter.send(.retrySaveRequested) }, onShowInFinder: { exporter.send(.revealRequested) },
            onCancelExport: { exporter.send(.cancelRequested) }, onClose: { animationExportPresented = false })
            .frame(width: 520).interactiveDismissDisabled(exporter.state.phase.isBusy)
    }

    private var suggestedExportFileName: String {
        ScreenshotExportRenderer.suggestedFileName(for: screenshotURL)
    }

    private func handleUndoTransaction(_ isEditing: Bool) {
        if isEditing {
            animationPlaying = false
            editor.beginUndoTransaction()
        } else {
            editor.endUndoTransaction()
        }
    }

    private func syncEditorSession() {
        editor.send(.sessionChanged(ScreenshotEditorSessionContext(
            screenshotURL: screenshotURL,
            projectPath: projectPath,
            editorTitle: editorTitle,
            initialScreenshotState: initialScreenshotState,
            editorSessionID: editorSessionID
        )))
    }

    private var autosaveSnapshot: ProjectAutosaveSnapshot? {
        editor.autosaveSnapshot(
            projectPath: projectPath,
            screenshotURL: screenshotURL,
            editorTitle: editorTitle
        )
    }

    private var isScreenshotExportRequestTarget: Bool {
        guard let screenshotURL else { return false }
        if let requestedEditorSessionID = exportRequest?.editorSessionID {
            return requestedEditorSessionID == editorSessionID
        }
        if let requestedURL = exportRequest?.url {
            return requestedURL == screenshotURL
        }
        return true
    }
}

struct ScreenshotExportDialog: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: () -> Void
    var onCopy: () -> Void
    @State private var pendingChoice: ScreenshotExportChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            exportHeader

            HStack(spacing: 10) {
                ScreenshotExportActionCard(
                    title: "Save",
                    subtitle: "Choose a folder",
                    symbolName: "square.and.arrow.down",
                    isPrimary: true
                ) {
                    pendingChoice = .save
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)

                ScreenshotExportActionCard(
                    title: "Copy",
                    subtitle: "Put PNG on clipboard",
                    symbolName: "doc.on.doc",
                    isPrimary: false
                ) {
                    pendingChoice = .copy
                    dismiss()
                }
                .keyboardShortcut("c", modifiers: .command)
            }

            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(22)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                LinearGradient(
                    colors: [Color.white.opacity(0.055), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .onDisappear(perform: performPendingChoice)
    }

    private func performPendingChoice() {
        let choice = pendingChoice
        pendingChoice = nil
        switch choice {
        case .save:
            onSave()
        case .copy:
            onCopy()
        case nil:
            break
        }
    }

    private var exportHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Export PNG")
                    .font(.system(size: 17, weight: .semibold))
                Text("Save the composed image or copy it for sharing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

enum ScreenshotExportChoice: Equatable {
    case save
    case copy
}

private struct ScreenshotExportActionCard: View {
    var title: String
    var subtitle: String
    var symbolName: String
    var isPrimary: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isPrimary ? Color.white : Theme.accent)
                    .background(isPrimary ? Color.white.opacity(0.16) : Theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(isPrimary ? Color.white.opacity(0.74) : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 102)
            .padding(.horizontal, 13)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(isPrimary ? Theme.accent : Theme.overlayStrong.opacity(0.72))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(isPrimary ? 0.18 : 0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.24) : Theme.borderStrong.opacity(0.72), lineWidth: 1)
            }
        }
        .shadow(color: isPrimary ? Theme.accent.opacity(0.24) : Color.clear, radius: 10, y: 4)
    }
}

struct ScreenshotCanvas: View {
    var image: NSImage?
    var background: BackgroundStyle
    var padding: Double
    var backgroundRoundness: Double
    var backgroundShadow: Double
    var imageRoundness: Double
    var imageShadow: Double

    var body: some View {
        ZStack {
            if let image {
                screenshotStage(image)
                    .padding(32)
            } else {
                EmptyEditorState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .studioEditorPaneChrome()
    }

    private func screenshotStage(_ image: NSImage) -> some View {
        GeometryReader { proxy in
            let layout = ScreenshotCompositionLayout(
                configuration: exportConfiguration,
                imageSize: Self.logicalSize(for: image),
                styleScale: 1
            )
            let previewScale = layout.displayScale(toFit: proxy.size)
            let backgroundSize = CGSize(
                width: layout.backgroundRect.width * previewScale,
                height: layout.backgroundRect.height * previewScale
            )
            let imageSize = CGSize(
                width: layout.imageRect.width * previewScale,
                height: layout.imageRect.height * previewScale
            )

            ZStack {
                BackgroundFillView(style: background)
                    .frame(width: backgroundSize.width, height: backgroundSize.height)
                    .clipShape(RoundedRectangle(
                        cornerRadius: layout.backgroundRoundness * previewScale,
                        style: .continuous
                    ))
                    .shadow(
                        color: Color.black.opacity(0.45 * backgroundShadow),
                        radius: 34 * backgroundShadow * previewScale,
                        y: 14 * backgroundShadow * previewScale
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: layout.backgroundRoundness * previewScale,
                            style: .continuous
                        )
                        .stroke(Theme.border, lineWidth: 1)
                    }

                Image(nsImage: image)
                    .resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
                    .clipShape(RoundedRectangle(
                        cornerRadius: layout.imageRoundness * previewScale,
                        style: .continuous
                    ))
                    .shadow(
                        color: Color.black.opacity(0.55 * imageShadow),
                        radius: 38 * imageShadow * previewScale,
                        y: 18 * imageShadow * previewScale
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var exportConfiguration: ScreenshotExportConfiguration {
        ScreenshotExportConfiguration(screenshotState: ScreenshotEditorState(
            background: background,
            padding: padding,
            backgroundRoundness: backgroundRoundness,
            backgroundShadow: backgroundShadow,
            imageRoundness: imageRoundness,
            imageShadow: imageShadow
        ))
    }

    private static func logicalSize(for image: NSImage) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return CGSize(width: cgImage.width, height: cgImage.height)
            }
            return CGSize(width: 1, height: 1)
        }
        return size
    }
}

struct ScreenshotSettingsPanel: View {
    @Binding var background: BackgroundStyle
    @Binding var padding: Double
    @Binding var backgroundRoundness: Double
    @Binding var backgroundShadow: Double
    @Binding var imageRoundness: Double
    @Binding var imageShadow: Double
    @Binding var canvasAspect: VideoPreviewAspectPreset
    var onAnimateExport: () -> Void = {}
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onRevealFile: () -> Void = {}
    var onExport: () -> Void
    var onSave: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    CanvasAspectPicker(selection: $canvasAspect)
                    BackgroundPickerView(selection: $background)
                    InspectorGroup(title: "Background Layer", symbolName: "rectangle.fill") {
                        InspectorSlider(title: "Padding", valueText: "\(Int(padding))px", value: $padding, range: 0...140, step: 1, onEditingChanged: onEditingChanged)
                        InspectorSlider(title: "Roundness", valueText: "\(Int(backgroundRoundness))px", value: $backgroundRoundness, range: 0...64, step: 1, onEditingChanged: onEditingChanged)
                        InspectorSlider(title: "Shadow", valueText: "\(Int(backgroundShadow * 100))%", value: $backgroundShadow, range: 0...1, step: 0.01, onEditingChanged: onEditingChanged)
                    }
                    InspectorGroup(title: "Image Layer", symbolName: "photo") {
                        InspectorSlider(title: "Roundness", valueText: "\(Int(imageRoundness))px", value: $imageRoundness, range: 0...48, step: 1, onEditingChanged: onEditingChanged)
                        InspectorSlider(title: "Shadow", valueText: "\(Int(imageShadow * 100))%", value: $imageShadow, range: 0...1, step: 0.01, onEditingChanged: onEditingChanged)
                    }
                }
                .padding(14)
            }

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack(spacing: 8) {
                InspectorFooterButton(title: "Reveal File", symbolName: "folder") {
                    onRevealFile()
                }
                if let onSave, let onCopy {
                    ScreenshotExportMenu(onAnimate: onAnimateExport, onSave: onSave, onCopy: onCopy)
                } else {
                    InspectorFooterButton(title: "Export", symbolName: "square.and.arrow.up") {
                        onExport()
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.025))
        }
        .studioEditorPaneChrome(bg: Theme.sidebarBg)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshot Settings")
                    .font(.system(size: 14, weight: .semibold))
                Text("Separate background and image layer styling.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                .stroke(Theme.overlay)
        }
    }

}

private struct ScreenshotExportMenu: View {
    var onAnimate: () -> Void = {}
    var onSave: () -> Void
    var onCopy: () -> Void

    var body: some View {
        Menu {
            Button("Export Animation…", action: onAnimate)
            Divider()
            Button(action: onSave) {
                Label("Save PNG…", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(action: onCopy) {
                Label("Copy PNG", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(Theme.fgMuted)
                .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Export screenshot")
        .help("Export screenshot")
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 18
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0...rows {
                for column in 0...columns {
                    let isLight = (row + column).isMultiple(of: 2)
                    let rect = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(isLight ? Theme.borderStrong : Theme.border))
                }
            }
        }
        .background(Color.black.opacity(0.25))
    }
}
