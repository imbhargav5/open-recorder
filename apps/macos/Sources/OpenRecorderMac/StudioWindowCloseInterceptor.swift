import AppKit
import SwiftUI

struct StudioWindowCloseInterceptor: NSViewRepresentable {
    typealias CloseRequestHandler = @MainActor () async -> Bool

    var onCloseRequest: CloseRequestHandler

    func makeNSView(context: Context) -> StudioWindowCloseInterceptionView {
        let view = StudioWindowCloseInterceptionView()
        view.onCloseRequest = onCloseRequest
        return view
    }

    func updateNSView(_ nsView: StudioWindowCloseInterceptionView, context: Context) {
        nsView.onCloseRequest = onCloseRequest
        nsView.attachToCurrentWindow()
    }

    static func dismantleNSView(
        _ nsView: StudioWindowCloseInterceptionView,
        coordinator: Void
    ) {
        nsView.detach()
    }
}

@MainActor
final class StudioWindowCloseInterceptionView: NSView, NSWindowDelegate {
    var onCloseRequest: StudioWindowCloseInterceptor.CloseRequestHandler = { true }

    private weak var interceptedWindow: NSWindow?
    nonisolated(unsafe) private weak var forwardedDelegate: (any NSWindowDelegate)?
    private var closeTask: Task<Void, Never>?
    private var allowsNextClose = false

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            detach()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToCurrentWindow()
    }

    func attachToCurrentWindow() {
        guard let window else { return }
        if interceptedWindow !== window {
            detach()
            interceptedWindow = window
        }
        guard window.delegate !== self else { return }
        forwardedDelegate = window.delegate
        window.delegate = self
    }

    func detach() {
        closeTask?.cancel()
        closeTask = nil
        if let interceptedWindow, interceptedWindow.delegate === self {
            interceptedWindow.delegate = forwardedDelegate
        }
        interceptedWindow = nil
        forwardedDelegate = nil
        allowsNextClose = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsNextClose {
            allowsNextClose = false
            return true
        }

        guard closeTask == nil else { return false }
        if forwardedDelegate?.windowShouldClose?(sender) == false {
            return false
        }

        let closeRequest = onCloseRequest
        closeTask = Task { @MainActor [weak self, weak sender] in
            let shouldClose = await closeRequest()
            if shouldClose {
                self?.completeApprovedClose(sender: sender)
            } else if !Task.isCancelled {
                self?.closeTask = nil
            }
        }
        return false
    }

    private func completeApprovedClose(sender: NSWindow?) {
        closeTask = nil
        guard let sender else { return }
        allowsNextClose = true
        sender.performClose(nil)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || forwardedDelegate?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if forwardedDelegate?.responds(to: aSelector) == true {
            return forwardedDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}
