import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

private typealias CGWindowInfoDictionary = [String: Any]

struct RecordingOverlayScreen: Equatable {
    var frame: CGRect
    var displayID: UInt32?
}

enum RecordingCountdownOverlayChrome {
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let collectionBehavior = CaptureOverlayWindowChrome.collectionBehavior
    static let level = CaptureOverlayWindowChrome.level
}

@MainActor
struct RecordingCountdownEventMonitorClient {
    var addLocalKeyDownMonitor: (@escaping (NSEvent) -> NSEvent?) -> Any?
    var addGlobalKeyDownMonitor: (@escaping (NSEvent) -> Void) -> Any?
    var removeMonitor: (Any) -> Void

    static let live = RecordingCountdownEventMonitorClient(
        addLocalKeyDownMonitor: { handler in
            NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
        },
        addGlobalKeyDownMonitor: { handler in
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        },
        removeMonitor: { monitor in
            NSEvent.removeMonitor(monitor)
        }
    )
}

@MainActor
final class RecordingCountdownEscapeMonitor {
    private let eventMonitorClient: RecordingCountdownEventMonitorClient
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onEscape: (() -> Void)?

    init(eventMonitorClient: RecordingCountdownEventMonitorClient = .live) {
        self.eventMonitorClient = eventMonitorClient
    }

    func install(onEscape: @escaping () -> Void) {
        remove()
        self.onEscape = onEscape

        localKeyMonitor = eventMonitorClient.addLocalKeyDownMonitor { [weak self] event in
            guard Self.isEscapeKey(event) else { return event }
            self?.handleEscape()
            return nil
        }
        globalKeyMonitor = eventMonitorClient.addGlobalKeyDownMonitor { [weak self] event in
            guard Self.isEscapeKey(event) else { return }
            Task { @MainActor [weak self] in
                self?.handleEscape()
            }
        }
    }

    func remove() {
        if let localKeyMonitor {
            eventMonitorClient.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor {
            eventMonitorClient.removeMonitor(globalKeyMonitor)
        }
        localKeyMonitor = nil
        globalKeyMonitor = nil
        onEscape = nil
    }

    private func handleEscape() {
        guard let onEscape else { return }
        remove()
        onEscape()
    }

    private static func isEscapeKey(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_Escape) || event.charactersIgnoringModifiers == "\u{1B}"
    }
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
            if let displayIndex = source.displayIndex,
               displayIndex > 0, displayIndex <= screens.count {
                return screens[displayIndex - 1].frame
            }
            return fallback
        case .area:
            guard let area = source.area else { return fallback }
            return CGRect(x: CGFloat(area.x), y: CGFloat(area.y), width: max(CGFloat(area.width), 1), height: max(CGFloat(area.height), 1))
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
        if let displayIndex = source.displayIndex,
           displayIndex > 0, displayIndex <= screens.count {
            return screens[displayIndex - 1].frame
        }
        return screens.first?.frame ?? CGRect(x: 0, y: 0, width: 900, height: 600)
    }

    @MainActor
    private static func currentWindowFrame(windowID: UInt32) -> CGRect? {
        let options = CGWindowListOption.optionIncludingWindow
        guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(windowID)) as? [CGWindowInfoDictionary],
              let window = windows.first,
              let bounds = window[kCGWindowBounds as String] as? CGWindowInfoDictionary else {
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
    private var window: RecordingCountdownOverlayPanel?
    private var state: RecordingCountdownState?
    private let escapeMonitor: RecordingCountdownEscapeMonitor
    var onCancel: () -> Void = {}

    init(eventMonitorClient: RecordingCountdownEventMonitorClient = .live) {
        escapeMonitor = RecordingCountdownEscapeMonitor(eventMonitorClient: eventMonitorClient)
    }

    func run(for source: CaptureSource) async throws {
        let state = RecordingCountdownState(sourceName: source.name)
        showWindow(for: source, state: state)
        escapeMonitor.install { [weak self] in
            self?.onCancel()
        }

        defer {
            dismiss()
        }

        for value in [3, 2, 1] {
            state.count = value
            RecordingSoundEffects.shared.playCountdownTick(for: value)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        RecordingSoundEffects.shared.playRecordingStarted()
    }

    func dismiss() {
        escapeMonitor.remove()
        window?.close()
        window = nil
        state = nil
    }

    private func showWindow(for source: CaptureSource, state: RecordingCountdownState) {
        dismiss()
        self.state = state
        let frame = RecordingCountdownTargetResolver.currentFrame(for: source)
        let window = RecordingCountdownOverlayPanel(
            contentRect: frame,
            styleMask: RecordingCountdownOverlayChrome.styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isFloatingPanel = true
        window.level = RecordingCountdownOverlayChrome.level
        window.collectionBehavior = RecordingCountdownOverlayChrome.collectionBehavior
        window.contentView = NSHostingView(rootView: RecordingCountdownOverlay(state: state))
        self.window = window
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }
}

final class RecordingCountdownOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
            Color.black.opacity(0.38)
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.80), Color.white.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .padding(16)

            VStack(spacing: 14) {
                Text("\(state.count)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.60), radius: 24, y: 8)
                    .id(state.count)
                    .transition(.scale(scale: 1.25).combined(with: .opacity))

                Text("Recording \(state.sourceName)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.40), radius: 8, y: 4)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: state.count)
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        max(width, 0) * max(height, 0)
    }
}
