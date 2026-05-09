import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct CaptureStudioView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sourceTab: SourceSelectorTab = .screens

    private var visibleTabs: [SourceSelectorTab] {
        SourceSelectorTab.allCases
    }

    var body: some View {
        ZStack {
            Color.studioBackground

            if model.captureFlow == .choice {
                VStack {
                    Spacer()
                    CaptureChoiceHUD(sourceTab: $sourceTab)
                        .padding(.bottom, 56)
                }
            } else {
                VStack(spacing: 18) {
                    Spacer(minLength: 10)
                    SourceSelectorCard(
                        sourceTab: $sourceTab,
                        visibleTabs: visibleTabs,
                        onDrawArea: {
                            model.requestInteractiveAreaSelection()
                        }
                    )
                        .frame(maxWidth: 860)
                    CaptureHUD(sourceTab: $sourceTab)
                        .padding(.bottom, 12)
                }
                .padding(16)
                .background(Color.studioMutedBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CaptureChoiceHUD: View {
    @EnvironmentObject private var model: AppModel
    @Binding var sourceTab: SourceSelectorTab

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
                    sourceTab = .screens
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

