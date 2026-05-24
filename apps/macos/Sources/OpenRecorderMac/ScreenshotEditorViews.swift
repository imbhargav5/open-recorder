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
    var editor: ScreenshotEditorDriver
    var exportRequest: EditorExportRequest?
    @State private var sidebarWidth: CGFloat = 320

    var body: some View {
        ResizableStudioSplitPane(
            secondarySize: $sidebarWidth,
            minPrimarySize: 520,
            minSecondarySize: 280,
            maxSecondarySize: 440
        ) {
            ScreenshotCanvas(
                image: image,
                background: editor.state.screenshot.background,
                padding: editor.state.screenshot.padding,
                backgroundRoundness: editor.state.screenshot.backgroundRoundness,
                backgroundShadow: editor.state.screenshot.backgroundShadow,
                imageRoundness: editor.state.screenshot.imageRoundness,
                imageShadow: editor.state.screenshot.imageShadow
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } secondary: {
            ScreenshotSettingsPanel(
                background: editor.binding(for: \.background),
                padding: editor.binding(for: \.padding),
                backgroundRoundness: editor.binding(for: \.backgroundRoundness),
                backgroundShadow: editor.binding(for: \.backgroundShadow),
                imageRoundness: editor.binding(for: \.imageRoundness),
                imageShadow: editor.binding(for: \.imageShadow),
                onEditingChanged: handleUndoTransaction,
                onRevealFile: {
                    if let screenshotURL {
                        model.reveal(screenshotURL.path)
                    }
                },
                onExport: {
                    editor.send(.exportRequested)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .background(Theme.appBgMuted)
        .sheet(isPresented: editor.exportDialogBinding) {
            ScreenshotExportDialog(
                onSave: {
                    editor.saveComposedPNG(image: image, suggestedFileName: suggestedExportFileName)
                },
                onCopy: {
                    editor.copyComposedPNG(image: image)
                }
            )
            .frame(width: 420)
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
                saveHandler: { snapshot in
                    try await model.autosaveProject(snapshot)
                },
                statusHandler: { status in
                    model.handleProjectAutosaveStatus(status)
                },
                setStatusMessage: { message in
                    model.statusMessage = message
                }
            )
            syncEditorSession()
        }
        .onDisappear {
            editor.send(.disappeared(autosaveSnapshot))
        }
    }

    private var image: NSImage? {
        guard let url = screenshotURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var suggestedExportFileName: String {
        ScreenshotExportRenderer.suggestedFileName(for: screenshotURL)
    }

    private func handleUndoTransaction(_ isEditing: Bool) {
        if isEditing {
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
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onSave()
                    }
                }

                ScreenshotExportActionCard(
                    title: "Copy",
                    subtitle: "Put PNG on clipboard",
                    symbolName: "doc.on.doc",
                    isPrimary: false
                ) {
                    onCopy()
                    dismiss()
                }
            }

            StudioButton(hitTarget: .rectangle) {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
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
    }

    private var exportHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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

private struct ScreenshotExportActionCard: View {
    var title: String
    var subtitle: String
    var symbolName: String
    var isPrimary: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(12), action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(isPrimary ? Color.white : Theme.accent)
                    .background(isPrimary ? Color.white.opacity(0.16) : Theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPrimary ? Theme.accent : Theme.overlayStrong.opacity(0.72))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(isPrimary ? 0.18 : 0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.20) : Theme.borderSubtle, lineWidth: 1)
            }
            .shadow(color: isPrimary ? Theme.accent.opacity(0.24) : Color.clear, radius: 10, y: 4)
        }
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
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onRevealFile: () -> Void = {}
    var onExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
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
                InspectorFooterButton(title: "Export", symbolName: "square.and.arrow.up") {
                    onExport()
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.025))
        }
        .studioEditorPaneChrome()
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "photo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

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
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.overlay)
        }
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
