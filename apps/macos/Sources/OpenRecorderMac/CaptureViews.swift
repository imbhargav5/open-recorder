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
                CaptureHUD(options: model.captureOptions)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
