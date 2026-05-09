import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsStudioView: View {
    @EnvironmentObject private var model: AppModel

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
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                        }
                        Text("Open a saved project or browse recordings from this device.")
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
                            .background(Color.brand, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 16) {
                    ProjectActionCard(title: "Open project", symbolName: "plus", description: "Load an Open Recorder editing session.") {
                        model.openProjectFile()
                    }
                    ProjectActionCard(title: "Recordings folder", symbolName: "folder", description: "Jump to saved captures and exported videos.") {
                        if let path = model.paths?.recordingsDir {
                            model.openPath(path)
                        }
                    }
                }

                Rectangle()
                    .fill(Color.studioBorder)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent projects")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if model.projects.isEmpty {
                        EmptyProjectsPanel()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.projects) { project in
                                ProjectListRow(project: project)
                                if project.id != model.projects.last?.id {
                                    Rectangle()
                                        .fill(Color.studioBorder)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .background(Color.studioPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.studioBorder)
                        }
                    }
                }
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioMutedBackground)
    }
}

struct ProjectActionCard: View {
    var title: String
    var symbolName: String
    var description: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(Color.brand)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            StudioButton(hitTarget: .rounded(8), action: action) {
                Label(title == "Open project" ? "Choose file" : "Browse recordings", systemImage: symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(title == "Open project" ? Color.brand : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(title == "Open project" ? Color.white : Color.primary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioPanel.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder)
        }
    }
}

struct ProjectListRow: View {
    @EnvironmentObject private var model: AppModel
    var project: ProjectSummary

    var body: some View {
        StudioButton(hitTarget: .rectangle) {
            if !project.missing {
                model.openProject(project)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.brand.opacity(0.22))
                    }
                    .foregroundStyle(Color.brand)

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
                        Text(project.sourceName ?? URL(fileURLWithPath: project.recordingPath ?? project.path).lastPathComponent)
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
        .opacity(project.missing ? 0.55 : 1)
    }
}

struct EmptyProjectsPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 30))
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.brand)
                .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            Text("No recent projects yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Recent project shortcuts will appear here after you save or open one.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(Color.studioPanel.opacity(0.60), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
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

