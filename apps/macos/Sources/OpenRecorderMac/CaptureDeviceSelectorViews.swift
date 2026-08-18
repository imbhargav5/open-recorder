import SwiftUI

enum CaptureDeviceSelectorWindowMetrics {
    static let width: CGFloat = 380
    static let height: CGFloat = 400
    static let minWidth: CGFloat = 340
    static let minHeight: CGFloat = 300
}

private enum CaptureDeviceDialogSelection: Hashable {
    case noInput
    case systemDefault
    case device(String)
}

struct MicrophoneSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var pendingSelection: CaptureDeviceDialogSelection = .systemDefault
    private var options: CaptureOptionsState {
        model.captureOptions.state
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .overlay(Theme.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    if options.deviceLoadPhase == .loading {
                        ProgressView("Checking microphones…")
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    }

                    CaptureDeviceOptionRow(
                        title: "No Microphone",
                        subtitle: "Do not record microphone audio",
                        symbolName: "mic.slash",
                        isSelected: pendingSelection == .noInput,
                        isDisabled: !options.canChangeOptions
                    ) {
                        pendingSelection = .noInput
                    }

                    CaptureDeviceOptionRow(
                        title: "System Default",
                        subtitle: options.microphoneDevices.isEmpty
                            ? "No default microphone is currently available"
                            : "Follow the current macOS default",
                        symbolName: "sparkles",
                        isSelected: pendingSelection == .systemDefault,
                        isDisabled: !options.canChangeOptions || options.microphoneDevices.isEmpty
                    ) {
                        pendingSelection = .systemDefault
                    }

                    if case .device(let selectedID) = pendingSelection,
                       !options.microphoneDevices.contains(where: { $0.id == selectedID }) {
                        CaptureDeviceOptionRow(
                            title: "Previously Selected Microphone",
                            subtitle: "This device is no longer available",
                            symbolName: "exclamationmark.triangle",
                            isSelected: true,
                            isDisabled: true
                        ) {}
                    }

                    ForEach(options.microphoneDevices) { device in
                        CaptureDeviceOptionRow(
                            title: device.name,
                            subtitle: device.isDefault ? "Current macOS default" : "Audio Input",
                            symbolName: "mic.fill",
                            isSelected: pendingSelection == .device(device.id),
                            isDisabled: !options.canChangeOptions
                        ) {
                            pendingSelection = .device(device.id)
                        }
                    }

                    deviceLoadMessage(emptyMessage: "No microphones are available.")
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .overlay(Theme.borderSubtle)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised.opacity(0.6))
        }
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .onAppear {
            resetPendingMicrophoneSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose Microphone")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("Pick the audio input to use for recordings.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted)
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                model.cancelMicrophoneSelection()
                dismissWindow(id: "microphone-selector")
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .frame(height: Theme.btnHeightMd)
                    .padding(.horizontal, Theme.space4)
                    .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    }
                    .foregroundStyle(Theme.fgMuted)
            }
            .keyboardShortcut(.cancelAction)

            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                applyMicrophoneSelection()
            } label: {
                Text("Save")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: Theme.btnHeightMd)
                    .padding(.horizontal, Theme.space5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 2)
            }
            .disabled(!canApplyMicrophoneSelection)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func applyMicrophoneSelection() {
        switch pendingSelection {
        case .noInput:
            model.selectNoMicrophoneInput()
        case .systemDefault:
            model.selectMicrophoneDevice(nil)
        case .device(let deviceID):
            model.selectMicrophoneDevice(deviceID)
        }
        dismissWindow(id: "microphone-selector")
    }

    private var canApplyMicrophoneSelection: Bool {
        guard options.canChangeOptions else { return false }
        return switch pendingSelection {
        case .noInput:
            true
        case .systemDefault:
            !options.microphoneDevices.isEmpty
        case .device(let deviceID):
            options.microphoneDevices.contains { $0.id == deviceID }
        }
    }

    private func resetPendingMicrophoneSelection() {
        guard options.includeMicrophone else {
            pendingSelection = .noInput
            return
        }
        if let selectedMicrophoneDeviceID = options.selectedMicrophoneDeviceID {
            pendingSelection = .device(selectedMicrophoneDeviceID)
        } else {
            pendingSelection = .systemDefault
        }
    }

    @ViewBuilder
    private func deviceLoadMessage(emptyMessage: String) -> some View {
        switch options.deviceLoadPhase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.statusError)
                .padding(.vertical, 8)
        case .loaded where options.microphoneDevices.isEmpty:
            Label(emptyMessage, systemImage: "mic.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
                .padding(.vertical, 8)
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }
}

