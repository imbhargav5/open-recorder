import AppKit
import Combine
import SwiftUI

enum OnboardingWindowMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 560
}

private enum OnboardingPalette {
    static let heroBackground = Color(red: 0.059, green: 0.059, blue: 0.075)
    static let mockWindow = Color(red: 0.094, green: 0.094, blue: 0.114)
    static let mockPanel = Color(red: 0.118, green: 0.118, blue: 0.133)
    static let keycap = Color(red: 0.122, green: 0.122, blue: 0.141)
    static let accentText = Color(red: 0.561, green: 0.690, blue: 1.0)
    static let record = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let success = Color(red: 0.290, green: 0.871, blue: 0.502)
    static let waiting = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let facecam = Color(red: 0.165, green: 0.208, blue: 0.314)
    static let facecamFigure = Color(red: 0.624, green: 0.702, blue: 0.851)
    static let heroHeight: CGFloat = 220
}

struct OnboardingView: View {
    var driver: OnboardingDriver
    private let permissionRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var state: OnboardingMachineState {
        driver.state
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(state: state)
                .frame(height: OnboardingPalette.heroHeight)

            VStack(alignment: .leading, spacing: 0) {
                stepContent
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 44)
            .padding(.top, 26)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .animation(.easeInOut(duration: 0.22), value: state.step)
        .animation(.easeInOut(duration: 0.22), value: state.screenRecordingStage)
        .onAppear {
            driver.send(.appeared)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            driver.send(.appBecameActive)
        }
        .onReceive(permissionRefreshTimer) { _ in
            driver.send(.timerTicked)
        }
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch state.step {
        case .welcome:
            OnboardingHeading(
                title: "Record, zoom and share in minutes",
                message: "Open Recorder needs one permission to start. Microphone, camera and keystrokes are optional, and you can change them later in Settings."
            )
        case .screenRecording:
            screenRecordingContent
        case .extras:
            extrasContent
        case .ready:
            readyContent
        }
    }

