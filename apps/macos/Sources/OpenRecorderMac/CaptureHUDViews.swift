import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct CaptureHUD: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Binding var sourceTab: SourceSelectorTab

    var body: some View {
        HUDSurface(isRecording: model.capture.isRecording) {
            if model.captureMode == .recording {
                recordingControls
            } else {
                screenshotControls
            }
        }
    }

    private var recordingControls: some View {
        ViewThatFits(in: .horizontal) {
            fullRecordingControls
            compactRecordingControls
            narrowRecordingControls
        }
    }

    private var fullRecordingControls: some View {
        HStack(spacing: 8) {
            sharedLeadingControls

            FlowLabel(
                tone: model.capture.isRecording ? .red : .blue,
                label: model.capture.isRecording ? "Recording" : "Ready",
                value: model.capture.isRecording ? recordingPhaseLabel : "Video"
            )

            sourcePicker()
                .layoutPriority(2)

            permissionControls

            HUDDivider()

            HUDControlGroup {
                HUDToggle(symbolName: model.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", isActive: model.includeSystemAudio, title: "System Audio") {
                    model.includeSystemAudio.toggle()
                }
                HUDToggle(symbolName: model.includeMicrophone ? "mic.fill" : "mic.slash.fill", isActive: model.includeMicrophone, title: "Microphone") {
                    model.includeMicrophone.toggle()
                }
                deviceMenu(
                    symbolName: "mic.badge.plus",
                    title: "Microphone Device",
                    devices: model.microphoneDevices,
                    selectedDeviceID: $model.selectedMicrophoneDeviceID
                )
                HUDToggle(symbolName: model.includeCamera ? "video.fill" : "video.slash.fill", isActive: model.includeCamera, title: "Facecam") {
                    model.includeCamera.toggle()
                }
                deviceMenu(
                    symbolName: "video.badge.plus",
                    title: "Camera Device",
                    devices: model.cameraDevices,
                    selectedDeviceID: $model.selectedCameraDeviceID
                )
            }

            HUDPrimaryButton(
                title: model.capture.isRecording ? "Stop" : startStopTitle,
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                toggleRecording()
            }
        }
    }

    private var compactRecordingControls: some View {
        HStack(spacing: 6) {
            compactLeadingControls

            CompactFlowLabel(
                tone: model.capture.isRecording ? .red : .blue,
                value: model.capture.isRecording ? recordingPhaseLabel : "Video"
            )

            sourcePicker(width: 154, textWidth: 100)

            compactPermissionControls

            compactCaptureControlGroup

            HUDPrimaryButton(
                title: model.capture.isRecording ? "Stop" : startStopTitle,
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                toggleRecording()
            }
        }
    }

    private var narrowRecordingControls: some View {
        HStack(spacing: 6) {
            backButton

            StatusDot(tone: model.capture.isRecording ? .red : .blue)

            sourcePicker(width: 118, textWidth: 66)

            narrowCaptureOptionsMenu

            HUDPrimaryIconButton(
                title: model.capture.isRecording ? "Stop" : startStopTitle,
                symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                isDestructive: model.capture.isRecording
            ) {
                toggleRecording()
            }
        }
    }

    private var screenshotControls: some View {
        ViewThatFits(in: .horizontal) {
            fullScreenshotControls
            compactScreenshotControls
        }
    }

    private var fullScreenshotControls: some View {
        HStack(spacing: 8) {
            sharedLeadingControls
            FlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                label: "Screenshot",
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            sourcePicker()
                .layoutPriority(2)

            permissionControls

            HUDPrimaryButton(
                title: "Capture",
                symbolName: "camera.fill",
                isDestructive: false
            ) {
                model.takeScreenshot()
            }
        }
    }

    private var compactScreenshotControls: some View {
        HStack(spacing: 6) {
            compactLeadingControls

            CompactFlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            sourcePicker(width: 154, textWidth: 100)

            compactPermissionControls

            HUDPrimaryIconButton(
                title: "Capture",
                symbolName: "camera.fill",
                isDestructive: false
            ) {
                model.takeScreenshot()
            }
        }
    }

    private var sharedLeadingControls: some View {
        HStack(spacing: 8) {
            DragHandle()
            backButton
            HUDDivider()
        }
    }

    private var compactLeadingControls: some View {
        HStack(spacing: 6) {
            DragHandle()
            backButton
        }
    }

    private var backButton: some View {
        StudioButton(hitTarget: .circle, help: "Back") {
            if !model.capture.isRecording {
                model.cancelCapture()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.white.opacity(model.capture.isRecording ? 0.25 : 0.70))
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                }
        }
        .disabled(model.capture.isRecording)
    }

    private func sourcePicker(width: CGFloat = 208, textWidth: CGFloat = 154) -> some View {
        StudioButton(hitTarget: .capsule, help: "Choose Source") {
            model.requestWindow(.showSourceSelector)
            openWindow(id: "source-selector")
        } label: {
            SourceChip(source: model.selectedSource, width: width, textWidth: textWidth)
        }
    }

    private var compactCaptureControlGroup: some View {
        HUDControlGroup {
            captureToggles
            compactDeviceMenu
        }
    }

    @ViewBuilder
    private var captureToggles: some View {
        HUDToggle(symbolName: model.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", isActive: model.includeSystemAudio, title: "System Audio") {
            model.includeSystemAudio.toggle()
        }
        HUDToggle(symbolName: model.includeMicrophone ? "mic.fill" : "mic.slash.fill", isActive: model.includeMicrophone, title: "Microphone") {
            model.includeMicrophone.toggle()
        }
        HUDToggle(symbolName: model.includeCamera ? "video.fill" : "video.slash.fill", isActive: model.includeCamera, title: "Facecam") {
            model.includeCamera.toggle()
        }
    }

    private var compactDeviceMenu: some View {
        StudioMenu(hitTarget: .rectangle, help: "Devices") {
            Section("Microphone Device") {
                deviceSelectionItems(devices: model.microphoneDevices, selectedDeviceID: $model.selectedMicrophoneDeviceID)
            }
            Section("Camera Device") {
                deviceSelectionItems(devices: model.cameraDevices, selectedDeviceID: $model.selectedCameraDeviceID)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
        }
    }

    private var narrowCaptureOptionsMenu: some View {
        StudioMenu(hitTarget: .circle, help: "Capture Options") {
            Button(model.includeSystemAudio ? "Turn Off System Audio" : "Turn On System Audio") {
                model.includeSystemAudio.toggle()
            }
            Button(model.includeMicrophone ? "Turn Off Microphone" : "Turn On Microphone") {
                model.includeMicrophone.toggle()
            }
            Button(model.includeCamera ? "Turn Off Facecam" : "Turn On Facecam") {
                model.includeCamera.toggle()
            }
            Section("Microphone Device") {
                deviceSelectionItems(devices: model.microphoneDevices, selectedDeviceID: $model.selectedMicrophoneDeviceID)
            }
            Section("Camera Device") {
                deviceSelectionItems(devices: model.cameraDevices, selectedDeviceID: $model.selectedCameraDeviceID)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.white.opacity(0.70))
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var permissionControls: some View {
        if model.statusMessage.localizedCaseInsensitiveContains("permission") {
            HUDPermissionGroup {
                openRelevantPrivacySettings()
            }
        } else if let captureStatusMessage {
            CaptureStatusChip(message: captureStatusMessage, isError: false)
        }
    }

    @ViewBuilder
    private var compactPermissionControls: some View {
        if model.statusMessage.localizedCaseInsensitiveContains("permission") {
            HUDIconActionButton(symbolName: "exclamationmark.triangle.fill", title: "Open Privacy Settings", tint: .red) {
                openRelevantPrivacySettings()
            }
        } else if let captureStatusMessage {
            CaptureStatusChip(message: captureStatusMessage, isError: false, maxWidth: 96)
        }
    }

    private var captureStatusMessage: String? {
        let message = model.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message != "Ready",
              message != "Rust service ready",
              !message.hasPrefix("Selected "),
              !message.hasPrefix("Opened ") else {
            return nil
        }

        if message.localizedCaseInsensitiveContains("permission") {
            return "Permission needed"
        }
        if message.localizedCaseInsensitiveContains("starting") {
            return "Starting..."
        }
        if message.localizedCaseInsensitiveContains("choose") {
            return "Choose source"
        }
        return message
    }

    private func openRelevantPrivacySettings() {
        let message = model.statusMessage.lowercased()
        if message.contains("microphone") {
            model.openMicrophoneSettings()
        } else if message.contains("camera") {
            model.openCameraSettings()
        } else if message.contains("accessibility") {
            model.openAccessibilitySettings()
        } else {
            model.openPrivacySettings()
        }
    }

    private var recordingPhaseLabel: String {
        switch model.recordingPhase {
        case .starting:
            "Starting"
        case .recording:
            "Live"
        case .stopping:
            "Saving"
        case .interrupted:
            "Interrupted"
        case .idle:
            "Live"
        }
    }

    private var startStopTitle: String {
        model.recordingPhase == .starting ? "Starting" : "Record"
    }

    private func toggleRecording() {
        model.capture.isRecording ? model.stopRecording() : model.startRecording()
    }

    private func deviceMenu(
        symbolName: String,
        title: String,
        devices: [CaptureDeviceInfo],
        selectedDeviceID: Binding<String?>
    ) -> some View {
        StudioMenu(hitTarget: .rectangle, help: title) {
            deviceSelectionItems(devices: devices, selectedDeviceID: selectedDeviceID)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
        }
    }

    @ViewBuilder
    private func deviceSelectionItems(devices: [CaptureDeviceInfo], selectedDeviceID: Binding<String?>) -> some View {
        Button("System Default") {
            selectedDeviceID.wrappedValue = nil
        }
        ForEach(devices) { device in
            Button(device.isDefault ? "\(device.name) (Default)" : device.name) {
                selectedDeviceID.wrappedValue = device.id
            }
        }
        if devices.isEmpty {
            Text("No devices found")
        }
    }
}

