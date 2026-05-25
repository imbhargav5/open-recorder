import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: ProjectLibraryTab = .screenRecordings
    @State private var projectPendingDeletion: ProjectSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Projects")
                                .font(.system(size: 26, weight: .semibold))
                            Text("Local")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 6))
                        }
                        Text("Open saved captures from this device.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    StudioButton(hitTarget: .rounded(7)) {
                        model.refreshBackendState()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(height: 32)
                            .padding(.horizontal, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.white)
                    }
                }

                ProjectLibraryTabBar(
                    selection: $selectedTab,
                    recordingCount: recordingProjects.count,
                    screenshotCount: screenshotProjects.count
                )

                HStack(spacing: 16) {
                    switch selectedTab {
                    case .screenRecordings:
                        ProjectActionCard(
                            title: "Open project",
                            symbolName: "plus",
                            description: "Load an Open Recorder editing session.",
                            buttonTitle: "Choose file",
                            style: .primary
                        ) {
                            model.openProjectFile()
                        }
                        ProjectActionCard(
                            title: "Recordings folder",
                            symbolName: "folder",
                            description: "Jump to saved recordings and exports.",
                            buttonTitle: "Browse recordings",
                            style: .secondary
                        ) {
                            if let path = model.paths?.recordingsDir {
                                model.openPath(path)
                            }
                        }
                    case .screenshots:
                        ProjectActionCard(
                            title: "Open project",
                            symbolName: "plus",
                            description: "Load a saved screenshot project.",
                            buttonTitle: "Choose file",
                            style: .primary
                        ) {
                            model.openProjectFile()
                        }
                        ProjectActionCard(
                            title: "Screenshots folder",
                            symbolName: "photo.on.rectangle",
                            description: "Jump to captured screenshot images.",
                            buttonTitle: "Browse screenshots",
                            style: .secondary
                        ) {
                            if let path = model.paths?.screenshotsDir {
                                model.openPath(path)
                            }
                        }
                    }
                }

                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(selectedTab.listTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if selectedProjects.isEmpty {
                        EmptyProjectsPanel(tab: selectedTab)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(selectedProjects) { project in
                                ProjectListRow(project: project) { project in
                                    projectPendingDeletion = project
                                }
                                if project.id != selectedProjects.last?.id {
                                    Rectangle()
                                        .fill(Theme.border)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .background(Theme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.border)
                        }
                    }
                }
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBgMuted)
        .confirmationDialog(
            "Delete Project?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let projectPendingDeletion {
                Button("Move to Trash", role: .destructive) {
                    model.deleteProject(projectPendingDeletion)
                    self.projectPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: {
            Text("This moves the .openrecorder project file to Trash. The recording or screenshot media file will not be deleted.")
        }
    }

    private var recordingProjects: [ProjectSummary] {
        model.projects.filter { $0.mediaKind == .video }
    }

    private var screenshotProjects: [ProjectSummary] {
        model.projects.filter { $0.mediaKind == .screenshot }
    }

    private var selectedProjects: [ProjectSummary] {
        switch selectedTab {
        case .screenRecordings:
            recordingProjects
        case .screenshots:
            screenshotProjects
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { projectPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    projectPendingDeletion = nil
                }
            }
        )
    }
}

enum ProjectLibraryTab: String, CaseIterable, Identifiable {
    case screenRecordings
    case screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenRecordings: "Screen Recordings"
        case .screenshots: "Screenshots"
        }
    }

    var symbolName: String {
        switch self {
        case .screenRecordings: "video.fill"
        case .screenshots: "photo.fill"
        }
    }

    var listTitle: String {
        switch self {
        case .screenRecordings: "Recent screen recordings"
        case .screenshots: "Recent screenshots"
        }
    }
}

struct ProjectLibraryTabBar: View {
    @Binding var selection: ProjectLibraryTab
    var recordingCount: Int
    var screenshotCount: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ProjectLibraryTab.allCases) { tab in
                StudioButton(hitTarget: .rounded(8), help: tab.title) {
                    selection = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("\(count(for: tab))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selection == tab ? Color.white.opacity(0.75) : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(selection == tab ? 0.16 : 0.06), in: Capsule())
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 12)
                    .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                    .background(selection == tab ? Theme.accent : Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
        }
        .padding(4)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border.opacity(0.9))
        }
    }

    private func count(for tab: ProjectLibraryTab) -> Int {
        switch tab {
        case .screenRecordings:
            recordingCount
        case .screenshots:
            screenshotCount
        }
    }
}

enum ProjectActionCardStyle: Equatable {
    case primary
    case secondary
}

struct ProjectActionCard: View {
    var title: String
    var symbolName: String
    var description: String
    var buttonTitle: String
    var style: ProjectActionCardStyle
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            StudioButton(hitTarget: .rounded(8), action: action) {
                Label(buttonTitle, systemImage: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(style == .primary ? Theme.accent : Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(style == .primary ? Color.white : Color.primary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border)
        }
    }
}

struct ProjectListRow: View {
    @EnvironmentObject private var model: AppModel
    var project: ProjectSummary
    var requestDelete: (ProjectSummary) -> Void

    var body: some View {
        StudioButton(hitTarget: .rectangle) {
            if !project.missing {
                model.openProject(project)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: project.mediaKind.titleIconSystemName)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Theme.accent.opacity(0.22))
                    }
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(project.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        if project.missing {
                            Text("Missing")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.red.opacity(0.35))
                                }
                        }
                    }
                    HStack(spacing: 12) {
                        Text(project.sourceName ?? URL(fileURLWithPath: project.mediaPath ?? project.path).lastPathComponent)
                            .lineLimit(1)
                        Label(formattedProjectDate(project.lastOpenedAt), systemImage: "clock")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(project.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .contextMenu {
            Button {
                model.openProject(project)
            } label: {
                Label("Open", systemImage: "folder")
            }
            .disabled(project.missing)

            Button(role: .destructive) {
                requestDelete(project)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .opacity(project.missing ? 0.55 : 1)
    }
}

struct EmptyProjectsPanel: View {
    var tab: ProjectLibraryTab

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 30))
                .frame(width: 64, height: 64)
                .foregroundStyle(Theme.accent)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            Text(tab == .screenRecordings ? "No recent recordings yet" : "No recent screenshots yet")
                .font(.system(size: 16, weight: .semibold))
            Text(tab == .screenRecordings ? "Screen recording projects will appear here after you save or open one." : "Screenshot projects will appear here after you capture or open one.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Theme.surface.opacity(0.60), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}


func formattedProjectDate(_ value: String) -> String {
    let date: Date
    if let seconds = TimeInterval(value) {
        date = Date(timeIntervalSince1970: seconds)
    } else {
        let formatter = ISO8601DateFormatter()
        date = formatter.date(from: value) ?? Date()
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: date)
}
