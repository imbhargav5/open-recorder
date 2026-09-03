import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum SettingsWindowMetrics {
    static let width: CGFloat = 840
    static let height: CGFloat = 560
    static let contentMaxWidth: CGFloat = 760
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case system

    static let defaultSelection: Self = .general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .system: "System"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .system: "desktopcomputer"
        }
    }
}

struct SettingsStudioView: View {
    @State private var selectedTab = SettingsTab.defaultSelection

    var driver: SettingsDriver
    var serviceHealth: HealthPayload?
    var paths: AppPaths?
    var serviceState: SettingsServicePresentationState? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.fg)

                SettingsTabBar(selection: $selectedTab)
            }
            .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .overlay(Theme.borderStrong.opacity(0.7))

            ScrollView {
                SettingsTabContent(
                    selection: selectedTab,
                    driver: driver,
                    serviceHealth: serviceHealth,
                    paths: paths,
                    serviceState: resolvedServiceState
                )
                .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBgMuted)
        .foregroundStyle(Theme.fg)
    }

    private var resolvedServiceState: SettingsServicePresentationState {
        serviceState ?? settingsServicePresentationState(
            health: serviceHealth,
            isRefreshing: driver.state.isRefreshingService,
            statusMessage: driver.state.statusMessage
        )
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        Picker("Settings category", selection: $selection) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.symbolName)
                    .tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 480, alignment: .leading)
        .accessibilityLabel("Settings category")
    }
}

private struct SettingsTabContent: View {
    var selection: SettingsTab
    var driver: SettingsDriver
    var serviceHealth: HealthPayload?
    var paths: AppPaths?
    var serviceState: SettingsServicePresentationState

    @ViewBuilder
    var body: some View {
        switch selection {
        case .general:
            SettingsGeneralPane(driver: driver, paths: paths)
        case .shortcuts:
            SettingsShortcutsPane(driver: driver)
        case .system:
            SettingsSystemPane(
                driver: driver,
                serviceHealth: serviceHealth,
                serviceState: serviceState
            )
        }
    }
}

private struct SettingsGeneralPane: View {
    var driver: SettingsDriver
    var paths: AppPaths?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Recording") {
                SettingsToggleRow(title: "Create zooms automatically", isOn: driver.autoZoomBinding)
                SettingsZoomPresetPicker(selection: driver.autoZoomAnimationPresetBinding)
            }

            SettingsSection(title: "Folders") {
                FolderRow(title: "Recordings", path: paths?.recordingsDir) {
                    driver.send(.folderOpenRequested($0))
                }
                FolderRow(title: "Screenshots", path: paths?.screenshotsDir) {
                    driver.send(.folderOpenRequested($0))
                }
                FolderRow(title: "Projects", path: paths?.projectsDir) {
                    driver.send(.folderOpenRequested($0))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsShortcutsPane: View {
    @State private var recorderSession = ShortcutRecorderSession()

    var driver: SettingsDriver

    var body: some View {
        SettingsSection(title: "Global Shortcuts") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Use Open Recorder's quick shortcuts from any application to capture screens and recordings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fgMuted)
                    .padding(.bottom, 10)

                ForEach(CaptureShortcutAction.allCases) { action in
                    if action != CaptureShortcutAction.allCases.first {
                        Divider().overlay(Color.white.opacity(0.06))
                    }

                    SettingsShortcutRow(
                        action: action,
                        item: driver.shortcutBinding(for: action),
                        isRecording: recorderSession.isRecording(action),
                        isAwaitingRelease: recorderSession.isAwaitingRelease(action),
                        previewModifiers: recorderSession.previewModifiers,
                        errorMessage: recorderSession.isRecording(action) ? recorderSession.errorMessage : nil,
                        onRecordRequested: { toggleRecording(for: action) },
                        onRecordingCancelled: cancelRecording
                    )
                }

                Button("Restore Default Shortcuts") {
                    cancelRecording()
                    driver.send(.shortcutsResetToDefaults)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)
            }
        }
        .background {
            SettingsShortcutEventMonitor(
                isEnabled: recorderSession.isActive,
                handler: handleRecorderEvent,
                windowDidResignKey: cancelRecording
            )
            .frame(width: 0, height: 0)
        }
        .onDisappear(perform: cancelRecording)
    }

    private func toggleRecording(for action: CaptureShortcutAction) {
        if recorderSession.isRecording(action) {
            cancelRecording()
            return
        }

        let wasActive = recorderSession.isActive
        recorderSession.begin(action)
        if !wasActive {
            driver.shortcutRecorderActive(true)
        }
    }

    private func cancelRecording() {
        guard recorderSession.isActive else { return }
        recorderSession.cancel()
        driver.shortcutRecorderActive(false)
    }

    private func handleRecorderEvent(_ event: NSEvent) -> Bool {
        guard recorderSession.isActive else { return false }

        switch event.type {
        case .flagsChanged:
            recorderSession.updateModifiers(ShortcutModifiers(eventModifierFlags: event.modifierFlags))
            return true

        case .keyDown:
            if ShortcutCapturePolicy.isCancelKey(UInt32(event.keyCode)) {
                cancelRecording()
                return true
            }
            guard !event.isARepeat,
                  case .recording(let action) = recorderSession.phase else {
                return true
            }

            let capturedKey = ShortcutCapturedKey(event: event)
            let validator = ShortcutAvailabilityValidator()
            if let error = validator.validationError(
                for: capturedKey,
                editing: action,
                preferences: driver.state.shortcuts
            ) {
                recorderSession.reject(error)
                return true
            }

            var updatedItem = driver.state.shortcuts.item(for: action)
            updatedItem.keyCombination = capturedKey.combination
            recorderSession.accept(capturedKey.combination)
            driver.send(.shortcutItemChanged(updatedItem))
            return true

        case .keyUp:
            if recorderSession.completeKeyRelease(UInt32(event.keyCode)) {
                driver.shortcutRecorderActive(false)
            }
            return true

        default:
            return false
        }
    }
}

