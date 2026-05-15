import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ScreenSelectionOverlayChrome {
    static let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle
    ]
}

@MainActor
protocol ScreenSelectionPresenting: AnyObject {
    func present(
        displaySources: [CaptureSource],
        onSelect: @escaping (CaptureSource) -> Void,
        onCancel: @escaping () -> Void
    )
    func dismiss()
}

@MainActor
final class ScreenSelectionOverlayController: ScreenSelectionPresenting {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onCancel: (() -> Void)?

    func present(
        displaySources: [CaptureSource],
        onSelect: @escaping (CaptureSource) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        guard !displaySources.isEmpty else {
            onCancel()
            return
        }

        self.onCancel = onCancel
        installKeyMonitor()

        for (screenIndex, screen) in NSScreen.screens.enumerated() {
            guard let source = displaySource(for: screen, index: screenIndex, in: displaySources) else {
                continue
            }
            let window = ScreenSelectionOverlayPanel(
                contentRect: screen.frame,
                styleMask: ScreenSelectionOverlayChrome.styleMask,
                backing: .buffered,
                defer: false
            )
            window.onCancel = onCancel
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.worksWhenModal = true
            window.becomesKeyOnlyIfNeeded = false
            window.level = ScreenSelectionOverlayChrome.level
            window.collectionBehavior = ScreenSelectionOverlayChrome.collectionBehavior
            window.isMovableByWindowBackground = false
            window.contentView = NSHostingView(rootView: ScreenSelectionOverlayView(
                sourceName: source.name,
                onChoose: { onSelect(source) },
                onCancel: onCancel
            ))
            windows.append(window)
            window.orderFrontRegardless()
        }

        guard !windows.isEmpty else {
            dismiss()
            onCancel()
            return
        }

        windows.last?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        keyMonitor = nil
        globalKeyMonitor = nil
        onCancel = nil
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.isEscapeKey {
                self.onCancel?()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.isEscapeKey else { return }
            Task { @MainActor [weak self] in
                self?.onCancel?()
            }
        }
    }

    private func displaySource(
        for screen: NSScreen,
        index: Int,
        in displaySources: [CaptureSource]
    ) -> CaptureSource? {
        if let displayID = screen.displayID,
           let source = displaySources.first(where: { $0.displayID == displayID }) {
            return source
        }

        if let source = displaySources.first(where: { $0.displayIndex == index + 1 }) {
            return source
        }

        guard displaySources.indices.contains(index) else {
            return nil
        }
        return displaySources[index]
    }
}

private final class ScreenSelectionOverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.isEscapeKey {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private extension NSEvent {
    var isEscapeKey: Bool {
        keyCode == UInt16(kVK_Escape) || charactersIgnoringModifiers == "\u{1B}"
    }
}

private struct ScreenSelectionOverlayView: View {
    var sourceName: String
    var onChoose: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            overlayColor
                .ignoresSafeArea()
                .rectangularHitTarget()
                .onTapGesture(perform: onCancel)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(overlayColor.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.74), lineWidth: 3)
                }
                .padding(18)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                Image(systemName: "display")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text(sourceName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.92))

                Button(action: onChoose) {
                    Label("Choose Screen", systemImage: "cursorarrow")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(Color(red: 0.08, green: 0.28, blue: 0.74))
                        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .capsuleHitTarget()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
            }
        }
        .focusable()
        .onExitCommand(perform: onCancel)
    }

    private var overlayColor: Color {
        Color(red: 0.12, green: 0.42, blue: 1.0).opacity(0.32)
    }
}

private extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
