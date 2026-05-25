import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct CaptureHUD: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var options: CaptureOptionsDriver
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
        HStack(spacing: 10) {
            sharedLeadingControls

            HStack(spacing: 4) {
                sourcePicker()
                    .layoutPriority(2)
                permissionControls
            }

            HUDDivider()

            HStack(spacing: 6) {
                recordingCaptureControlGroup

                HUDPrimaryButton(
                    title: model.capture.isRecording ? "Stop" : startStopTitle,
                    symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                    isDestructive: model.capture.isRecording,
                    shortcutText: recordingShortcutText
                ) {
                    toggleRecording()
                }
            }
        }
    }

    private var compactRecordingControls: some View {
        HStack(spacing: 8) {
            compactLeadingControls

            HStack(spacing: 4) {
                sourcePicker(minWidth: 128, maxWidth: 172)
                compactPermissionControls
            }

            HStack(spacing: 6) {
                recordingCaptureControlGroup

                HUDPrimaryButton(
                    title: model.capture.isRecording ? "Stop" : startStopTitle,
                    symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                    isDestructive: model.capture.isRecording,
                    shortcutText: recordingShortcutText
                ) {
                    toggleRecording()
                }
            }
        }
    }

    private var narrowRecordingControls: some View {
        HStack(spacing: 6) {
            backButton

            sourcePicker(minWidth: 112, maxWidth: 134)

            narrowCaptureOptionsMenu

            HUDPrimaryIconButton(
                title: recordingShortcutHelpTitle,
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
        HStack(spacing: 10) {
            sharedLeadingControls

            FlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                label: "Screenshot",
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            HStack(spacing: 4) {
                sourcePicker()
                    .layoutPriority(2)
                permissionControls
            }

            HUDDivider()

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
        HStack(spacing: 8) {
            compactLeadingControls

            CompactFlowLabel(
                tone: model.statusMessage.localizedCaseInsensitiveContains("permission") ? .red : .blue,
                value: model.selectedSource == nil ? "Source" : "Ready"
            )

            HStack(spacing: 4) {
                sourcePicker(minWidth: 128, maxWidth: 172)
                compactPermissionControls
            }

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
                .foregroundStyle(model.capture.isRecording ? Theme.fgDisabled : Color.white.opacity(0.70))
                .background(Theme.overlay, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Theme.border, lineWidth: 1)
                }
        }
        .disabled(model.capture.isRecording)
    }

    private func sourcePicker(minWidth: CGFloat = 132, maxWidth: CGFloat = 198) -> some View {
        StudioButton(hitTarget: .capsule, help: "Choose Source") {
            model.requestSourceSelector()
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
        systemAudioToggle
        microphoneToggle
        cameraToggle
    }

    private var systemAudioToggle: some View {
        HUDToggle(
            symbolName: options.state.includeSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
            isActive: options.state.includeSystemAudio,
            title: options.state.includeSystemAudio ? "System Audio On" : "System Audio Off",
            isDisabled: !options.state.canChangeOptions
        ) {
            model.toggleSystemAudio()
        }
    }

    @ViewBuilder
    private var microphoneToggle: some View {
        let button = HUDToggle(
            symbolName: options.state.includeMicrophone ? "mic.fill" : "mic.slash.fill",
            isActive: options.state.includeMicrophone,
            title: options.state.includeMicrophone ? "Microphone On" : "Microphone Off",
            isDisabled: !options.state.canChangeOptions
        ) {
            if options.state.includeMicrophone {
                model.disableMicrophone()
            } else {
                openMicrophoneSelector()
            }
        }

        if options.state.includeMicrophone && options.state.canChangeOptions {
            button.contextMenu {
                Button("Microphone: \(options.state.selectedMicrophoneDeviceName)") {}
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
            symbolName: options.state.includeCamera ? "video.fill" : "video.slash.fill",
            isActive: options.state.includeCamera,
            title: options.state.includeCamera ? "Camera On" : "Camera Off",
            isDisabled: !options.state.canChangeOptions
        ) {
            if options.state.includeCamera {
                model.disableCamera()
            } else {
                openCameraSelector()
            }
        }

        if options.state.includeCamera && options.state.canChangeOptions {
            button.contextMenu {
                Button("Camera: \(options.state.selectedCameraDeviceName)") {}
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
            Button(options.state.includeSystemAudio ? "Turn Off System Audio" : "Turn On System Audio") {
                model.toggleSystemAudio()
            }
            .disabled(!options.state.canChangeOptions)
            microphoneOptionsMenuItems
            cameraOptionsMenuItems
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.white.opacity(0.70))
                .background(Theme.overlay, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Theme.border, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var microphoneOptionsMenuItems: some View {
        if options.state.includeMicrophone {
            Button("Turn Off Microphone") {
                model.disableMicrophone()
            }
            .disabled(!options.state.canChangeOptions)
            Button("Change Microphone...") {
                openMicrophoneSelector()
            }
            .disabled(!options.state.canChangeOptions)
        } else {
            Button("Choose Microphone...") {
                openMicrophoneSelector()
            }
            .disabled(!options.state.canChangeOptions)
        }
    }

    @ViewBuilder
    private var cameraOptionsMenuItems: some View {
        if options.state.includeCamera {
            Button("Turn Off Camera") {
                model.disableCamera()
            }
            .disabled(!options.state.canChangeOptions)
            Button("Change Camera...") {
                openCameraSelector()
            }
            .disabled(!options.state.canChangeOptions)
        } else {
            Button("Choose Camera...") {
                openCameraSelector()
            }
            .disabled(!options.state.canChangeOptions)
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
              !message.hasPrefix("System audio "),
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

    private var recordingShortcutHelpTitle: String {
        let title = model.capture.isRecording ? "Stop" : startStopTitle
        guard recordingShortcutText != nil else { return title }
        return "\(title) (⌘R)"
    }

    private var recordingShortcutText: String? {
        model.captureState.shouldRegisterRecordingHotKey(runtimeIsRecording: model.capture.isRecording) ? "⌘R" : nil
    }

    private func toggleRecording() {
        model.toggleRecordingShortcut()
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