private struct SettingsSystemPane: View {
    var driver: SettingsDriver
    var serviceHealth: HealthPayload?
    var serviceState: SettingsServicePresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    ControlGroup {
                        Button {
                            driver.send(.screenRecordingSettingsRequested)
                        } label: {
                            Label("Screen Recording", systemImage: "lock.shield")
                        }

                        Button {
                            driver.send(.accessibilitySettingsRequested)
                        } label: {
                            Label("Accessibility", systemImage: "accessibility")
                        }
                    }
                    .controlSize(.regular)

                    Button {
                        driver.send(.onboardingReviewRequested)
                    } label: {
                        Label("Review Permissions", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            SettingsSection(title: "Service") {
                SettingsServiceStatusRow(state: serviceState)
                SettingsRow(title: "Platform", value: serviceHealth?.platform ?? "macOS")
                Button {
                    driver.send(.serviceRefreshRequested)
                } label: {
                    Label(serviceState.isChecking ? "Checking Service…" : "Check Service", systemImage: "bolt.horizontal")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(serviceState.isChecking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsShortcutRow: View {
    var action: CaptureShortcutAction
    @Binding var item: ShortcutItem
    var isRecording: Bool
    var isAwaitingRelease: Bool
    var previewModifiers: ShortcutModifiers
    var errorMessage: String?
    var onRecordRequested: () -> Void
    var onRecordingCancelled: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.isEnabled ? Theme.fg : Theme.fgMuted)
                Text(action.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Button(action: onRecordRequested) {
                    HStack(spacing: 7) {
                        Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isRecording ? Theme.accent : Theme.fgMuted)
                            .accessibilityHidden(true)
                        Text(recorderLabel)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(item.isEnabled ? Color.white : Theme.fgMuted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !isRecording {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.fgMuted)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(recorderBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(recorderBorder, lineWidth: isRecording ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .accessibilityLabel("Change shortcut for \(action.title)")
                .accessibilityValue(isRecording ? recorderLabel : item.keyCombination.displayString)
                .accessibilityHint(isRecording ? "Press a shortcut. Press Escape to cancel." : "Press to record a new shortcut.")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Shortcut error: \(errorMessage)")
                }
            }
            .frame(width: 210, alignment: .leading)

            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .labelsHidden()
                .controlSize(.small)
                .padding(.top, 7)
                .accessibilityLabel("Enable \(action.title) shortcut")
        }
        .padding(.vertical, 9)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { item.isEnabled },
            set: { isEnabled in
                item.isEnabled = isEnabled
                if !isEnabled && isRecording {
                    onRecordingCancelled()
                }
            }
        )
    }

    private var recorderLabel: String {
        guard isRecording else { return item.keyCombination.displayString }
        if isAwaitingRelease {
            return item.keyCombination.displayString
        }
        let modifiers = previewModifiers.displayString
        return modifiers.isEmpty ? "Press shortcut…" : "\(modifiers)…"
    }

    private var recorderBackground: Color {
        if isRecording {
            return Theme.accent.opacity(0.16)
        }
        return item.isEnabled ? Color.white.opacity(0.10) : Color.white.opacity(0.04)
    }

    private var recorderBorder: Color {
        if isRecording {
            return Theme.accent.opacity(0.9)
        }
        return item.isEnabled ? Color.white.opacity(0.20) : Color.white.opacity(0.07)
    }
}

private struct SettingsShortcutEventMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var handler: (NSEvent) -> Bool
    var windowDidResignKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler, windowDidResignKey: windowDidResignKey)
    }

    func makeNSView(context: Context) -> StudioKeyMonitorAttachmentView {
        let view = StudioKeyMonitorAttachmentView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.handler = handler
        context.coordinator.windowDidResignKey = windowDidResignKey
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: StudioKeyMonitorAttachmentView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.handler = handler
        context.coordinator.windowDidResignKey = windowDidResignKey
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
    }

    static func dismantleNSView(_ nsView: StudioKeyMonitorAttachmentView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject {
        weak var view: StudioKeyMonitorAttachmentView?
        var handler: (NSEvent) -> Bool
        var windowDidResignKey: () -> Void
        var isEnabled = false
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool, windowDidResignKey: @escaping () -> Void) {
            self.handler = handler
            self.windowDidResignKey = windowDidResignKey
        }

        func install() {
            guard monitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let windowScope = view.windowScope.snapshot(),
                      StudioKeyEventScope.shouldHandle(
                          isEnabled: self.isEnabled,
                          ownerWindowNumber: windowScope.windowNumber,
                          eventWindowNumber: event.windowNumber,
                          ownerWindowIsKey: windowScope.isKey
                      ) else {
                    return event
                }
                return self.handler(event) ? nil : event
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(ownerWindowDidResignKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor @objc private func ownerWindowDidResignKey(_ notification: Notification) {
            guard isEnabled,
                  let ownerWindow = view?.window,
                  let resignedWindow = notification.object as? NSWindow,
                  ownerWindow === resignedWindow else {
                return
            }
            windowDidResignKey()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private struct SettingsZoomPresetPicker: View {
    @Binding var selection: TimelineZoomAnimationPreset

    var body: some View {
        LabeledContent {
            Picker("Auto zoom style", selection: $selection) {
                ForEach(TimelineZoomAnimationPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        } label: {
            Text("Auto zoom style")
                .foregroundStyle(Theme.fgMuted)
        }
        .font(.system(size: 13))
        .accessibilityHint("Controls the timing and motion used for automatically created zooms")
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                .stroke(Theme.overlay)
        }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.fgMuted)
            content
        }
        .padding(Theme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                .stroke(Theme.borderStrong.opacity(0.7))
        }
    }
}

struct SettingsRow: View {
    var title: String
    var value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Theme.fg)
        } label: {
            Text(title)
                .foregroundStyle(Theme.fgMuted)
        }
        .font(.system(size: 13))
    }
}

private struct SettingsServiceStatusRow: View {
    var state: SettingsServicePresentationState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 7) {
                    if state.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(state.value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.fg)
                }
            } label: {
                Text("Status")
                    .foregroundStyle(Theme.fgMuted)
            }
            if let detail = state.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
    }
}

struct FolderRow: View {
    var title: String
    var path: String?
    var onOpen: (String) -> Void = { _ in }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(path ?? "Not available")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(path == nil ? Color.secondary : Theme.fg)
                Button {
                    guard let path else { return }
                    onOpen(path)
                } label: {
                    Label("Open \(title) Folder", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(path == nil)
                .help(path == nil ? "Folder path is unavailable" : "Open \(title) folder")
            }
        } label: {
            Text(title)
                .foregroundStyle(Theme.fgMuted)
        }
        .font(.system(size: 13))
    }
}

struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        LabeledContent {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        } label: {
            Text(title)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(Theme.fgMuted)
        .font(.system(size: 13))
    }
}
