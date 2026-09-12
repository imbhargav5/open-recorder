import AppKit
import CoreImage
import SwiftUI

struct SceneScreenshotPreview: View {
    var image: NSImage?
    var state: ScreenshotEditorState
    var time: Double
    @State private var rendered: CGImage?
    @State private var renderer = SceneRenderer()

    private struct RenderKey: Equatable {
        var state: ScreenshotEditorState
        var time: Double
        var image: ObjectIdentifier?
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let rendered {
                    Image(decorative: rendered, scale: 1).resizable().interpolation(.high).scaledToFit()
                } else if image == nil { EmptyEditorState() }
                else { Text("Scene preview unavailable. Reset Scene to use the standard preview.").font(.callout).foregroundStyle(Theme.fgMuted).padding(20) }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(32)
        .task(id: RenderKey(state: state, time: time, image: image.map(ObjectIdentifier.init))) {
            guard let image else { rendered = nil; return }
            var configuration = ScreenshotExportConfiguration(screenshotState: state)
            configuration.sceneTime = time
            rendered = ScreenshotExportRenderer(configuration: configuration).renderImage(from: image, maxDimension: 1600, renderer: renderer)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
