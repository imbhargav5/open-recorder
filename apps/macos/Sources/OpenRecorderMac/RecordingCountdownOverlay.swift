import AppKit
import CoreGraphics
import SwiftUI

struct RecordingOverlayScreen: Equatable {
    var frame: CGRect
    var displayID: UInt32?
}

enum RecordingCountdownTargetResolver {
    static func frame(
        for source: CaptureSource,
        screens: [RecordingOverlayScreen],
        windowFrame: CGRect? = nil
    ) -> CGRect {
        let fallback = fallbackFrame(for: source, screens: screens)

        switch source.kind {
        case .display:
            if let displayID = source.displayID,
               let screen = screens.first(where: { $0.displayID == displayID }) {
                return screen.frame
            }
            return fallback
        case .area:
            guard let area = source.area else { return fallback }
            return CGRect(x: area.x, y: area.y, width: max(area.width, 1), height: max(area.height, 1))
        case .window:
            guard let windowFrame, windowFrame.width > 1, windowFrame.height > 1 else {
                return fallback
            }
            return windowFrame
        }
    }

    @MainActor
    static func currentFrame(for source: CaptureSource) -> CGRect {
        frame(
            for: source,
            screens: NSScreen.screens.map {
                RecordingOverlayScreen(
                    frame: $0.frame,
                    displayID: ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                )
            },
            windowFrame: source.windowID.flatMap(currentWindowFrame)
        )
    }

    private static func fallbackFrame(for source: CaptureSource, screens: [RecordingOverlayScreen]) -> CGRect {
        if let displayID = source.displayID,
           let screen = screens.first(where: { $0.displayID == displayID }) {
            return screen.frame
        }
        return screens.first?.frame ?? CGRect(x: 0, y: 0, width: 900, height: 600)
    }

    @MainActor
    private static func currentWindowFrame(windowID: UInt32) -> CGRect? {
        let options = CGWindowListOption.optionIncludingWindow
        guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(windowID)) as? [[String: Any]],
              let window = windows.first,
              let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }

        let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
        let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
        let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
        guard width > 1, height > 1 else { return nil }

        let cgFrame = CGRect(x: x, y: y, width: width, height: height)
        guard let screen = NSScreen.screens.max(by: {
            $0.frame.intersection(cgFrame).area < $1.frame.intersection(cgFrame).area
        }) ?? NSScreen.main else {
            return cgFrame
        }

        return CGRect(
            x: cgFrame.minX,
            y: screen.frame.maxY - cgFrame.maxY,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }
}

@MainActor
final class RecordingCountdownOverlayController {
    private var window: NSWindow?
    private var state: RecordingCountdownState?

    func run(for source: CaptureSource) async throws {
        let state = RecordingCountdownState(sourceName: source.name)
        self.state = state
        showWindow(for: source, state: state)

        defer {
            dismiss()
        }

        for value in [3, 2, 1] {
            state.count = value
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func dismiss() {
        window?.close()
        window = nil
        state = nil
    }

    private func showWindow(for source: CaptureSource, state: RecordingCountdownState) {
        dismiss()
        let frame = RecordingCountdownTargetResolver.currentFrame(for: source)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: RecordingCountdownOverlay(state: state))
        self.window = window
        window.orderFrontRegardless()
    }
}

@MainActor
private final class RecordingCountdownState: ObservableObject {
    @Published var count = 3
    let sourceName: String

    init(sourceName: String) {
        self.sourceName = sourceName
    }
}

private struct RecordingCountdownOverlay: View {
    @ObservedObject var state: RecordingCountdownState

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.70), lineWidth: 4)
                .padding(18)

            VStack(spacing: 12) {
                Text("\(state.count)")
                    .font(.system(size: 132, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.55), radius: 18, y: 8)

                Text("Recording \(state.sourceName)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.36), in: Capsule())
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        max(width, 0) * max(height, 0)
    }
}
