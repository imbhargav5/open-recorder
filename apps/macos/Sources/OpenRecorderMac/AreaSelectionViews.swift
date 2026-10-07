import AVFoundation
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum AreaSelectionOverlayChrome {
    static let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]
}

@MainActor
protocol AreaSelectionPresenting: AnyObject {
    var adjustsSelectionBeforeCapture: Bool { get set }
    func present(
        mode: CaptureMode,
        onSelect: @escaping (CaptureArea) -> Void,
        onCancel: @escaping () -> Void
    )
    func focus()
    func dismiss()
}

extension AreaSelectionPresenting {
    var adjustsSelectionBeforeCapture: Bool {
        get { false }
        set { }
    }
}

@MainActor
final class AreaSelectionOverlayController: AreaSelectionPresenting {
    var adjustsSelectionBeforeCapture = false
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var onSelect: ((CaptureArea) -> Void)?
    private var onCancel: (() -> Void)?
    private var mode: CaptureMode = .recording
    private var presentationGeneration = 0

#if DEBUG || OPEN_RECORDER_TESTING
    var presentedWindowCountForTesting: Int { windows.count }
    var presentedWindowsForTesting: [NSWindow] { windows }
#endif

    func present(
        mode: CaptureMode,
        onSelect: @escaping (CaptureArea) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()
        self.mode = mode
        self.onSelect = onSelect
        self.onCancel = onCancel

        installKeyMonitor()
        installSpaceAndScreenObservers(generation: presentationGeneration)
        rebuildWindows()
    }

    func focus() {
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        if let mainScreenWindow = windows.first(where: { $0.screen == NSScreen.main }) ?? windows.first {
            mainScreenWindow.makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        presentationGeneration += 1
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        keyMonitor = nil
        globalKeyMonitor = nil
        spaceObserver = nil
        screenObserver = nil
        onSelect = nil
        onCancel = nil
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()

        for screen in NSScreen.screens {
            let window = AreaSelectionOverlayPanel(
                contentRect: screen.frame,
                styleMask: AreaSelectionOverlayChrome.styleMask,
                backing: .buffered,
                defer: false
            )
            window.onCancel = { [weak self] in
                self?.handleCancel()
            }
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.worksWhenModal = true
            window.becomesKeyOnlyIfNeeded = false
            window.level = AreaSelectionOverlayChrome.level
            window.collectionBehavior = AreaSelectionOverlayChrome.collectionBehavior
            window.isMovableByWindowBackground = false
            window.acceptsMouseMovedEvents = true
            window.contentView = AreaSelectionHostingView(rootView: AreaSelectionScreenOverlayView(
                screen: screen,
                mode: mode,
                adjustsSelectionBeforeCapture: adjustsSelectionBeforeCapture,
                onSelect: { [weak self] area in
                    self?.handleSelect(area)
                },
                onCancel: { [weak self] in
                    self?.handleCancel()
                }
            ))
            windows.append(window)
            window.orderFrontRegardless()
        }

        focus()
    }

    private func handleSelect(_ area: CaptureArea) {
        let callback = onSelect
        dismiss()
        callback?(area)
    }

    private func handleCancel() {
        let callback = onCancel
        dismiss()
        callback?()
    }

    private func installSpaceAndScreenObservers(generation: Int) {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.presentationGeneration == generation else { return }
                self?.windows.forEach { $0.orderFrontRegardless() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.presentationGeneration == generation else { return }
                self?.rebuildWindows()
            }
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.isEscapeKey {
                self.handleCancel()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.isEscapeKey else { return }
            Task { @MainActor [weak self] in
                self?.handleCancel()
            }
        }
    }
}

final class AreaSelectionHostingView: NSHostingView<AreaSelectionScreenOverlayView> {
    // The activating mouse-down must also begin selection, including on non-key displays.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AreaSelectionOverlayPanel: NSPanel {
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

struct AreaSelectionScreenOverlayView: View {
    var screen: NSScreen
    var mode: CaptureMode
    var adjustsSelectionBeforeCapture = false
    var onSelect: (CaptureArea) -> Void
    var onCancel: () -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var isFinishingSelection = false
    @State private var adjustedRect: CGRect?
    @State private var adjustmentOrigin: CGRect?
    @FocusState private var selectionHasFocus: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(isFinishingSelection ? 0 : 0.28)
                    .ignoresSafeArea()

