import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SourceSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    private var sourceSelector: SourceSelectorDriver {
        model.appShell.floatingSourceSelector
    }

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        SourceSelectorCard(
            sourceTab: sourceSelector.sourceTabBinding,
            visibleTabs: sourceSelector.state.visibleTabs,
            allSources: model.capture.sources,
            selectedSourceID: sourceSelector.state.pendingSourceID,
            captureMode: model.captureMode,
            loadPhase: sourceSelector.state.loadPhase,
            onCancel: {
                sourceSelector.send(.cancelRequested)
            },
            onRefresh: {
                sourceSelector.send(.refreshRequested)
            },
            onSelectSource: { source in
                sourceSelector.send(.sourceSelected(source.id))
            },
            onDrawArea: {
                sourceSelector.send(.drawAreaRequested)
            }
        )
        .frame(width: SourceSelectorWindowMetrics.width, height: SourceSelectorWindowMetrics.height)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(Theme.surface.opacity(0.96))
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .onAppear {
            sourceSelector.configure(
                refreshSources: {
                    await model.refreshSources(requestScreenRecordingPermission: true)
                    return SourceSelectorRefreshResult(
                        sourceIDs: model.capture.sources.map(\.id),
                        errorMessage: model.capture.sourceCatalogState.issueMessage
                    )
                },
                cancel: {
                    model.cancelSourceSelection()
                    dismissWindow(id: "source-selector")
                },
                select: { sourceID in
                    guard let source = model.capture.sources.first(where: { $0.id == sourceID }) else {
                        return
                    }
                    model.selectSource(source)
                    dismissWindow(id: "source-selector")
                },
                drawArea: {
                    dismissWindow(id: "source-selector")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        model.requestInteractiveAreaSelection()
                    }
                }
            )
            sourceSelector.send(.visibleTabsChanged(visibleTabs))
            sourceSelector.send(.committedSelectionSynced(model.selectedSource?.id))
            sourceSelector.send(.sourcesChanged(model.capture.sources.map(\.id)))
            applyPreferredSourceTab()
            sourceSelector.send(.refreshRequested)
        }
        .onChange(of: model.selectedSource?.id) { _, sourceID in
            sourceSelector.send(.committedSelectionSynced(sourceID))
        }
        .onChange(of: model.capture.sources.map(\.id)) { _, sourceIDs in
            sourceSelector.send(.sourcesChanged(sourceIDs))
        }
        .onChange(of: model.preferredSourceSelectorKind) { _, _ in
            applyPreferredSourceTab()
        }
    }

    private func applyPreferredSourceTab() {
        let preferredKind = model.preferredSourceSelectorKind ?? model.selectedSource?.kind ?? .window
        sourceSelector.send(.tabSelected(SourceSelectorTab(sourceKind: preferredKind)))
    }
}

enum SourceSelectorTab: String, CaseIterable, Identifiable, Hashable {
    case screens
    case windows
    case area

    var id: String { rawValue }

    init(sourceKind: CaptureSourceKind) {
        switch sourceKind {
        case .display:
            self = .screens
        case .window:
            self = .windows
        case .area:
            self = .area
        }
    }

    var title: String {
        switch self {
        case .screens: "Screens"
        case .windows: "Windows"
        case .area: "Area"
        }
    }

    var symbolName: String {
        switch self {
        case .screens: "display"
        case .windows: "macwindow"
        case .area: "rectangle.dashed"
        }
    }
}

struct SourceSelectorCard: View {
    @Binding var sourceTab: SourceSelectorTab
    var visibleTabs: [SourceSelectorTab]
    var allSources: [CaptureSource]
    var selectedSourceID: String?
    var captureMode: CaptureMode
    var loadPhase: SourceSelectorLoadPhase = .loaded
    var onCancel: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    var onSelectSource: (CaptureSource) -> Void = { _ in }
    var onDrawArea: (() -> Void)? = nil

