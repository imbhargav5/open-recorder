import SwiftUI

enum CaptureDeviceSelectorWindowMetrics {
    static let width: CGFloat = 360
    static let height: CGFloat = 360
    static let minWidth: CGFloat = 320
    static let minHeight: CGFloat = 260
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
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .background(Theme.overlay, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.border, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose Microphone")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Pick the input to use for the next recording.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if options.deviceLoadPhase == .loading {
                        ProgressView("Checking microphones…")
                            .controlSize(.small)
                    }

                    Picker("Microphone", selection: $pendingSelection) {
                        CaptureDevicePickerLabel(
                            title: "No Microphone",
                            subtitle: "Do not record microphone audio"
                        )
                        .tag(CaptureDeviceDialogSelection.noInput)

                        CaptureDevicePickerLabel(
                            title: "System Default",
                            subtitle: options.microphoneDevices.isEmpty
                                ? "No default microphone is currently available"
                                : "Follow the current macOS default"
                        )
                        .tag(CaptureDeviceDialogSelection.systemDefault)
                        .disabled(options.microphoneDevices.isEmpty)

                        if case .device(let selectedID) = pendingSelection,
                           !options.microphoneDevices.contains(where: { $0.id == selectedID }) {
                            CaptureDevicePickerLabel(
                                title: "Previously Selected Microphone",
                                subtitle: "This device is no longer available"
                            )
                            .tag(CaptureDeviceDialogSelection.device(selectedID))
                            .disabled(true)
                        }

                        ForEach(options.microphoneDevices) { device in
                            CaptureDevicePickerLabel(
                                title: device.name,
                                subtitle: device.isDefault ? "Current macOS default" : "Microphone"
                            )
                            .tag(CaptureDeviceDialogSelection.device(device.id))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .accessibilityLabel("Microphone")
                    .disabled(!options.canChangeOptions)

                    deviceLoadMessage(emptyMessage: "No microphones are available.")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 220)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack {
                Spacer()
                StudioButton(hitTarget: .rounded(8)) {
                    model.cancelMicrophoneSelection()
                    dismissWindow(id: "microphone-selector")
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                StudioButton(hitTarget: .rounded(8)) {
                    applyMicrophoneSelection()
                } label: {
                    Text("OK")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(height: 34)
                        .padding(.horizontal, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .disabled(!canApplyMicrophoneSelection)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border)
        }
        .padding(16)
        .background(Theme.appBg.ignoresSafeArea())
        .onAppear {
            resetPendingMicrophoneSelection()
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
                .foregroundStyle(.secondary)
        case .loaded where options.microphoneDevices.isEmpty:
            Label(emptyMessage, systemImage: "mic.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
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
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .background(Theme.overlay, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.border, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose Camera")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Pick the camera to use for the next recording.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if options.deviceLoadPhase == .loading {
                        ProgressView("Checking cameras…")
                            .controlSize(.small)
                    }

                    Picker("Camera", selection: $pendingSelection) {
                        CaptureDevicePickerLabel(
                            title: "No Camera",
                            subtitle: "Do not record facecam video"
                        )
                        .tag(CaptureDeviceDialogSelection.noInput)

                        CaptureDevicePickerLabel(
                            title: "System Default",
                            subtitle: options.cameraDevices.isEmpty
                                ? "No default camera is currently available"
                                : "Follow the current macOS default"
                        )
                        .tag(CaptureDeviceDialogSelection.systemDefault)
                        .disabled(options.cameraDevices.isEmpty)

                        if case .device(let selectedID) = pendingSelection,
                           !options.cameraDevices.contains(where: { $0.id == selectedID }) {
                            CaptureDevicePickerLabel(
                                title: "Previously Selected Camera",
                                subtitle: "This device is no longer available"
                            )
                            .tag(CaptureDeviceDialogSelection.device(selectedID))
                            .disabled(true)
                        }

                        ForEach(options.cameraDevices) { device in
                            CaptureDevicePickerLabel(
                                title: device.name,
                                subtitle: device.isDefault ? "Current macOS default" : "Camera"
                            )
                            .tag(CaptureDeviceDialogSelection.device(device.id))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .accessibilityLabel("Camera")
                    .disabled(!options.canChangeOptions)

                    deviceLoadMessage(emptyMessage: "No cameras are available.")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 220)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            HStack {
                Spacer()
                StudioButton(hitTarget: .rounded(8)) {
                    model.cancelCameraSelection()
                    dismissWindow(id: "camera-selector")
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                StudioButton(hitTarget: .rounded(8)) {
                    applyCameraSelection()
                } label: {
                    Text("OK")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(height: 34)
                        .padding(.horizontal, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .disabled(!canApplyCameraSelection)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .background(Theme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border)
        }
        .padding(16)
        .background(Theme.appBg.ignoresSafeArea())
        .onAppear {
            resetPendingCameraSelection()
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
                .foregroundStyle(.secondary)
        case .loaded where options.cameraDevices.isEmpty:
            Label(emptyMessage, systemImage: "video.slash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        case .idle, .loading, .loaded:
            EmptyView()
        }
    }
}

private struct CaptureDevicePickerLabel: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}