    @ViewBuilder
    private var screenRecordingContent: some View {
        switch state.screenRecordingStage {
        case .notRequested:
            OnboardingHeading(
                eyebrow: "Required",
                title: "Allow Screen Recording",
                message: "macOS will ask once. Choose Allow so Open Recorder can capture the displays, windows and areas you pick."
            )
        case .waitingForSettings:
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeading(
                    eyebrow: "Required",
                    title: "Switch on Screen Recording",
                    message: "In System Settings, open Privacy & Security, then Screen & System Audio Recording, and switch on Open Recorder. This window updates as soon as you do."
                )
                OnboardingStatusRow(color: OnboardingPalette.waiting, text: "Waiting for Screen Recording to be switched on")
            }
        case .needsRelaunch:
            OnboardingHeading(
                eyebrow: "Almost there",
                title: "Relaunch to finish",
                message: "Switched on Open Recorder in System Settings? macOS applies it after the app restarts. Setup will pick up right here."
            )
        case .granted:
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeading(
                    eyebrow: "Done",
                    eyebrowColor: OnboardingPalette.success,
                    title: "Screen Recording is on",
                    message: "You can record now. Next, a few optional extras."
                )
            }
        }
    }

    private var extrasContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(
                title: "Make it yours",
                message: "All optional. macOS asks only when you turn one on."
            )
            HStack(alignment: .top, spacing: 10) {
                OnboardingExtraCard(
                    systemImage: "mic.fill",
                    title: "Microphone",
                    message: "Narrate as you record.",
                    status: OnboardingExtraStatus(media: state.microphonePermissionState)
                ) {
                    driver.send(.microphoneButtonTapped)
                }
                OnboardingExtraCard(
                    systemImage: "video.fill",
                    title: "Camera",
                    message: "Add a facecam bubble.",
                    status: OnboardingExtraStatus(media: state.cameraPermissionState)
                ) {
                    driver.send(.cameraButtonTapped)
                }
                OnboardingExtraCard(
                    systemImage: "keyboard",
                    title: "Keystrokes",
                    message: "Show the shortcuts you press and track the cursor for zooms.",
                    status: OnboardingExtraStatus(accessibility: state.accessibilityPermissionState)
                ) {
                    driver.send(.accessibilityPermissionButtonTapped)
                }
            }
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeading(
                title: "You're ready to record",
                message: "Open Recorder lives in your menu bar. Start from there, or with a shortcut from any app."
            )
            if AppVariant.isNightly {
                Text("Global shortcuts are off in nightly builds. Turn them on in Settings, Shortcuts.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fgMuted)
            } else {
                HStack(spacing: 8) {
                    OnboardingShortcutChip(title: "Area", keys: "⌥⇧6")
                    OnboardingShortcutChip(title: "Window", keys: "⌥⇧8")
                    OnboardingShortcutChip(title: "Start or stop", keys: "⌥⇧R")
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            OnboardingProgress(step: state.step)
            Spacer(minLength: 12)
            footerButtons
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch state.step {
        case .welcome:
            OnboardingButton(title: "Get started") {
                driver.send(.stepAdvanceRequested)
            }
        case .screenRecording:
            OnboardingButton(title: "Back", kind: .secondary) {
                driver.send(.stepBackRequested)
            }
            screenRecordingButtons
        case .extras:
            OnboardingButton(title: "Back", kind: .secondary) {
                driver.send(.stepBackRequested)
            }
            OnboardingButton(title: "Continue") {
                driver.send(.stepAdvanceRequested)
            }
        case .ready:
            OnboardingButton(title: "Later", kind: .secondary) {
                driver.send(.continueRequested)
            }
            OnboardingButton(title: "Record your first clip", systemImage: "record.circle") {
                driver.send(.firstRecordingRequested)
            }
        }
    }

    @ViewBuilder
    private var screenRecordingButtons: some View {
        switch state.screenRecordingStage {
        case .notRequested:
            OnboardingButton(title: "Allow Screen Recording") {
                driver.send(.screenPermissionButtonTapped)
            }
        case .waitingForSettings:
            OnboardingButton(title: "Open System Settings") {
                driver.send(.screenRecordingSettingsRequested)
            }
        case .needsRelaunch:
            OnboardingButton(title: "Open Settings", kind: .secondary) {
                driver.send(.screenRecordingSettingsRequested)
            }
            OnboardingButton(title: "Relaunch Open Recorder", systemImage: "arrow.clockwise") {
                driver.send(.relaunchRequested)
            }
        case .granted:
            OnboardingButton(title: "Continue") {
                driver.send(.stepAdvanceRequested)
            }
        }
    }
}

// MARK: - Text and controls

private struct OnboardingHeading: View {
    var eyebrow: String?
    var eyebrowColor: Color = OnboardingPalette.accentText
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(eyebrowColor)
            }
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Theme.fg)
            Text(message)
                .font(.system(size: 13))
                .lineSpacing(2)
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingStatusRow: View {
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .phaseAnimator([1.0, 0.35]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    Animation.easeInOut(duration: 0.8)
                }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
        }
    }
}

private struct OnboardingButton: View {
    enum Kind {
        case primary
        case secondary
    }

    var title: String
    var systemImage: String?
    var kind: Kind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, kind == .primary ? 20 : 16)
            .frame(height: 38)
            .foregroundStyle(kind == .primary ? Color.white : Theme.fg)
            .background(
                kind == .primary ? Theme.accent : Theme.surfaceControl,
                in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(kind == .primary ? Theme.accent.opacity(0.45) : Theme.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(kind == .primary ? KeyboardShortcut.defaultAction : nil)
    }
}

private struct OnboardingProgress: View {
    var step: OnboardingStep

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.number <= step.number ? Theme.accent : Color.white.opacity(0.14))
                        .frame(width: 26, height: 4)
                }
            }
            Text("Step \(step.number) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.number) of \(OnboardingStep.allCases.count)")
    }
}

private enum OnboardingExtraStatus {
    case off
    case on
    case needsSettings

    init(media: OnboardingMediaPermissionState) {
        switch media {
        case .undetermined: self = .off
        case .granted: self = .on
        case .denied: self = .needsSettings
        }
    }

    init(accessibility: AccessibilityPermissionState) {
        switch accessibility {
        case .requestAvailable: self = .off
        case .granted: self = .on
        case .requestAlreadyShown: self = .needsSettings
        }
    }
}

private struct OnboardingExtraCard: View {
    var systemImage: String
    var title: String
    var message: String
    var status: OnboardingExtraStatus
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.fg)
                        .frame(width: 30, height: 30)
                        .background(Theme.surfaceControl, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer(minLength: 6)
                    statusLabel
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(
                status == .on ? Theme.accent.opacity(0.10) : Theme.surface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(status == .on ? Theme.accent.opacity(0.55) : Theme.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(statusText)")
    }

    private var statusText: String {
        switch status {
        case .off: "Allow"
        case .on: "On"
        case .needsSettings: "Open Settings"
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .off:
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OnboardingPalette.accentText)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Theme.accent.opacity(0.16), in: Capsule())
        case .on:
            Label(statusText, systemImage: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OnboardingPalette.success)
        case .needsSettings:
            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OnboardingPalette.waiting)
        }
    }
}

