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

            sourcePicker()
                .layoutPriority(2)

            permissionControls

            HUDDivider()

            recordingCaptureControlGroup

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

            sourcePicker(minWidth: 128, maxWidth: 172)

            compactPermissionControls

            recordingCaptureControlGroup

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

            sourcePicker(minWidth: 112, maxWidth: 134)

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

            sourcePicker(minWidth: 128, maxWidth: 172)

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

    private func sourcePicker(minWidth: CGFloat = 132, maxWidth: CGFloat = 198) -> some View {
        StudioButton(hitTarget: .capsule, help: "Choose Source") {
            model.requestWindow(.showSourceSelector)
            openWindow(id: "source-selector")
        } label: {
            SourceChip(source: model.selectedSource, tone: sourceChipTone, minWidth: minWidth, maxWidth: maxWidth)
        }
    }

    private var recordingCaptureControlGroup: some View {
        HUDControlGroup {
            captureToggles
        }
    }

    @ViewBuilder
    private var captureToggles: some View {
        HUDToggle(symbolName: model.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", isActive: model.includeSystemAudio, title: "System Audio") {
            model.includeSystemAudio.toggle()
        }
        microphoneToggle
        cameraToggle
    }

    @ViewBuilder
    private var microphoneToggle: some View {
        let button = HUDToggle(
            symbolName: model.includeMicrophone ? "mic.fill" : "mic.slash.fill",
            isActive: model.includeMicrophone,
            title: "Microphone"
        ) {
            if model.includeMicrophone {
                model.disableMicrophone()
            } else {
                openMicrophoneSelector()
            }
        }

        if model.includeMicrophone {
            button.contextMenu {
                Button("Microphone: \(model.selectedMicrophoneDeviceName)") {}
                    .disabled(true)
                Divider()
                Button("Change Device...") {
                    openMicrophoneSelector()
                }
            }
        } else {
            button
        }
    }

    @ViewBuilder
    private var cameraToggle: some View {
        let button = HUDToggle(
            symbolName: model.includeCamera ? "video.fill" : "video.slash.fill",
            isActive: model.includeCamera,
            title: "Camera"
        ) {
            if model.includeCamera {
                model.disableCamera()
            } else {
                openCameraSelector()
            }
        }

        if model.includeCamera {
            button.contextMenu {
                Button("Camera: \(model.selectedCameraDeviceName)") {}
                    .disabled(true)
                Divider()
                Button("Change Device...") {
                    openCameraSelector()
                }
            }
        } else {
            button
        }
    }

    private var narrowCaptureOptionsMenu: some View {
        StudioMenu(hitTarget: .circle, help: "Capture Options") {
            Button(model.includeSystemAudio ? "Turn Off System Audio" : "Turn On System Audio") {
                model.includeSystemAudio.toggle()
            }
            microphoneOptionsMenuItems
            cameraOptionsMenuItems
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
    private var microphoneOptionsMenuItems: some View {
        if model.includeMicrophone {
            Button("Turn Off Microphone") {
                model.disableMicrophone()
            }
            Button("Change Microphone...") {
                openMicrophoneSelector()
            }
        } else {
            Button("Choose Microphone...") {
                openMicrophoneSelector()
            }
        }
    }

    @ViewBuilder
    private var cameraOptionsMenuItems: some View {
        if model.includeCamera {
            Button("Turn Off Camera") {
                model.disableCamera()
            }
            Button("Change Camera...") {
                openCameraSelector()
            }
        } else {
            Button("Choose Camera...") {
                openCameraSelector()
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
              !message.hasPrefix("Opened "),
              !message.hasPrefix("Microphone "),
              !message.hasPrefix("Camera ") else {
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

    private var startStopTitle: String {
        model.recordingPhase == .starting ? "Starting" : "Record"
    }

    private func toggleRecording() {
        model.capture.isRecording ? model.stopRecording() : model.startRecording()
    }

    private var sourceChipTone: FlowTone {
        if model.capture.isRecording || model.recordingPhase == .recording {
            return .red
        }
        if model.recordingPhase == .starting || model.recordingPhase == .stopping {
            return .amber
        }
        return .green
    }

    private func openMicrophoneSelector() {
        model.requestMicrophoneSelection()
        openWindow(id: "microphone-selector")
    }

    private func openCameraSelector() {
        model.requestCameraSelection()
        openWindow(id: "camera-selector")
    }
}
