import AppKit
import SwiftUI

/// A floating, app-owned prompt window. ScreenCaptureKit excludes Open Recorder
/// windows from display and area captures, so the speaker can read this without
/// putting the script into the resulting movie.
@MainActor
final class TeleprompterOverlayController {
    private var window: TeleprompterOverlayPanel?
    private var state: TeleprompterState?

    var isVisible: Bool { window?.isVisible == true }

    func show(script: NSAttributedString, for source: CaptureSource) {
        guard !script.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let state {
            state.script = script
            state.resume()
            window?.orderFrontRegardless()
            return
        }

        let state = TeleprompterState(script: script)
        let frame = Self.frame(for: source)
        let panel = TeleprompterOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: TeleprompterOverlay(state: state, onClose: { [weak self] in
            self?.hide()
        }))
        self.window = panel
        self.state = state
        panel.orderFrontRegardless()
    }

    /// Used by the editor voiceover workflow, where there is no capture source
    /// but the reader still needs a prompt above the playback window.
    func show(script: NSAttributedString) {
        guard !script.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let state {
            state.script = script
            state.resume()
            window?.orderFrontRegardless()
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let target = screen?.visibleFrame ?? .zero
        let width = min(max(target.width * 0.52, 420), 760)
        let height = min(max(target.height * 0.38, 300), 540)
        let frame = CGRect(x: target.midX - width / 2, y: target.maxY - height - 58, width: width, height: height)
        let state = TeleprompterState(script: script)
        let panel = TeleprompterOverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: TeleprompterOverlay(state: state, onClose: { [weak self] in self?.hide() }))
        self.window = panel
        self.state = state
        panel.orderFrontRegardless()
    }

    func toggle(script: NSAttributedString, for source: CaptureSource) {
        if isVisible { hide() } else { show(script: script, for: source) }
    }

    func hide() {
        window?.orderOut(nil)
        state?.pause()
    }

    func dismiss() {
        window?.close()
        window = nil
        state = nil
    }

    private static func frame(for source: CaptureSource) -> CGRect {
        let target = RecordingCountdownTargetResolver.currentFrame(for: source)
        let width = min(max(target.width * 0.52, 420), 760)
        let height = min(max(target.height * 0.38, 300), 540)
        return CGRect(
            x: target.midX - width / 2,
            y: target.maxY - height - max(42, target.height * 0.07),
            width: width,
            height: height
        )
    }
}

private final class TeleprompterOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class TeleprompterState: ObservableObject {
    @Published var script: NSAttributedString
    @Published var isPaused = false
    @Published var speed: Double = 28

    private var accumulatedTime: TimeInterval = 0
    private var resumedAt = Date()

    init(script: NSAttributedString) { self.script = script }

    func elapsed(at date: Date) -> TimeInterval {
        accumulatedTime + (isPaused ? 0 : date.timeIntervalSince(resumedAt))
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func pause() {
        guard !isPaused else { return }
        accumulatedTime += Date().timeIntervalSince(resumedAt)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        resumedAt = Date()
        isPaused = false
    }

    func reset() {
        accumulatedTime = 0
        resumedAt = Date()
    }
}

private struct TeleprompterOverlay: View {
    @ObservedObject var state: TeleprompterState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let offset = max(0, state.elapsed(at: context.date) * state.speed - proxy.size.height * 0.28)
                    Text(AttributedString(state.script))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .lineSpacing(8)
                        .frame(width: proxy.size.width - 44, alignment: .top)
                        .offset(y: -offset)
                        .animation(.linear(duration: 0.05), value: offset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.10), .init(color: .white, location: 0.82), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .padding(.top, 20)

            HStack(spacing: 10) {
                Button(state.isPaused ? "Resume" : "Pause") { state.togglePause() }
                Button("Reset") { state.reset() }
                Spacer()
                Button { state.speed = max(12, state.speed - 4) } label: { Image(systemName: "tortoise") }
                    .accessibilityLabel("Slow teleprompter")
                Text("\(Int(state.speed))")
                    .monospacedDigit().font(.caption).frame(minWidth: 24)
                Button { state.speed = min(80, state.speed + 4) } label: { Image(systemName: "hare") }
                    .accessibilityLabel("Speed up teleprompter")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("Hide teleprompter")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(14)
            .background(.black.opacity(0.46))
        }
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1) }
    }
}