    private var sources: [CaptureSource] {
        switch sourceTab {
        case .screens:
            allSources.filter { $0.kind == .display }
        case .windows:
            allSources.filter { $0.kind == .window }
        case .area:
            allSources.filter { $0.kind == .area }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            VStack(spacing: 12) {
                HStack {
                    SourceTabs(sourceTab: $sourceTab, visibleTabs: visibleTabs)
                    Spacer()
                }

                ZStack {
                    if sourceTab == .area && sources.isEmpty {
                        SourceEmptyState(sourceTab: sourceTab, onDrawArea: onDrawArea)
                    } else if loadPhase == .loading && sources.isEmpty {
                        SourceLoadingState()
                    } else if case .failed(let message) = loadPhase, sources.isEmpty {
                        SourceLoadFailureState(message: message, onRetry: onRefresh)
                    } else if sources.isEmpty {
                        SourceEmptyState(sourceTab: sourceTab, onDrawArea: onDrawArea)
                    } else {
                        VStack(spacing: 8) {
                            if case .failed(let message) = loadPhase {
                                SourceLoadIssueBanner(message: message)
                            }
                            SourceGrid(
                                sources: sources,
                                sourceTab: sourceTab,
                                selectedSourceID: selectedSourceID,
                                onSelectSource: onSelectSource
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: headerIcon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Choose what to capture")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(selectorDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                StudioButton(hitTarget: .rounded(6), help: loadPhase == .loading ? "Refreshing Sources" : "Refresh Sources") {
                    onRefresh?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .foregroundStyle(Theme.fgMuted)
                .disabled(onRefresh == nil || loadPhase == .loading)

                if let onCancel {
                    StudioButton(hitTarget: .rounded(6), help: "Cancel", action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                    }
                    .foregroundStyle(Theme.fgMuted)
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private var headerIcon: String {
        captureMode == .screenshot ? "camera.viewfinder" : "record.circle"
    }

    private var selectorDescription: String {
        if captureMode == .screenshot {
            "Pick a screen, app window, or drawn area for this screenshot."
        } else {
            "Pick a screen, app window, or drawn area for the next recording."
        }
    }
}

struct SourceTabs: View {
    @Binding var sourceTab: SourceSelectorTab
    var visibleTabs: [SourceSelectorTab]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                let isSelected = sourceTab == tab
                Button {
                    withAnimation(Theme.springFast) {
                        sourceTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .foregroundStyle(isSelected ? Color.white : Theme.fgMuted)
                    .background(
                        isSelected ? Color.white.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SourceLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading current screens and windows…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SourceLoadFailureState: View {
    var message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(Theme.statusWarning)
            Text("Sources Unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.fgMuted)
                .multilineTextAlignment(.center)
            if let onRetry {
                StudioButton(hitTarget: .rectangle, action: onRetry) {
                    Text("Try Again")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Theme.accent, in: Rectangle())
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SourceLoadIssueBanner: View {
    var message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.statusWarning)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.statusWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                .stroke(Theme.statusWarning.opacity(0.3), lineWidth: 1)
        }
    }
}

struct SourceGrid: View {
    var sources: [CaptureSource]
    var sourceTab: SourceSelectorTab
    var selectedSourceID: String?
    var onSelectSource: (CaptureSource) -> Void

    private var columns: [GridItem] {
        let count = sourceTab == .windows ? 3 : min(max(sources.count, 1), 2)
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        if sourceTab == .screens && sources.count == 1, let singleSource = sources.first {
            singleScreenLayout(singleSource)
        } else if sourceTab == .windows {
            ScrollView(.vertical, showsIndicators: true) {
                grid
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
        } else {
            grid
                .padding(.horizontal, 2)
                .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func singleScreenLayout(_ source: CaptureSource) -> some View {
        VStack {
            Spacer(minLength: 0)
            SourceTile(
                source: source,
                isSelected: selectedSourceID == source.id,
                isCompact: false
            ) {
                onSelectSource(source)
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(sources) { source in
                SourceTile(
                    source: source,
                    isSelected: selectedSourceID == source.id,
                    isCompact: sourceTab == .windows
                ) {
                    onSelectSource(source)
                }
            }
        }
    }
}

struct SourceTile: View {
    var source: CaptureSource
    var isSelected: Bool
    var isCompact: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                SourceThumbnailPreview(
                    source: source,
                    isSelected: isSelected,
                    isHovering: isHovering,
                    isCompact: isCompact
                )

                labels
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.name), \(source.subtitle)")
        .accessibilityValue(isSelected ? "Current source" : "")
        .onHover { hovering in
            withAnimation(Theme.springFast) {
                isHovering = hovering
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(source.name)
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : (isHovering ? Color.white : Theme.fg))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            Text(source.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Theme.fgMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }
}

struct SourceThumbnailPreview: View {
    var source: CaptureSource
    var isSelected: Bool
    var isHovering: Bool
    var isCompact: Bool

    private var aspectRatio: CGFloat {
        source.kind == .window ? 1.6 : 16.0 / 9.0
    }

    var body: some View {
        ZStack {
            if let thumbnail = source.thumbnailData,
               let image = NSImage(data: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            } else {
                thumbnailPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .foregroundStyle(.white)
                            .shadow(color: Theme.accent.opacity(0.5), radius: 4)
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent : (isHovering ? Theme.borderStrong : Theme.borderSubtle),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .shadow(color: isSelected ? Theme.accent.opacity(0.3) : (isHovering ? Color.black.opacity(0.3) : Color.clear), radius: isSelected ? 8 : 4, y: 2)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Theme.overlay
            Image(systemName: source.kind == .window ? "macwindow" : source.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: isCompact ? 18 : 24, weight: .medium))
                .foregroundStyle(Theme.fgSubtle)
        }
    }
}

struct SourceEmptyState: View {
    var sourceTab: SourceSelectorTab
    var onDrawArea: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: sourceTab.symbolName)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Theme.accent)

            VStack(spacing: 4) {
                Text(sourceTab == .area ? "Draw a capture area" : "No sources available")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text(sourceTab == .area ? "Select the part of the screen you want to capture." : "Try a different tab or make sure the window is open.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.fgMuted)
            }

            if sourceTab == .area {
                StudioButton(hitTarget: .rectangle) {
                    onDrawArea?()
                } label: {
                    Label("Draw Selection", systemImage: "rectangle.dashed")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(height: Theme.btnHeightMd)
                        .padding(.horizontal, 16)
                        .background(Theme.accent, in: Rectangle())
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