private struct OnboardingShortcutChip: View {
    var title: String
    var keys: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.fgMuted)
            Text(keys)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.fg)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.border)
        }
    }
}

// MARK: - Hero scenes

private struct OnboardingHero: View {
    var state: OnboardingMachineState

    var body: some View {
        ZStack {
            OnboardingDotGrid()
            scene
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var scene: some View {
        switch state.step {
        case .welcome:
            OnboardingRecordingScene(
                showsZoom: true,
                showsCamera: true,
                showsMicrophone: false,
                showsKeystrokes: false
            )
        case .screenRecording:
            switch state.screenRecordingStage {
            case .needsRelaunch:
                OnboardingRelaunchScene()
            case .granted:
                OnboardingSettingsScene(isGranted: true)
            case .notRequested, .waitingForSettings:
                OnboardingSettingsScene(isGranted: false)
            }
        case .extras:
            OnboardingRecordingScene(
                showsZoom: false,
                showsCamera: state.cameraPermissionState == .granted,
                showsMicrophone: state.microphonePermissionState == .granted,
                showsKeystrokes: state.accessibilityPermissionState == .granted
            )
        case .ready:
            OnboardingShortcutScene()
        }
    }
}

private struct OnboardingDotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = 8
                while x < size.width {
                    let dot = CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)
                    context.fill(Path(ellipseIn: dot), with: .color(Color.white.opacity(0.08)))
                    x += spacing
                }
                y += spacing
            }
        }
        .background(OnboardingPalette.heroBackground)
    }
}

private struct OnboardingRecordingScene: View {
    var showsZoom: Bool
    var showsCamera: Bool
    var showsMicrophone: Bool
    var showsKeystrokes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 18)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                placeholderBar(width: 190, height: 9, opacity: 0.18)
                placeholderBar(width: 290, height: 7, opacity: 0.08)
                placeholderBar(width: 240, height: 7, opacity: 0.08)
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 100, height: 52)
                    }
                }
                .padding(.top, 6)
            }
            .padding(14)
        }
        .frame(width: 360, height: 186, alignment: .topLeading)
        .background(OnboardingPalette.mockWindow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            if showsZoom {
                OnboardingZoomBox()
                    .padding(.leading, 10)
                    .padding(.top, 60)
            }
        }
        .overlay(alignment: .topTrailing) {
            OnboardingRecordingPill()
                .padding(.top, 26)
                .padding(.trailing, 10)
        }
        .overlay(alignment: .bottomLeading) {
            if showsMicrophone {
                OnboardingMicrophoneMeter()
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if showsKeystrokes {
                OnboardingKeystrokePill()
                    .padding(.bottom, 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsCamera {
                OnboardingFacecam()
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.5), radius: 24, y: 14)
        .padding(.top, 10)
        .animation(.spring(duration: 0.3), value: showsCamera)
        .animation(.spring(duration: 0.3), value: showsMicrophone)
        .animation(.spring(duration: 0.3), value: showsKeystrokes)
    }

    private func placeholderBar(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
    }
}

private struct OnboardingZoomBox: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.accent.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.accent, lineWidth: 2)
            }
            .frame(width: 216, height: 74)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.6), radius: 1)
                    .offset(x: -24, y: -12)
            }
            .phaseAnimator([1.0, 1.04]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in
                Animation.easeInOut(duration: 1.5)
            }
    }
}

private struct OnboardingRecordingPill: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(OnboardingPalette.record)
                .frame(width: 7, height: 7)
                .phaseAnimator([1.0, 0.3]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    Animation.easeInOut(duration: 0.7)
                }
            Text("REC 00:12")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Color.black.opacity(0.65), in: Capsule())
    }
}

private struct OnboardingFacecam: View {
    var body: some View {
        Circle()
            .fill(OnboardingPalette.facecam)
            .frame(width: 60, height: 60)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(OnboardingPalette.facecamFigure)
                    .offset(y: 6)
            }
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color.white, lineWidth: 2)
            }
    }
}

private struct OnboardingMicrophoneMeter: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(OnboardingPalette.success)
                        .frame(width: 3, height: 14)
                        .phaseAnimator([0.3, 1.0]) { content, scale in
                            content.scaleEffect(x: 1, y: scale)
                        } animation: { _ in
                            Animation.easeInOut(duration: 0.3 + Double(index) * 0.07)
                        }
                }
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Color.black.opacity(0.65), in: Capsule())
    }
}

