import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: ProjectLibraryTab = .screenRecordings
    @State private var projectPendingDeletion: ProjectSummary?
    @State private var selectedProjectID: ProjectSummary.ID?
    @State private var searchText = ""
    @State private var sortOrder = [ProjectLibraryComparator(field: .lastOpened, order: .reverse)]

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

                    HStack(spacing: 8) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Refreshing projects")
                        }

                        Button {
                            model.refreshBackendState()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(isRefreshing)
                        .help(isRefreshing ? "Refreshing projects" : "Refresh projects")
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
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(selectedProjects.count) found")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }

                    if let backendFailureMessage, !model.projects.isEmpty {
                        ProjectLibraryFailureBanner(message: backendFailureMessage) {
                            model.refreshBackendState()
                        }
                    }

                    if isInitialLoadPending {
                        ProjectLibraryIdlePanel {
                            model.refreshBackendState()
                        }
                    } else if isLoadingWithoutProjects {
                        ProjectLibraryLoadingPanel()
                    } else if selectedProjects.isEmpty, isFailedWithoutProjects {
                        ProjectLibraryFailurePanel(message: backendFailureMessage ?? "The project library could not be loaded.") {
                            model.refreshBackendState()
                        }
                    } else if selectedProjects.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if selectedProjects.isEmpty {
                        EmptyProjectsPanel(tab: selectedTab)
                    } else {
                        projectTable
                    }
                }
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBgMuted)
        .searchable(text: $searchText, prompt: "Search projects")
        .onChange(of: selectedTab) {
            selectedProjectID = nil
        }
        .onChange(of: searchText) {
            if let selectedProjectID,
               !selectedProjects.contains(where: { $0.id == selectedProjectID }) {
                self.selectedProjectID = nil
            }
        }
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
        ProjectLibraryQuery.projects(
            from: model.projects,
            tab: selectedTab,
            searchText: searchText,
            sortOrder: sortOrder
        )
    }

    @ViewBuilder
    private var projectTable: some View {
        Table(selectedProjects, selection: $selectedProjectID, sortOrder: $sortOrder) {
            TableColumn("Project", sortUsing: ProjectLibraryComparator(field: .title)) { project in
                HStack(spacing: 8) {
                    Image(systemName: project.mediaKind.titleIconSystemName)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(project.title)
                        .lineLimit(1)
                    if let availabilityLabel = project.libraryAvailabilityLabel {
                        Text(availabilityLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Source", sortUsing: ProjectLibraryComparator(field: .source)) { project in
                Text(projectSourceDisplayName(project))
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)

            TableColumn("Last opened", sortUsing: ProjectLibraryComparator(field: .lastOpened)) { project in
                Text(formattedProjectDate(project.lastOpenedAt))
                    .lineLimit(1)
            }
            .width(min: 130, ideal: 160)

            TableColumn("Project file", sortUsing: ProjectLibraryComparator(field: .path)) { project in
                Text(project.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .width(min: 170, ideal: 260)
        }
        .frame(height: min(max(CGFloat(selectedProjects.count * 34 + 44), 240), 480))
        .contextMenu(forSelectionType: ProjectSummary.ID.self) { selection in
            if let project = onlyProject(in: selection) {
                Button {
                    open(project)
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .disabled(!project.isOpenableFromLibrary)

                Divider()

                Button(role: .destructive) {
                    projectPendingDeletion = project
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } primaryAction: { selection in
            guard let project = onlyProject(in: selection) else { return }
            open(project)
        }
        .onKeyPress(.return) {
            guard let project = selectedProject, project.isOpenableFromLibrary else { return .ignored }
            open(project)
            return .handled
        }
        .onDeleteCommand {
            guard let project = selectedProject else { return }
            projectPendingDeletion = project
        }
    }

    private func onlyProject(in selection: Set<ProjectSummary.ID>) -> ProjectSummary? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return model.projects.first { $0.id == id }
    }

    private var selectedProject: ProjectSummary? {
        guard let selectedProjectID else { return nil }
        return model.projects.first { $0.id == selectedProjectID }
    }

    private func open(_ project: ProjectSummary) {
        guard project.isOpenableFromLibrary else { return }
        model.openProject(project)
    }

    private var isRefreshing: Bool {
        if case .loading = model.backendLoadPhase { return true }
        return false
    }

    private var isInitialLoadPending: Bool {
        guard model.projects.isEmpty else { return false }
        if case .idle = model.backendLoadPhase { return true }
        return false
    }

    private var isLoadingWithoutProjects: Bool {
        isRefreshing && model.projects.isEmpty
    }

    private var isFailedWithoutProjects: Bool {
        guard model.projects.isEmpty else { return false }
        if case .failed = model.backendLoadPhase { return true }
        return false
    }

    private var backendFailureMessage: String? {
        if case .failed(let message) = model.backendLoadPhase {
            return message
        }
        return nil
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

    var mediaKind: EditorMediaKind {
        switch self {
        case .screenRecordings: .video
        case .screenshots: .screenshot
        }
    }
}

struct ProjectLibraryTabBar: View {
    @Binding var selection: ProjectLibraryTab
    var recordingCount: Int
    var screenshotCount: Int

    var body: some View {
        Picker("Project type", selection: $selection) {
            ForEach(ProjectLibraryTab.allCases) { tab in
                Label("\(tab.title) (\(count(for: tab)))", systemImage: tab.symbolName)
                    .tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 480, alignment: .leading)
        .accessibilityLabel("Project type")
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
            if project.isOpenableFromLibrary {
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
                        if let availabilityLabel = project.libraryAvailabilityLabel {
                            Text(availabilityLabel)
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
            .disabled(!project.isOpenableFromLibrary)

            Button(role: .destructive) {
                requestDelete(project)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .opacity(project.isOpenableFromLibrary ? 1 : 0.55)
    }
}

struct EmptyProjectsPanel: View {
    var tab: ProjectLibraryTab

    var body: some View {
        ContentUnavailableView {
            Label(
                tab == .screenRecordings ? "No recent recordings yet" : "No recent screenshots yet",
                systemImage: tab.symbolName
            )
        } description: {
            Text(tab == .screenRecordings ? "Screen recording projects will appear here after you save or open one." : "Screenshot projects will appear here after you capture or open one.")
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Theme.surface.opacity(0.60), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}

private struct ProjectLibraryLoadingPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading projects…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectLibraryIdlePanel: View {
    var load: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Projects not loaded", systemImage: "rectangle.stack")
        } description: {
            Text("Load projects saved on this Mac.")
        } actions: {
            Button("Load Projects", action: load)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

private struct ProjectLibraryFailurePanel: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Projects unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

private struct ProjectLibraryFailureBanner: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Try Again", action: retry)
                .controlSize(.small)
                .disabled(false)
        }
        .padding(10)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}


func formattedProjectDate(_ value: String) -> String {
    guard let date = projectDate(value) else { return "Unknown" }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: date)
}
