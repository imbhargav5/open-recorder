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
    var driver: SettingsDriver

    var body: some View {
        SettingsSection(title: "Global Shortcuts") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Use Open Recorder's quick shortcuts from any application to capture screens and recordings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.fgMuted)
                    .padding(.bottom, 4)

                SettingsShortcutRow(
                    action: .deviceScreenshot,
                    item: driver.shortcutBinding(for: .deviceScreenshot)
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsShortcutRow(
                    action: .dragScreenshot,
                    item: driver.shortcutBinding(for: .dragScreenshot)
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsShortcutRow(
                    action: .deviceScreenRecord,
                    item: driver.shortcutBinding(for: .deviceScreenRecord)
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsShortcutRow(
                    action: .dragScreenRecord,
                    item: driver.shortcutBinding(for: .dragScreenRecord)
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsShortcutRow(
                    action: .toggleRecording,
                    item: driver.shortcutBinding(for: .toggleRecording)
                )

                Button("Restore Default Shortcuts") {
                    driver.send(.shortcutsResetToDefaults)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.isEnabled ? Theme.fg : Theme.fgMuted)
                Text(action.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted.opacity(0.8))
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(action.availablePresets) { preset in
                    Button {
                        item.keyCombination = preset
                        item.isEnabled = true
                    } label: {
                        HStack {
                            Text(preset.displayString)
                            if item.keyCombination == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(item.keyCombination.displayString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(item.isEnabled ? Color.white : Theme.fgMuted)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.fgMuted)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(item.isEnabled ? Color.white.opacity(0.12) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(item.isEnabled ? Color.white.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!item.isEnabled)

            Toggle("", isOn: $item.isEnabled)
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.vertical, 3)
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
