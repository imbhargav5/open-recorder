import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SettingsStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var driver = SettingsDriver(createZoomsAutomatically: false)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                SettingsSection(title: "Service") {
                    SettingsRow(title: "Status", value: driver.state.serviceHealth.map { "\($0.service) \($0.version)" } ?? "Unavailable")
                    SettingsRow(title: "Platform", value: driver.state.serviceHealth?.platform ?? "macOS")
                    StudioButton(hitTarget: .rounded(8)) {
                        driver.send(.serviceRefreshRequested)
                    } label: {
                        Label("Check Service", systemImage: "bolt.horizontal")
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                SettingsSection(title: "Folders") {
                    FolderRow(title: "Recordings", path: driver.state.paths?.recordingsDir) {
                        driver.send(.folderOpenRequested($0))
                    }
                    FolderRow(title: "Screenshots", path: driver.state.paths?.screenshotsDir) {
                        driver.send(.folderOpenRequested($0))
                    }
                    FolderRow(title: "Projects", path: driver.state.paths?.projectsDir) {
                        driver.send(.folderOpenRequested($0))
                    }
                }

                SettingsSection(title: "Recording") {
                    SettingsToggleRow(title: "Create zooms automatically", isOn: driver.autoZoomBinding)
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
                                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.white)
                            }

                            StudioButton(hitTarget: .rounded(8)) {
                                driver.send(.accessibilitySettingsRequested)
                            } label: {
                                Label("Accessibility", systemImage: "accessibility")
                                    .frame(height: 34)
                                    .padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Color.white.opacity(0.86))
                            }
                        }

                        StudioButton(hitTarget: .rounded(8)) {
                            driver.send(.onboardingReviewRequested)
                        } label: {
                            Label("Review Permissions", systemImage: "checklist")
                                .frame(height: 34)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(Color.white.opacity(0.86))
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioMutedBackground)
        .onAppear {
            driver.configure(
                refreshService: {
                    if model.refreshBackendState() {
                        driver.send(.serviceRefreshSucceeded(serviceHealth: model.serviceHealth, paths: model.paths))
                    } else {
                        driver.send(.serviceRefreshFailed(model.statusMessage))
                    }
                },
                persistAutoZoomPreference: { value in
                    model.createZoomsAutomatically = value
                },
                openFolder: { path in
                    model.openPath(path)
                },
                openScreenRecordingSettings: {
                    model.openPrivacySettings()
                },
                openAccessibilitySettings: {
                    model.openAccessibilitySettings()
                },
                showOnboarding: {
                    model.showOnboarding()
                }
            )
            driver.send(.autoZoomPreferenceSynced(model.createZoomsAutomatically))
            driver.send(.appeared(serviceHealth: model.serviceHealth, paths: model.paths))
        }
        .onChange(of: model.serviceHealth) { _, _ in
            driver.send(.appeared(serviceHealth: model.serviceHealth, paths: model.paths))
        }
        .onChange(of: model.paths) { _, _ in
            driver.send(.appeared(serviceHealth: model.serviceHealth, paths: model.paths))
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
                .foregroundStyle(.secondary)
            content
        }
        .padding(18)
        .background(Color.studioPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
    }
}

struct SettingsRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(path ?? "Unknown")
                .lineLimit(1)
                .truncationMode(.middle)
            if let path {
                StudioButton(hitTarget: .rounded(7)) {
                    onOpen(path)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
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
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .font(.system(size: 13))
    }
}
