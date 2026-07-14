import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SettingsStudioView: View {
    var driver: SettingsDriver
    var serviceHealth: HealthPayload?
    var paths: AppPaths?
    var serviceState: SettingsServicePresentationState? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                SettingsSection(title: "Service") {
                    SettingsServiceStatusRow(state: resolvedServiceState)
                    SettingsRow(title: "Platform", value: serviceHealth?.platform ?? "macOS")
                    Button {
                        driver.send(.serviceRefreshRequested)
                    } label: {
                        Label(resolvedServiceState.isChecking ? "Checking Service…" : "Check Service", systemImage: "bolt.horizontal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(resolvedServiceState.isChecking)
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

                SettingsSection(title: "Recording") {
                    SettingsToggleRow(title: "Create zooms automatically", isOn: driver.autoZoomBinding)
                    SettingsZoomPresetPicker(selection: driver.autoZoomAnimationPresetBinding)
                }

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
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
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

private struct SettingsZoomPresetPicker: View {
    @Binding var selection: TimelineZoomAnimationPreset

    var body: some View {
        Picker("Auto zoom style", selection: $selection) {
            ForEach(TimelineZoomAnimationPreset.allCases) { preset in
                Text(preset.title)
                    .tag(preset)
                }
        }
        .pickerStyle(.menu)
        .foregroundStyle(Theme.fgMuted)
        .accessibilityHint("Controls the timing and motion used for automatically created zooms")
        .padding(10)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.overlay)
        }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.fgMuted)
            content
        }
        .padding(18)
        .background(Theme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border)
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
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .foregroundStyle(Theme.fgMuted)
            .font(.system(size: 13))
    }
}
