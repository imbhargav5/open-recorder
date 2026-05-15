import AppKit
import Carbon.HIToolbox
import SwiftUI

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
            let window = ScreenSelectionOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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

        NSApp.activate(ignoringOtherApps: true)
        windows.last?.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        onCancel = nil
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) || event.charactersIgnoringModifiers == "\u{1B}" {
                self.onCancel?()
                return nil
            }
            return event
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

private final class ScreenSelectionOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
                    Label("Choose Screen", systemImage: "checkmark.circle.fill")
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
