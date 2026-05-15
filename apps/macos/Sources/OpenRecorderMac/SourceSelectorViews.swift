import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct SourceSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var sourceTab: SourceSelectorTab = .screens
    @State private var preferredHeight: CGFloat = SourceSelectorWindowMetrics.compactHeight

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            SourceSelectorCard(
                sourceTab: $sourceTab,
                visibleTabs: visibleTabs,
                onCancel: {
                    model.cancelCapture()
                },
                onShare: {
                    if let selectedSource = model.selectedSource {
                        model.selectSource(selectedSource)
                    }
                    dismissWindow(id: "source-selector")
                },
                onDrawArea: {
                    model.selectInteractiveAreaSource()
                    dismissWindow(id: "source-selector")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        model.requestInteractiveAreaSelection()
                    }
                }
            )
            .padding(16)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SourceSelectorCardHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
        }
        .background(SourceSelectorWindowSizer(size: CGSize(width: SourceSelectorWindowMetrics.width, height: preferredHeight)))
        .background(Color.studioBackground.ignoresSafeArea())
        .onPreferenceChange(SourceSelectorCardHeightPreferenceKey.self) { cardHeight in
            let nextHeight = ceil(cardHeight + (SourceSelectorWindowMetrics.outerPadding * 2))
            guard abs(preferredHeight - nextHeight) > 0.5 else { return }
            preferredHeight = nextHeight
        }
        .onAppear {
            applyPreferredSourceTab()
            model.reloadSourcesForPreview()
        }
        .onChange(of: model.preferredSourceSelectorKind) { _, _ in
            applyPreferredSourceTab()
        }
    }

    private func applyPreferredSourceTab() {
        sourceTab = SourceSelectorTab(
            sourceKind: model.preferredSourceSelectorKind ?? model.selectedSource?.kind ?? .display
        )
    }
}



enum SourceSelectorTab: String, CaseIterable, Identifiable {
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
    @EnvironmentObject private var model: AppModel
    @Binding var sourceTab: SourceSelectorTab
    var visibleTabs: [SourceSelectorTab]
    var onCancel: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var onDrawArea: (() -> Void)? = nil

    private var sources: [CaptureSource] {
        switch sourceTab {
        case .screens:
            model.capture.sources.filter { $0.kind == .display }
        case .windows:
            model.capture.sources.filter { $0.kind == .window }
        case .area:
            model.capture.sources.filter { $0.kind == .area }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose what to share")
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectorDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.capture.sources.filter { $0.kind != .area }.count) sources")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.studioBorder)
                    }
            }
            .padding(16)

            VStack(spacing: 14) {
                SourceTabs(sourceTab: $sourceTab, visibleTabs: visibleTabs)

                if sources.isEmpty {
                    SourceEmptyState(sourceTab: sourceTab, onDrawArea: onDrawArea)
                } else {
                    SourceGrid(sources: sources, sourceTab: sourceTab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack {
                StudioButton(hitTarget: .rounded(8)) {
                    onCancel?()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.secondary)

                StudioButton(hitTarget: .rounded(8)) {
                    model.reloadSourcesForPreview()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.secondary)

                Spacer()

                StudioButton(hitTarget: .rounded(8)) {
                    onShare?()
                } label: {
                    Text("Share Source")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(canShareSource ? Color.brand : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(canShareSource ? Color.white : Color.secondary)
                }
                .disabled(!canShareSource || onShare == nil)
            }
            .padding(16)
        }
        .background(Color.studioPanel.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioBorder)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 26, y: 18)
    }

    private var selectorDescription: String {
        if model.captureMode == .screenshot {
            "Pick a screen, app window, or drawn area for this screenshot."
        } else {
            "Pick a screen, app window, or drawn area for the next recording."
        }
    }

    private var canShareSource: Bool {
        guard let selectedSource = model.selectedSource else {
            return false
        }
        return sources.contains { $0.id == selectedSource.id }
    }
}

struct SourceTabs: View {
    @Binding var sourceTab: SourceSelectorTab
    var visibleTabs: [SourceSelectorTab]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs) { tab in
                StudioSegmentedTabButton(
                    title: tab.title,
                    symbolName: tab.symbolName,
                    isSelected: sourceTab == tab
                ) {
                    sourceTab = tab
                }
            }
        }
        .padding(4)
        .background(Color.studioControl, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct StudioSegmentedTabButton: View {
    var title: String
    var symbolName: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(7), action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background(isSelected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

struct SourceGrid: View {
    @EnvironmentObject private var model: AppModel
    var sources: [CaptureSource]
    var sourceTab: SourceSelectorTab

    private var columns: [GridItem] {
        let count = sourceTab == .windows ? 3 : min(max(sources.count, 1), 3)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        if sourceTab == .windows {
            ScrollView(.vertical) {
                grid
                    .padding(.trailing, 2)
            }
            .frame(maxHeight: 356)
            .scrollClipDisabled(false)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            grid
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(sources) { source in
                SourceTile(
                    source: source,
                    isSelected: model.selectedSource?.id == source.id,
                    isCompact: sourceTab == .windows
                ) {
                    model.selectSource(source)
                }
            }
        }
        .clipped()
    }
}

struct SourceTile: View {
    var source: CaptureSource
    var isSelected: Bool
    var isCompact: Bool
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .rounded(9), action: action) {
            if isCompact {
                squareContent
            } else {
                standardContent
            }
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceThumbnailPreview(
                source: source,
                isSelected: isSelected,
                isCompact: isCompact
            )
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)

            labels
        }
        .padding(8)
        .background(Color.studioCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.brand : Color.studioBorder, lineWidth: isSelected ? 2 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var squareContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            SourceThumbnailPreview(
                source: source,
                isSelected: isSelected,
                isCompact: isCompact
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            labels
        }
        .padding(4)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studioCard.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color.brand : Color.studioBorder, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(source.name)
                    .font(.system(size: isCompact ? 12 : 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            Text(source.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewAspectRatio: CGFloat {
        source.kind == .window ? 1.6 : 16.0 / 9.0
    }
}

struct SourceThumbnailPreview: View {
    var source: CaptureSource
    var isSelected: Bool
    var isCompact: Bool

    private var aspectRatio: CGFloat {
        source.kind == .window ? 1.6 : 16.0 / 9.0
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.045))

            if let thumbnail = source.thumbnailData,
               let image = NSImage(data: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
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
                            .frame(width: 18, height: 18)
                            .background(Color.brand, in: Circle())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Image(systemName: source.kind == .window ? "macwindow" : source.kind == .area ? "rectangle.dashed" : "display")
                .font(.system(size: isCompact ? 18 : 24, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

}

struct SourceEmptyState: View {
    var sourceTab: SourceSelectorTab
    var onDrawArea: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: sourceTab.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            Text(sourceTab == .area ? "Draw a capture area" : "No sources available")
                .font(.system(size: 15, weight: .semibold))
            Text(sourceTab == .area ? "Select the part of the screen you want to capture." : "Try a different tab or make sure the source is visible.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if sourceTab == .area {
                StudioButton(hitTarget: .rounded(8)) {
                    onDrawArea?()
                } label: {
                    Label("Draw Selection", systemImage: "rectangle.dashed")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color.brand, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.studioBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}
