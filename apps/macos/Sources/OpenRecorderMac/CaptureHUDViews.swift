import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct CaptureHUD: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var options: CaptureOptionsDriver

    private var isRecordingActive: Bool {
        model.capture.isRecording || model.recordingPhase == .recording
    }

    var body: some View {
        HUDSurface(isRecording: isRecordingActive) {
            if isRecordingActive {
                activeRecordingControls
            } else {
                idleControls
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.captureMode)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isRecordingActive)
        .environment(\.layoutDirection, .leftToRight)
        .flipsForRightToLeftLayoutDirection(false)
    }

    private var activeRecordingControls: some View {
        HStack(spacing: 8) {
            DragHandle()

            // Integrated Status Pill: Pulsing Dot + REC + Live Elapsed Time
            HStack(spacing: 7) {
                PulsingRecDot()
                Text("REC")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.red)
                LiveRecordingTimerView(startDate: model.activeRecordingStartDate)
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.btnHeightLg)
            .background(Theme.scrim, in: Rectangle())
            .overlay {
                Rectangle().stroke(Theme.borderSubtle, lineWidth: 1)
            }

            HUDDivider()

            // Active Source Target
            SourceChip(
                source: model.captureState.source,
                tone: .red,
                minWidth: 110,
                maxWidth: 240
            )

            // Audio & Mic Indicators (Modular, borderless)
            if options.state.includeMicrophone || options.state.includeSystemAudio {
                HStack(spacing: 6) {
                    if options.state.includeMicrophone {
                        HStack(spacing: 5) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.green)
                            AudioWaveformIndicator()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: Theme.btnHeightLg)
                        .background(Color.green.opacity(0.12), in: Rectangle())
                        .help("Microphone is actively recording")
                    }

                    if options.state.includeSystemAudio {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28, height: Theme.btnHeightLg)
                            .background(Theme.accent.opacity(0.12), in: Rectangle())
                            .help("System audio is actively recording")
                    }
                }
            }

            HUDPrimaryButton(
                title: "Stop",
                symbolName: "stop.fill",
                isDestructive: true,
                shortcutText: nil
            ) {
                model.stopRecording()
            }
            .help(recordingShortcutHelpTitle)
        }
    }

    private var idleControls: some View {
        HStack(spacing: 10) {
            sharedLeadingControls

            HStack(spacing: 4) {
                sourcePicker()
                permissionControls
            }

            HUDDivider()

            HStack(spacing: 6) {
                if model.captureMode == .recording {
                    recordingCaptureControlGroup
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                            removal: .scale(scale: 0.85).combined(with: .opacity).combined(with: .move(edge: .trailing))
                        ))
                }

                if model.captureMode == .recording {
                    HUDPrimaryButton(
                        title: model.capture.isRecording ? "Stop" : startStopTitle,
                        symbolName: model.capture.isRecording ? "stop.fill" : "record.circle",
                        isDestructive: model.capture.isRecording,
                        shortcutText: nil
                    ) {
                        toggleRecording()
                    }
                    .help(recordingShortcutHelpTitle)
                    .disabled(model.recordingPhase == .idle && !model.capture.isRecording && !captureReadiness.canCapture)
                    .transition(.identity)
                } else {
                    HUDPrimaryButton(
                        title: "Capture",
                        symbolName: "camera.fill",
                        isDestructive: false
                    ) {
                        model.takeScreenshot()
                    }
                    .disabled(!captureReadiness.canCapture)
                    .transition(.identity)
                }
            }
        }
    }

    private var compactScreenshotControls: some View {
        HStack(spacing: 8) {
            compactLeadingControls

            HStack(spacing: 4) {
                sourcePicker(minWidth: 128, maxWidth: 230)
                compactPermissionControls
            }

            HUDPrimaryIconButton(
                title: "Capture",
                symbolName: "camera.fill",
                isDestructive: false
            ) {
                model.takeScreenshot()
            }
            .disabled(!captureReadiness.canCapture)
        }
    }

    private var sharedLeadingControls: some View {
        HStack(spacing: 8) {
            DragHandle()
            HUDModeSwitcher(
                mode: Binding(
                    get: { model.captureMode },
                    set: { model.beginCapture($0) }
                ),
                isDisabled: model.capture.isRecording || model.recordingPhase != .idle
            )
            HUDDivider()
        }
    }

    private var compactLeadingControls: some View {
        HStack(spacing: 6) {
            DragHandle()
            HUDModeSwitcher(
                mode: Binding(
                    get: { model.captureMode },
                    set: { model.beginCapture($0) }
                ),
                isDisabled: model.capture.isRecording || model.recordingPhase != .idle
            )
        }
    }

    private func sourcePicker(minWidth: CGFloat = 120, maxWidth: CGFloat = 240) -> some View {
        StudioButton(hitTarget: .rounded(8), help: "Choose Source") {
            model.requestSourceSelector()
        } label: {
            SourceChip(source: model.selectedSource, tone: sourceChipTone, minWidth: minWidth, maxWidth: maxWidth)
        }
        .accessibilityLabel("Capture Source")
        .accessibilityValue(model.selectedSource.map { "\($0.name), \($0.subtitle)" } ?? "Not selected")
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
                model.includeCamera = true
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
        StudioMenu(hitTarget: .rectangle, help: "Capture Options") {
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
                .background(Theme.overlay, in: Rectangle())
                .overlay {
                    Rectangle()
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
        if let blocker = captureReadiness.primaryBlocker {
            switch blocker.recoveryAction {
            case .openScreenRecordingSettings:
                HUDPermissionGroup {
                    model.openPrivacySettings()
                }
            case .openMicrophoneSettings:
                HUDIconActionButton(symbolName: "mic.badge.xmark", title: blocker.message, tint: .red) {
                    model.openMicrophoneSettings()
                }
            case .openCameraSettings:
                HUDIconActionButton(symbolName: "video.badge.xmark", title: blocker.message, tint: .red) {
                    model.openCameraSettings()
                }
            case .chooseMicrophone:
                HUDIconActionButton(symbolName: "mic.badge.xmark", title: blocker.message, tint: .red) {
                    openMicrophoneSelector()
                }
            case .chooseCamera:
                HUDIconActionButton(symbolName: "video.badge.xmark", title: blocker.message, tint: .red) {
                    openCameraSelector()
                }
            case .chooseSource, .drawArea, .waitForCurrentCapture:
                EmptyView()
            }
        } else if let captureStatusMessage {
            CaptureStatusChip(message: captureStatusMessage, isError: false)
        }
    }

    @ViewBuilder
    private var compactPermissionControls: some View {
        if let blocker = captureReadiness.primaryBlocker {
            switch blocker.recoveryAction {
            case .chooseSource, .drawArea, .waitForCurrentCapture:
                EmptyView()
            default:
                HUDIconActionButton(symbolName: "exclamationmark.triangle.fill", title: blocker.message, tint: .red) {
                    performRecovery(for: blocker)
                }
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
            return nil
        }
        return message
    }

    private var captureReadiness: CaptureReadiness {
        model.captureState.readiness(
            availableSources: model.capture.sources,
            screenRecordingPermissionState: model.capture.screenRecordingPermissionState,
            options: options.state,
            runtimeIsRecording: model.capture.isRecording,
            microphoneAuthorization: model.microphoneCaptureAuthorization,
            cameraAuthorization: model.cameraCaptureAuthorization,
            isChecking: model.capture.sourceCatalogState == .loading || model.isCapturePreflightRunning
        )
    }

    private func performRecovery(for blocker: CaptureBlocker) {
        switch blocker.recoveryAction {
        case .waitForCurrentCapture:
            break
        case .chooseSource:
            model.requestSourceSelector()
        case .drawArea:
            model.requestInteractiveAreaSelection()
        case .openScreenRecordingSettings:
            model.openPrivacySettings()
        case .openMicrophoneSettings:
            model.openMicrophoneSettings()
        case .openCameraSettings:
            model.openCameraSettings()
        case .chooseMicrophone:
            openMicrophoneSelector()
        case .chooseCamera:
            openCameraSelector()
        }
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

private struct PulsingRecDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .shadow(color: Color.red.opacity(0.8), radius: 3)
    }
}

private struct LiveRecordingTimerView: View {
    var startDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(formattedDuration(for: context.date))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 46, alignment: .leading)
        }
    }

    private func formattedDuration(for currentDate: Date) -> String {
        guard let startDate else { return "00:00" }
        let totalSeconds = max(0, Int(currentDate.timeIntervalSince(startDate)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

private struct AudioWaveformIndicator: View {
    var body: some View {
        HStack(spacing: 2) {
            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: 6)

            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: 10)

            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: 7)
        }
        .frame(height: 12)
    }
}
