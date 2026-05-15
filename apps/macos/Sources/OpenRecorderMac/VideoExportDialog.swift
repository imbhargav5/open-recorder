import SwiftUI

struct VideoExportDialog: View {
    @State private var resolution: VideoExportResolution = VideoExportResolution.defaultExportOption
    @State private var format: VideoExportFormat = .mov
    @State private var frameRate: VideoExportFrameRate = VideoExportFrameRate.defaultExportOption
    var phase: VideoExportPhase
    var progress: Double
    var errorMessage: String?
    var exportedFileName: String?
    var isExporting: Bool
    var initialOptions: VideoExportOptions = .default
    var onExport: (VideoExportOptions) -> Void
    var onRetrySave: () -> Void
    var onShowInFinder: () -> Void
    var onCancelExport: () -> Void
    var onClose: () -> Void
    @State private var didApplyInitialOptions = false

    private var canEditOptions: Bool {
        phase == .idle || phase == .failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        .padding(20)
        .background(Color.studioPanel)
        .onAppear {
            guard !didApplyInitialOptions else { return }
            resolution = resolutionOptions.contains(initialOptions.resolution) ? initialOptions.resolution : VideoExportResolution.defaultExportOption
            format = initialOptions.format
            frameRate = VideoExportFrameRate.exportOptions.contains(initialOptions.frameRate) ? initialOptions.frameRate : VideoExportFrameRate.defaultExportOption
            didApplyInitialOptions = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerSymbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 38, height: 38)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage, phase == .failed {
                ExportMessageRow(symbolName: "xmark.circle.fill", message: errorMessage, tint: .red)
            }

            settingsPanel
            idleActions
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progressTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(selectedExportSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(VideoExportProgressPresentation.percentText(for: displayedProgress))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: displayedProgress, total: 1)
                    .progressViewStyle(.linear)
                    .tint(Color.brand)
            }
            .padding(12)
            .background(Color.studioCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.studioBorder)
            }

            if phase == .exporting {
                HStack {
                    Spacer(minLength: 0)
                    ExportDialogButton(
                        title: "Cancel Export",
                        systemImage: "xmark.circle",
                        kind: .destructive,
                        minWidth: 132,
                        action: onCancelExport
                    )
                }
            }
        }
    }

    private var retrySaveContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ExportMessageRow(
                symbolName: "exclamationmark.triangle.fill",
                message: errorMessage ?? "Save dialog canceled. Click Save Again to save without re-exporting.",
                tint: .orange
            )

            HStack(spacing: 10) {
                ExportDialogButton(
                    title: "Discard Export",
                    kind: .secondary,
                    minWidth: 124,
                    action: onClose
                )
                Spacer(minLength: 0)
                ExportDialogButton(
                    title: "Save Again",
                    systemImage: "square.and.arrow.down",
                    kind: .primary,
                    minWidth: 128,
                    action: onRetrySave
                )
            }
        }
    }

    private var successContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ExportMessageRow(
                symbolName: "checkmark.circle.fill",
                message: exportedFileName.map { "Saved \($0)" } ?? "Video saved successfully.",
                tint: .green
            )

            HStack(spacing: 10) {
                ExportDialogButton(
                    title: "Done",
                    kind: .secondary,
                    minWidth: 96,
                    action: onClose
                )
                Spacer(minLength: 0)
                ExportDialogButton(
                    title: "Show in Finder",
                    systemImage: "folder",
                    kind: .primary,
                    minWidth: 144,
                    action: onShowInFinder
                )
            }
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            ExportPickerSettingRow(
                title: "Resolution",
                detail: resolution.detail,
                selection: $resolution,
                options: resolutionOptions,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            ExportDivider()
            ExportPickerSettingRow(
                title: "Frame Rate",
                detail: frameRate.detail,
                selection: $frameRate,
                options: VideoExportFrameRate.exportOptions,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            ExportDivider()
            ExportStaticSettingRow(
                title: "Format",
                detail: "QuickTime movie (.mov)",
                value: format.title
            )
        }
        .background(Color.studioCard, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
    }

    private var idleActions: some View {
        HStack(spacing: 10) {
            ExportDialogButton(
                title: "Cancel",
                kind: .secondary,
                minWidth: 96,
                isDisabled: isExporting,
                action: onClose
            )

            Spacer(minLength: 0)

            ExportDialogButton(
                title: isExporting ? "Exporting…" : "Export Video",
                systemImage: "square.and.arrow.down",
                kind: .primary,
                minWidth: 136,
                isDisabled: isExporting
            ) {
                onExport(currentOptions)
            }
        }
    }

    private var currentOptions: VideoExportOptions {
        VideoExportOptions(
            resolution: resolution,
            format: format,
            frameRate: frameRate,
            styling: .none,
            cropSelection: initialOptions.cropSelection,
            customOutputSize: resolution == .custom ? initialOptions.customOutputSize : nil,
            cursorOverlay: initialOptions.cursorOverlay,
            cursorTelemetryURL: initialOptions.cursorTelemetryURL
        )
    }

    private var selectedExportSummary: String {
        "\(resolution.title) \(format.title) · \(frameRate.title)"
    }

    private var displayedProgress: Double {
        switch phase {
        case .saving:
            1
        case .exporting:
            min(VideoExportProgressPresentation.clamped(progress), 0.99)
        case .idle, .savePending, .success, .failed:
            VideoExportProgressPresentation.clamped(progress)
        }
    }

    private var progressTitle: String {
        switch phase {
        case .saving:
            "Ready to Save"
        case .exporting where displayedProgress <= 0.01:
            "Preparing Video"
        case .exporting:
            "Rendering Video"
        case .idle, .savePending, .success, .failed:
            "Export Video"
        }
    }

    private var headerSymbolName: String {
        switch phase {
        case .success: "checkmark.circle"
        case .savePending, .failed: "exclamationmark.triangle"
        case .exporting, .saving, .idle: "arrow.down.circle"
        }
    }

    private var resolutionOptions: [VideoExportResolution] {
        VideoExportResolution.exportOptions
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
        case .exporting: "\(VideoExportProgressPresentation.percentText(for: displayedProgress)) · \(selectedExportSummary)"
        case .saving: "Choose where to save the completed MOV."
        case .savePending: "Save without rendering again."
        case .success: "Your MOV export is ready."
        case .failed: "Adjust settings and try again."
        case .idle: selectedExportSummary
        }
    }
}