struct CameraSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var pendingSelection: CaptureDeviceDialogSelection = .systemDefault
    private var options: CaptureOptionsState {
        model.captureOptions.state
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()
                .overlay(Theme.borderSubtle)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    if options.deviceLoadPhase == .loading {
                        ProgressView("Checking cameras…")
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    }

                    CaptureDeviceOptionRow(
                        title: "No Camera",
                        subtitle: "Do not record facecam video",
                        symbolName: "video.slash",
                        isSelected: pendingSelection == .noInput,
                        isDisabled: !options.canChangeOptions
                    ) {
                        pendingSelection = .noInput
                    }

                    CaptureDeviceOptionRow(
                        title: "System Default",
                        subtitle: options.cameraDevices.isEmpty
                            ? "No default camera is currently available"
                            : "Follow the current macOS default",
                        symbolName: "sparkles",
                        isSelected: pendingSelection == .systemDefault,
                        isDisabled: !options.canChangeOptions || options.cameraDevices.isEmpty
                    ) {
                        pendingSelection = .systemDefault
                    }

                    if case .device(let selectedID) = pendingSelection,
                       !options.cameraDevices.contains(where: { $0.id == selectedID }) {
                        CaptureDeviceOptionRow(
                            title: "Previously Selected Camera",
                            subtitle: "This device is no longer available",
                            symbolName: "exclamationmark.triangle",
                            isSelected: true,
                            isDisabled: true
                        ) {}
                    }

                    ForEach(options.cameraDevices) { device in
                        CaptureDeviceOptionRow(
                            title: device.name,
                            subtitle: device.isDefault ? "Current macOS default" : "Video Camera",
                            symbolName: "video.fill",
                            isSelected: pendingSelection == .device(device.id),
                            isDisabled: !options.canChangeOptions
                        ) {
                            pendingSelection = .device(device.id)
                        }
                    }

                    deviceLoadMessage(emptyMessage: "No cameras are available.")
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .overlay(Theme.borderSubtle)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised.opacity(0.6))
        }
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .onAppear {
            resetPendingCameraSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose Camera")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("Pick the camera to use for the next recording.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted)
            }

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                model.cancelCameraSelection()
                dismissWindow(id: "camera-selector")
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .frame(height: Theme.btnHeightMd)
                    .padding(.horizontal, Theme.space4)
                    .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    }
                    .foregroundStyle(Theme.fgMuted)
            }
            .keyboardShortcut(.cancelAction)

            StudioButton(hitTarget: .rounded(Theme.radiusMd)) {
                applyCameraSelection()
            } label: {
                Text("Save")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: Theme.btnHeightMd)
                    .padding(.horizontal, Theme.space5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 2)
            }
            .disabled(!canApplyCameraSelection)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func applyCameraSelection() {
        switch pendingSelection {
        case .noInput:
            model.selectNoCameraInput()
        case .systemDefault:
            model.selectCameraDevice(nil)
        case .device(let deviceID):
            model.selectCameraDevice(deviceID)
        }
        dismissWindow(id: "camera-selector")
    }

    private var canApplyCameraSelection: Bool {
        guard options.canChangeOptions else { return false }
        return switch pendingSelection {
        case .noInput:
            true
        case .systemDefault:
            !options.cameraDevices.isEmpty
        case .device(let deviceID):
            options.cameraDevices.contains { $0.id == deviceID }
        }
    }

    private func resetPendingCameraSelection() {
        guard options.includeCamera else {
            pendingSelection = .noInput
            return
        }
        if let selectedCameraDeviceID = options.selectedCameraDeviceID {
            pendingSelection = .device(selectedCameraDeviceID)
        } else {
            pendingSelection = .systemDefault
        }
    }

    @ViewBuilder
    private func deviceLoadMessage(emptyMessage: String) -> some View {
        switch options.deviceLoadPhase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.statusError)
                .padding(.vertical, 8)
        case .loaded where options.cameraDevices.isEmpty:
            Label(emptyMessage, systemImage: "video.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
                .padding(.vertical, 8)
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }
}

private struct CaptureDeviceOptionRow: View {
    var title: String
    var subtitle: String
    var symbolName: String
    var isSelected: Bool
    var isDisabled: Bool = false
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : (isDisabled ? Theme.fgSubtle : Theme.fgMuted))
                    .frame(width: 28, height: 28)
                    .background(
                        isSelected ? Theme.accent.opacity(0.18) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : (isDisabled ? Theme.fgSubtle : Theme.fg))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Theme.fgMuted : Theme.fgSubtle)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Circle()
                        .stroke(Theme.borderSubtle, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isSelected ? Theme.accent.opacity(0.12) : (isHovering && !isDisabled ? Color.white.opacity(0.05) : Theme.overlay.opacity(0.5)),
                in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(
                        isSelected ? Theme.accent.opacity(0.50) : (isHovering && !isDisabled ? Theme.borderStrong : Theme.borderSubtle),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .disabled(isDisabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
