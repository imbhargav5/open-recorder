import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct CaptureStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sourceSelector = SourceSelectorDriver(sourceTab: .screens)

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        ZStack {
            Color.studioBackground

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
                        onDrawArea: {
                            model.requestInteractiveAreaSelection()
                        }
                    )
                        .frame(maxWidth: 860)
                    CaptureHUD(options: model.captureOptions, sourceTab: sourceSelector.sourceTabBinding)
                        .padding(.bottom, 12)
                }
                .padding(16)
                .background(Color.studioMutedBackground)
                .onAppear {
                    sourceSelector.configure(refreshSources: {
                        model.reloadSourcesForPreview()
                    })
                    sourceSelector.state.visibleTabs = visibleTabs
                    model.reloadSourcesForPreview()
                }
                .onChange(of: model.preferredSourceSelectorKind) { _, kind in
                    sourceSelector.send(.preferredSourceKindSynced(kind))
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
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                }
        }
    }
}

struct SourceTypeButton: View {
    var sourceType: CaptureSourceType
    var action: () -> Void

    var body: some View {
        StudioButton(hitTarget: .capsule, help: sourceType.title, action: action) {
            Label(sourceType.title, systemImage: sourceType.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 94)
                .frame(height: 38)
                .padding(.horizontal, 12)
                .foregroundStyle(Color.white.opacity(0.76))
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
    }
}