                if !isFinishingSelection, let selectionRect {
                    Rectangle()
                        .fill(Color.clear)
                        .overlay {
                            Rectangle()
                                .strokeBorder(Color.white, lineWidth: 2)
                                .shadow(color: Color.black.opacity(0.4), radius: 2)
                        }
                        .background(Theme.border.opacity(0.12))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                        .gesture(moveGesture(in: proxy.size))
                        .accessibilityLabel("Selected capture area")
                        .accessibilityValue("\(Int(selectionRect.width)) by \(Int(selectionRect.height)) pixels")

                    dimensionBadge(for: selectionRect)
                    if adjustedRect != nil {
                        ForEach(AreaSelectionResizeCorner.allCases) { corner in
                            Circle().fill(.white).frame(width: 12, height: 12)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                                .position(corner.point(in: selectionRect))
                                .highPriorityGesture(resizeGesture(corner: corner, in: proxy.size))
                                .accessibilityLabel("Resize \(corner.title) corner")
                                .accessibilityValue("\(Int(selectionRect.width)) by \(Int(selectionRect.height)) pixels")
                                .accessibilityAdjustableAction { direction in
                                    let delta: CGFloat = direction == .increment ? 1 : -1
                                    let left = corner == .topLeft || corner == .bottomLeft
                                    let top = corner == .topLeft || corner == .topRight
                                    adjustedRect = AreaSelectionGeometry.resized(selectionRect, corner: corner, translation: CGSize(width: left ? -delta : delta, height: top ? -delta : delta), bounds: proxy.size)
                                }
                        }
                        VStack(spacing: 8) {
                            Text("Drag the area to move it or its handles to resize. Arrow keys move; Shift moves 10 px.")
                                .font(.caption)
                            HStack {
                                Button("Redraw") { adjustedRect = nil; dragStart = nil; dragCurrent = nil }
                                Button("Cancel", action: onCancel)
                                Button(mode == .screenshot ? "Capture" : "Use area") { finishSelection(selectionRect) }
                                    .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 32)
                    }
                }

                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 26, weight: .medium))
                    Text("Drag to select an area")
                        .font(.system(size: 18, weight: .semibold))
                    Text(adjustsSelectionBeforeCapture
                        ? "Release to adjust the area, then press Return. Esc cancels."
                        : (mode == .recording
                            ? "Release to set the area, review inputs, then press Record. Esc cancels."
                            : "Release to capture this area. Press Esc to cancel."))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
                        .stroke(Theme.borderStrong, lineWidth: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(selectionRect == nil && !isFinishingSelection ? 1 : 0)
            }
            .rectangularHitTarget()
            .gesture(selectionGesture(in: proxy.size), including: adjustedRect == nil ? .all : .subviews)
        }
        .focusable()
        .focused($selectionHasFocus)
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onExitCommand(perform: onCancel)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard let rect = adjustedRect else { return .ignored }
            let amount: CGFloat = press.modifiers.contains(.shift) ? 10 : 1
            let delta = CGSize(width: press.key == .leftArrow ? -amount : (press.key == .rightArrow ? amount : 0),
                               height: press.key == .upArrow ? -amount : (press.key == .downArrow ? amount : 0))
            adjustedRect = AreaSelectionGeometry.moved(rect, translation: delta, bounds: screen.frame.size)
            return .handled
        }
        .onAppear {
            dragStart = nil
            dragCurrent = nil
            isFinishingSelection = false
            adjustedRect = nil
            adjustmentOrigin = nil
            DispatchQueue.main.async {
                selectionHasFocus = true
            }
        }
    }

    private var selectionRect: CGRect? {
        if let adjustedRect { return adjustedRect }
        guard let dragStart, let dragCurrent else { return nil }
        return AreaSelectionGeometry.alignedSelectionRect(between: dragStart, and: dragCurrent)
    }

    @ViewBuilder
    private func dimensionBadge(for rect: CGRect) -> some View {
        let badgeWidth: CGFloat = 110
        let badgeX = min(max(rect.midX, badgeWidth / 2 + 8), screen.frame.width - badgeWidth / 2 - 8)
        let badgeY = rect.maxY + 18 < screen.frame.height - 30
            ? rect.maxY + 18
            : max(rect.minY - 18, 30)

        Text("\(Int(rect.width.rounded())) × \(Int(rect.height.rounded())) px")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
            .position(x: badgeX, y: badgeY)
    }

    private func selectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = clamped(value.startLocation, to: size)
                }
                dragCurrent = clamped(value.location, to: size)
            }
            .onEnded { _ in
                guard let rect = selectionRect, rect.width >= 8, rect.height >= 8 else {
                    dragStart = nil
                    dragCurrent = nil
                    return
                }

                if adjustsSelectionBeforeCapture {
                    adjustedRect = rect
                } else {
                    finishSelection(rect)
                }
            }
    }

    private func finishSelection(_ rect: CGRect) {
        guard !isFinishingSelection else { return }
        let area = captureArea(for: rect)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            adjustedRect = nil
            dragStart = nil
            dragCurrent = nil
            isFinishingSelection = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onSelect(area) }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            guard let rect = adjustedRect else { return }
            if adjustmentOrigin == nil { adjustmentOrigin = rect }
            adjustedRect = AreaSelectionGeometry.moved(adjustmentOrigin ?? rect, translation: value.translation, bounds: size)
        }.onEnded { _ in adjustmentOrigin = nil }
    }

    private func resizeGesture(corner: AreaSelectionResizeCorner, in size: CGSize) -> some Gesture {
        DragGesture().onChanged { value in
            guard let rect = adjustedRect else { return }
            if adjustmentOrigin == nil { adjustmentOrigin = rect }
            adjustedRect = AreaSelectionGeometry.resized(adjustmentOrigin ?? rect, corner: corner, translation: value.translation, bounds: size)
        }.onEnded { _ in adjustmentOrigin = nil }
    }

    private func clamped(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), size.width),
            y: min(max(point.y, 0), size.height)
        )
    }

    private func captureArea(for rect: CGRect) -> CaptureArea {
        let screenFrame = screen.frame
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return AreaSelectionGeometry.captureArea(
            for: rect,
            on: screenFrame,
            displayID: displayID
        )
    }
}
