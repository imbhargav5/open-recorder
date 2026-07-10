import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SettingsStudioView: View {
    var driver: SettingsDriver
    var serviceHealth: HealthPayload?
    var paths: AppPaths?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                SettingsSection(title: "Service") {
                    SettingsRow(title: "Status", value: serviceHealth.map { "\($0.service) \($0.version)" } ?? "Unavailable")
                    SettingsRow(title: "Platform", value: serviceHealth?.platform ?? "macOS")
                    StudioButton(hitTarget: .rounded(8)) {
                        driver.send(.serviceRefreshRequested)
                    } label: {
                        Label("Check Service", systemImage: "bolt.horizontal")
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Theme.fg)
                    }
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
                        HStack(spacing: 10) {
                            StudioButton(hitTarget: .rounded(8)) {
                                driver.send(.screenRecordingSettingsRequested)
                            } label: {
                                Label("Screen Recording", systemImage: "lock.shield")
                                    .frame(height: 34)
                                    .padding(.horizontal, 12)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.white)
                            }

                            StudioButton(hitTarget: .rounded(8)) {
                                driver.send(.accessibilitySettingsRequested)
                            } label: {
                                Label("Accessibility", systemImage: "accessibility")
                                    .frame(height: 34)
                                    .padding(.horizontal, 12)
                                    .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Color.white.opacity(0.86))
                            }
                        }

                        StudioButton(hitTarget: .rounded(8)) {
                            driver.send(.onboardingReviewRequested)
                        } label: {
                            Label("Review Permissions", systemImage: "checklist")
                                .frame(height: 34)
                                .padding(.horizontal, 12)
                                .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(Color.white.opacity(0.86))
                        }
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
}

private struct SettingsZoomPresetPicker: View {
    @Binding var selection: TimelineZoomAnimationPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Auto zoom style")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text(selection.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(TimelineZoomAnimationPreset.allCases) { preset in
                    let isSelected = selection == preset
                    StudioButton(hitTarget: .rounded(7)) {
                        selection = preset
                    } label: {
                        Text(preset.shortTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .background(isSelected ? Theme.accent.opacity(0.18) : Theme.overlay, in: RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isSelected ? Theme.accent.opacity(0.42) : Theme.overlay, lineWidth: isSelected ? 1.5 : 1)
                            }
                    }
                    .help(preset.title)
                    .accessibilityLabel("Set auto zoom style to \(preset.title)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
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
        HStack {
            Text(title)
                .foregroundStyle(Theme.fgMuted)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Theme.fg)
        }
        .font(.system(size: 13))
    }
}

struct FolderRow: View {
    var title: String
    var path: String?
    var onOpen: (String) -> Void = { _ in }

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.fgMuted)
            Spacer()
            Text(path ?? "Unknown")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Theme.fg)
            if let path {
                StudioButton(hitTarget: .rounded(7)) {
                    onOpen(path)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(Theme.fgMuted)
                }
            }
        }
        .font(.system(size: 13))
    }
}

struct SettingsToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.fgMuted)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
        .font(.system(size: 13))
    }
}