private struct OnboardingKeystrokePill: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["⌘", "⇧", "S"], id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct OnboardingSettingsScene: View {
    var isGranted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Privacy & Security  ›  Screen & System Audio Recording")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .padding(.horizontal, 14)
                .frame(height: 34)
            divider
            placeholderRow(isOn: true)
            divider
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.appBg)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle()
                            .fill(OnboardingPalette.record)
                            .frame(width: 10, height: 10)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.14))
                    }
                Text("Open Recorder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                if isGranted {
                    Label("Allowed", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.success)
                    OnboardingMiniToggle(isOn: true)
                } else {
                    OnboardingAnimatedToggle()
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "cursorarrow")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .shadow(color: Color.black.opacity(0.6), radius: 1)
                                .offset(x: 8, y: 14)
                        }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.accent.opacity(0.10))
            divider
            placeholderRow(isOn: false)
        }
        .frame(width: 400)
        .background(OnboardingPalette.mockPanel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12))
        }
        .shadow(color: Color.black.opacity(0.5), radius: 24, y: 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }

    private func placeholderRow(isOn: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: 24, height: 24)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .frame(width: 110, height: 8)
            Spacer()
            OnboardingMiniToggle(isOn: isOn)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .opacity(0.5)
    }
}

private struct OnboardingMiniToggle: View {
    var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Color.white.opacity(0.2))
            .frame(width: 32, height: 18)
            .overlay {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .offset(x: isOn ? 7 : -7)
            }
    }
}

private struct OnboardingAnimatedToggle: View {
    var body: some View {
        PhaseAnimator([false, true]) { isOn in
            OnboardingMiniToggle(isOn: isOn)
        } animation: { isOn in
            Animation.easeInOut(duration: 0.25).delay(isOn ? 1.0 : 1.6)
        }
    }
}

private struct OnboardingRelaunchScene: View {
    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Theme.accent.opacity(0.14))
                .frame(width: 76, height: 76)
                .overlay {
                    Circle().stroke(Theme.accent.opacity(0.45))
                }
                .overlay {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(OnboardingPalette.accentText)
                }
            Text("Restarting takes about two seconds")
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgMuted)
        }
    }
}

private struct OnboardingShortcutScene: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                menuBarGlyph
                Capsule()
                    .fill(Theme.accent.opacity(0.35))
                    .frame(width: 24, height: 18)
                    .overlay {
                        Circle()
                            .fill(OnboardingPalette.record)
                            .frame(width: 8, height: 8)
                    }
                    .overlay {
                        Capsule().stroke(Theme.accent, lineWidth: 2)
                    }
                    .overlay(alignment: .bottom) {
                        Text("Open Recorder lives here")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .offset(y: 30)
                    }
                menuBarGlyph
                menuBarGlyph
            }
            .padding(.horizontal, 24)
            .frame(height: 26)
            .background(Color.white.opacity(0.04))
            .padding(.top, 10)

            Spacer(minLength: 0)

            PhaseAnimator([false, true]) { isPressed in
                HStack(spacing: 12) {
                    OnboardingKeycap(symbol: "⌥", isPressed: isPressed)
                    plus
                    OnboardingKeycap(symbol: "⇧", isPressed: isPressed)
                    plus
                    OnboardingKeycap(symbol: "5", isPressed: isPressed)
                }
            } animation: { isPressed in
                isPressed
                    ? Animation.easeOut(duration: 0.15).delay(1.1)
                    : Animation.easeIn(duration: 0.2).delay(0.5)
            }

            Text("Record the whole screen from any app")
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgMuted)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
    }

    private var menuBarGlyph: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white.opacity(0.3))
            .frame(width: 14, height: 10)
    }

    private var plus: some View {
        Text("+")
            .font(.system(size: 20))
            .foregroundStyle(Color.white.opacity(0.4))
    }
}

private struct OnboardingKeycap: View {
    var symbol: String
    var isPressed: Bool

    var body: some View {
        Text(symbol)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Theme.fg)
            .frame(width: 60, height: 60)
            .background(OnboardingPalette.keycap, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isPressed ? Theme.accent.opacity(0.8) : Color.white.opacity(0.16))
            }
            .shadow(color: Color.black.opacity(0.6), radius: 0, y: isPressed ? 1 : 4)
            .offset(y: isPressed ? 3 : 0)
    }
}
