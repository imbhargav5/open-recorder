import SwiftUI

struct VideoExportDialog: View {
    @State private var resolution: VideoExportResolution = .source
    @State private var format: VideoExportFormat = .mov
    @State private var frameRate: VideoExportFrameRate = .source
    var phase: VideoExportPhase
    var progress: Double
    var errorMessage: String?
    var exportedFileName: String?
    var isExporting: Bool
    var onExport: (VideoExportOptions) -> Void
    var onRetrySave: () -> Void
    var onShowInFinder: () -> Void
    var onCancelExport: () -> Void
    var onClose: () -> Void

    private var canEditOptions: Bool {
        phase == .idle || phase == .failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            switch phase {
            case .exporting, .saving:
                progressContent
            case .savePending:
                retrySaveContent
            case .success:
                successContent
            case .idle, .failed:
                optionsContent
            }
        }
        .padding(18)
        .background(Color.studioPanel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: headerSymbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 34, height: 34)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let errorMessage, phase == .failed {
                ExportMessageRow(symbolName: "xmark.circle.fill", message: errorMessage, tint: .red)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Resolution")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(VideoExportResolution.allCases) { option in
                    ExportOptionRow(
                        title: option.title,
                        detail: option.detail,
                        isSelected: resolution == option,
                        isDisabled: !canEditOptions
                    ) {
                        resolution = option
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Format")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(VideoExportFormat.allCases) { option in
                    ExportOptionRow(
                        title: option.title,
                        detail: "QuickTime movie export.",
                        isSelected: format == option,
                        isDisabled: !canEditOptions
                    ) {
                        format = option
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Frame Rate")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(VideoExportFrameRate.allCases) { option in
                        ExportOptionRow(
                            title: option.title,
                            detail: option.detail,
                            isSelected: frameRate == option,
                            isDisabled: !canEditOptions
                        ) {
                            frameRate = option
                        }
                    }
                }
            }

            primaryActions
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text(phase == .saving ? "Waiting for save location…" : "Rendering video…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if phase == .exporting {
                Button {
                    onCancelExport()
                } label: {
                    Label("Cancel Export", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.red)
            }
        }
    }

    private var retrySaveContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExportMessageRow(
                symbolName: "exclamationmark.triangle.fill",
                message: errorMessage ?? "Save dialog canceled. Click Save Again to save without re-exporting.",
                tint: .orange
            )
            Button {
                onRetrySave()
            } label: {
                Label("Save Again", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.white)

            secondaryCloseButton(title: "Discard Export")
        }
    }

    private var successContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExportMessageRow(
                symbolName: "checkmark.circle.fill",
                message: exportedFileName.map { "Saved \($0)" } ?? "Video saved successfully.",
                tint: .green
            )
            Button {
                onShowInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.primary)

            secondaryCloseButton(title: "Done")
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 8) {
            Button {
                onExport(VideoExportOptions(resolution: resolution, format: format, frameRate: frameRate, styling: .none))
            } label: {
                Label(isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
            .padding(.horizontal, 12)
            .background(Color.brand.opacity(isExporting ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Color.white)

            secondaryCloseButton(title: "Cancel")
                .disabled(isExporting)
        }
    }

    private func secondaryCloseButton(title: String) -> some View {
        Button(title) {
            onClose()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private var headerSymbolName: String {
        switch phase {
        case .success: "checkmark.circle"
        case .savePending, .failed: "exclamationmark.triangle"
        case .exporting, .saving, .idle: "arrow.down.circle"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .exporting: "Exporting Video"
        case .saving: "Save Export"
        case .savePending: "Export Ready"
        case .success: "Export Complete"
        case .failed: "Export Failed"
        case .idle: "Export Video"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .exporting: "Rendering your MOV export."
        case .saving: "Choose where to save the completed MOV."
        case .savePending: "Save without rendering again."
        case .success: "Your MOV export is ready."
        case .failed: "Adjust settings and try again."
        case .idle: "Choose a MOV export size before saving."
        }
    }
}

private struct ExportOptionRow: View {
    var title: String
    var detail: String
    var isSelected: Bool
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.brand : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(isSelected ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.brand.opacity(0.35) : Color.studioBorder)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct ExportMessageRow: View {
    var symbolName: String
    var message: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.24))
        }
    }
}