enum VideoExportProgressPresentation {
    static func clamped(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    static func percentText(for progress: Double) -> String {
        "\(Int((clamped(progress) * 100).rounded()))%"
    }
}

private struct ExportPickerSettingRow<Option: Hashable & Identifiable>: View {
    var title: String
    var detail: String
    @Binding var selection: Option
    var options: [Option]
    var optionTitle: KeyPath<Option, String>
    var isDisabled = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option[keyPath: optionTitle])
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .disabled(isDisabled)
            .frame(width: 118, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

private struct ExportStaticSettingRow: View {
    var title: String
    var detail: String
    var value: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 58)
                .frame(height: 28)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.08))
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

private struct ExportDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.studioBorder)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

private enum ExportDialogButtonKind {
    case primary
    case secondary
    case destructive

    var background: Color {
        switch self {
        case .primary: Color.brand
        case .secondary: Color.white.opacity(0.055)
        case .destructive: Color.red.opacity(0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .primary: Color.white
        case .secondary: Color.primary
        case .destructive: Color.red
        }
    }

    var border: Color {
        switch self {
        case .primary: Color.brand.opacity(0.45)
        case .secondary: Color.studioBorder
        case .destructive: Color.red.opacity(0.24)
        }
    }
}

private struct ExportDialogButton: View {
    var title: String
    var systemImage: String?
    var kind: ExportDialogButtonKind
    var minWidth: CGFloat = 96
    var isDisabled = false
    var action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        kind: ExportDialogButtonKind,
        minWidth: CGFloat = 96,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.minWidth = minWidth
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kind.foreground)
            .frame(minWidth: minWidth)
            .frame(height: 38)
            .padding(.horizontal, 12)
            .background(kind.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(kind.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
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
