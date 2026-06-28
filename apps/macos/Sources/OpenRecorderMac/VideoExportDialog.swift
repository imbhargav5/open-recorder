import SwiftUI

struct VideoExportDialog: View {
    var phase: VideoExportPhase
    var progress: Double
    var errorMessage: String?
    var exportedFileName: String?
    var isExporting: Bool
    @Binding var resolution: VideoExportResolution
    @Binding var format: VideoExportFormat
    @Binding var frameRate: VideoExportFrameRate
    @Binding var quality: VideoExportQuality
    @Binding var gifSize: VideoExportGIFSize
    @Binding var gifLoops: Bool
    var onExport: () -> Void
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
            exportSummaryCard

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
        .animation(.snappy(duration: 0.20), value: phase)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerSymbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 17, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var exportSummaryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(format == .gif ? "GIF export" : "Movie export")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(format == .gif ? "Animated for quick sharing" : "Optimized for screen recordings")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ExportSummaryMetric(title: "Size", value: selectedSizeTitle)
                ExportSummaryMetric(title: "Rate", value: frameRate.title)
                ExportSummaryMetric(title: "Type", value: format.title)
            }
        }
        .padding(11)
        .background(Theme.overlay.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.borderSubtle, lineWidth: 1)
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
                    .tint(Theme.accent)
            }
            .padding(12)
            .background(Theme.surfaceRaised.opacity(0.86), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.borderSubtle)
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
                message: errorMessage ?? VideoExportCopy.saveDialogCanceled,
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
                symbolName: "doc.badge.gearshape",
                title: "Format",
                detail: format.detail,
                selection: $format,
                options: VideoExportFormat.allCases,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            ExportDivider()
            if format == .gif {
                gifSettings
            } else {
                movieSettings
            }
        }
        .background(Theme.surfaceRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.borderStrong.opacity(0.56))
        }
    }

    private var movieSettings: some View {
        VStack(spacing: 0) {
            ExportPickerSettingRow(
                symbolName: "rectangle.arrowtriangle.2.inward",
                title: "Resolution",
                detail: resolution.detail,
                selection: $resolution,
                options: resolutionOptions,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            ExportDivider()
            ExportPickerSettingRow(
                symbolName: "speedometer",
                title: "Frame Rate",
                detail: frameRate.detail,
                selection: $frameRate,
                options: frameRateOptions,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            if format == .mp4 {
                ExportDivider()
                ExportPickerSettingRow(
                    symbolName: "slider.horizontal.3",
                    title: "Quality",
                    detail: quality.detail,
                    selection: $quality,
                    options: VideoExportQuality.allCases,
                    optionTitle: \.title,
                    isDisabled: !canEditOptions
                )
            }
        }
    }

    private var gifSettings: some View {
        VStack(spacing: 0) {
            ExportPickerSettingRow(
                symbolName: "rectangle.resize",
                title: "Size",
                detail: gifSize.detail,
                selection: $gifSize,
                options: VideoExportGIFSize.allCases,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            ExportDivider()
            ExportPickerSettingRow(
                symbolName: "speedometer",
                title: "Frame Rate",
                detail: frameRate.detail,
                selection: $frameRate,
                options: frameRateOptions,
                optionTitle: \.title,
                isDisabled: !canEditOptions
            )
            ExportDivider()
            ExportToggleSettingRow(
                symbolName: "repeat",
                title: "Loop",
                detail: gifLoops ? "Repeat continuously." : "Play once.",
                isOn: $gifLoops,
                isDisabled: !canEditOptions
            )
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
                onExport()
            }
        }
    }

    private var selectedExportSummary: String {
        switch format {
        case .gif:
            "\(gifSize.title) \(format.title) · \(frameRate.title)"
        case .mp4:
            "\(resolution.title) \(format.title) · \(frameRate.title) · \(quality.title)"
        case .mov:
            "\(resolution.title) \(format.title) · \(frameRate.title)"
        }
    }

    private var selectedSizeTitle: String {
        format == .gif ? gifSize.title : resolution.title
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

    private var frameRateOptions: [VideoExportFrameRate] {
        VideoExportFrameRate.exportOptions(for: format)
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
        case .saving: "Choose where to save the completed \(format.title)."
        case .savePending: "Save without rendering again."
        case .success: "Your \(format.title) export is ready."
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

private struct ExportSummaryMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 48)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        }
    }
}

private struct ExportPickerSettingRow<Option: Hashable & Identifiable>: View {
    var symbolName: String
    var title: String
    var detail: String
    @Binding var selection: Option
    var options: [Option]
    var optionTitle: KeyPath<Option, String>
    var isDisabled = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
            .frame(width: 122, alignment: .trailing)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }
}

private struct ExportStaticSettingRow: View {
    var symbolName: String
    var title: String
    var detail: String
    var value: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                .background(Theme.overlayStrong.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.borderSubtle)
                }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }
}

private struct ExportToggleSettingRow: View {
    var symbolName: String
    var title: String
    var detail: String
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isDisabled)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
    }
}

private struct ExportDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

private enum ExportDialogButtonKind: Equatable {
    case primary
    case secondary
    case destructive

    var background: Color {
        switch self {
        case .primary: Theme.accent
        case .secondary: Theme.overlay
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
        case .primary: Theme.accent.opacity(0.45)
        case .secondary: Theme.border
        case .destructive: Color.red.opacity(0.24)
        }
    }
}

private struct ExportDialogButton: View {
    @State private var isHovering = false
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
            .frame(height: 40)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(kind.background)
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(kind == .primary ? 0.16 : 0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(kind.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(isHovering && !isDisabled ? 1.015 : 1)
            .brightness(isHovering && !isDisabled ? 0.035 : 0)
            .shadow(color: kind == .primary ? Theme.accent.opacity(0.22) : Color.clear, radius: 10, y: 4)
            .animation(.snappy(duration: 0.16), value: isHovering)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .onHover { hovering in
            isHovering = hovering
        }
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
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.24))
        }
    }
}
