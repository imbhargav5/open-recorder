import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SettingsStudioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                SettingsSection(title: "Service") {
                    SettingsRow(title: "Status", value: model.serviceHealth.map { "\($0.service) \($0.version)" } ?? "Unavailable")
                    SettingsRow(title: "Platform", value: model.serviceHealth?.platform ?? "macOS")
                    StudioButton(hitTarget: .rounded(8)) {
                        model.refreshBackendState()
                    } label: {
                        Label("Check Service", systemImage: "bolt.horizontal")
                            .frame(height: 34)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                SettingsSection(title: "Folders") {
                    FolderRow(title: "Recordings", path: model.paths?.recordingsDir)
                    FolderRow(title: "Screenshots", path: model.paths?.screenshotsDir)
                    FolderRow(title: "Projects", path: model.paths?.projectsDir)
                }

                SettingsSection(title: "Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            StudioButton(hitTarget: .rounded(8)) {
                                model.openPrivacySettings()
                            } label: {
                                Label("Screen Recording", systemImage: "lock.shield")
                                    .frame(height: 34)
                                    .padding(.horizontal, 12)
                                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.white)
                            }

                            StudioButton(hitTarget: .rounded(8)) {
                                model.openAccessibilitySettings()
                            } label: {
                                Label("Accessibility", systemImage: "accessibility")
                                    .frame(height: 34)
                                    .padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Color.white.opacity(0.86))
                            }
                        }

                        StudioButton(hitTarget: .rounded(8)) {
                            model.showOnboarding()
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
    @EnvironmentObject private var model: AppModel
    var title: String
    var path: String?

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
                    model.openPath(path)
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
