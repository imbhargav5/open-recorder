import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct CaptureStudioView: View {
    @EnvironmentObject private var model: AppModel
    private var sourceSelector: SourceSelectorDriver {
        model.appShell.inlineSourceSelector
    }

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        ZStack {
            Theme.appBg

            switch model.hudState.phase {
            case .idle, .choosingMode:
                VStack {
                    Spacer()
                    CaptureChoiceHUD()
                        .padding(.bottom, 56)
                }
            case .choosingSourceType(let mode), .screenSelecting(let mode):
                VStack {
                    Spacer()
                    SourceTypeChoiceHUD(mode: mode)
                        .padding(.bottom, 56)
                }
            default:
                VStack(spacing: 18) {
                    Spacer(minLength: 10)
                    SourceSelectorCard(
                        sourceTab: sourceSelector.sourceTabBinding,
                        visibleTabs: sourceSelector.state.visibleTabs,
                        allSources: model.capture.sources,
                        selectedSourceID: model.selectedSource?.id,
                        captureMode: model.captureMode,
                        loadPhase: sourceSelector.state.loadPhase,
                        onRefresh: {
                            sourceSelector.send(.refreshRequested)
                        },
                        onSelectSource: { source in
                            model.selectSource(source)
                        },
                        onDrawArea: {
                            model.requestInteractiveAreaSelection()
                        }
                    )
                        .frame(maxWidth: 860)
                    CaptureHUD(options: model.captureOptions, sourceTab: sourceSelector.sourceTabBinding)
                        .padding(.bottom, 12)
                }
                .padding(16)
                .background(Theme.appBgMuted)
                .onAppear {
                    sourceSelector.configure(refreshSources: {
                        await model.refreshSources(requestScreenRecordingPermission: true)
                        return SourceSelectorRefreshResult(
                            sourceIDs: model.capture.sources.map(\.id),
                            errorMessage: model.capture.sourceCatalogState.issueMessage
                        )
                    })
                    sourceSelector.send(.visibleTabsChanged(visibleTabs))
                    sourceSelector.send(.committedSelectionSynced(model.selectedSource?.id))
                    sourceSelector.send(.sourcesChanged(model.capture.sources.map(\.id)))
                    sourceSelector.send(.refreshRequested)
                }
                .onChange(of: model.preferredSourceSelectorKind) { _, kind in
                    sourceSelector.send(.preferredSourceKindSynced(kind))
                }
                .onChange(of: model.capture.sources.map(\.id)) { _, sourceIDs in
                    sourceSelector.send(.sourcesChanged(sourceIDs))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CaptureChoiceHUD: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HUDSurface {
            HStack(spacing: 12) {
                DragHandle()

                CaptureModeButton(
                    title: "Screenshot",
                    symbolName: "camera",
                    isActive: false
                ) {
                    model.beginCapture(.screenshot)
                }

                CaptureModeButton(
                    title: "Record Video",
                    symbolName: "video",
                    isActive: false
                ) {
                    model.beginCapture(.recording)
                }
            }
        }
    }
}

struct SourceTypeChoiceHUD: View {
    @EnvironmentObject private var model: AppModel
    var mode: CaptureMode

    var body: some View {
        HUDSurface {
            HStack(spacing: 8) {
                DragHandle()
                backButton
                HUDDivider()

                FlowLabel(
                    tone: .blue,
                    label: mode == .screenshot ? "Screenshot" : "Recording",
                    value: "Source"
                )

                ForEach(CaptureSourceType.allCases) { sourceType in
                    SourceTypeButton(sourceType: sourceType) {
                        model.chooseSourceType(sourceType)
                    }
                }
            }
        }
    }

    private var backButton: some View {
        StudioButton(hitTarget: .circle, help: "Back") {
            model.cancelCapture()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 38, height: 38)
                .foregroundStyle(Color.white.opacity(0.70))
                .background(Theme.overlay, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Theme.border, lineWidth: 1)
                }
        }
    }
}

struct SourceTypeButton: View {
    var sourceType: CaptureSourceType
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .capsule, help: sourceType.title, action: action) {
            HStack(spacing: 8) {
                Image(systemName: sourceType.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.055), in: Circle())
                Text(sourceType.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 104)
            .frame(height: 40)
            .padding(.horizontal, 13)
            .foregroundStyle(Color.white.opacity(0.78))
            .background(Theme.overlayStrong, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Theme.borderStrong.opacity(0.68), lineWidth: 1)
            }
        }
    }
}
