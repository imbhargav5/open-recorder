import Foundation
import Observation

struct CaptureEffectHandlers {
    var showHUD: () -> Void = {}
    var hideHUD: () -> Void = {}
    var closeCaptureSetup: () -> Void = {}
    var showSourceSelector: () -> Void = {}
    var showRecordingSetup: (CaptureSourceKind) -> Void = { _ in }
    var dismissScreenSelection: () -> Void = {}
    var dismissCaptureWindows: () -> Void = {}
    var hideAppWindowsForCapture: () -> Void = {}
    var focusActiveCaptureWindow: () -> Void = {}
    var flashDisplay: (CaptureSource) -> Void = { _ in }
    var cancelRecordingStart: () -> Void = {}
    var cancelScreenshotCapture: () -> Void = {}
    var prepareRecordingFile: (CaptureSource) -> Void = { _ in }
    var runRecordingStart: (CaptureSource, URL) async -> Void = { _, _ in }
    var stopRecording: (CaptureSource?) async -> Void = { _ in }
    var runScreenshotCapture: (CaptureSource) async -> Void = { _ in }
}

@Observable
@MainActor
final class CaptureDriver {
    var state: CaptureState
    var lastTransition: CaptureTransition?

    @ObservationIgnored private var transitionHandler: (CaptureTransition) -> Void = { _ in }
    @ObservationIgnored private var effectObserver: ([CaptureEffect]) -> Void = { _ in }
    @ObservationIgnored private var effectHandlers = CaptureEffectHandlers()
    @ObservationIgnored private var recordingStartTask: Task<Void, Never>?
    @ObservationIgnored private var screenshotCaptureTask: Task<Void, Never>?

    init(initialState: CaptureState = .choosingMode) {
        state = initialState
    }

    func configure(
        transitionHandler: @escaping (CaptureTransition) -> Void = { _ in },
        effectObserver: @escaping ([CaptureEffect]) -> Void = { _ in },
        effectHandlers: CaptureEffectHandlers = CaptureEffectHandlers()
    ) {
        self.transitionHandler = transitionHandler
        self.effectObserver = effectObserver
        self.effectHandlers = effectHandlers
    }

    @discardableResult
    func send(_ event: CaptureEvent) -> CaptureTransition {
        let transition = state.applying(event)
        state = transition.state
        lastTransition = transition
        transitionHandler(transition)
        effectObserver(transition.effects)
        perform(transition.effects)
        return transition
    }

    func setStateForTesting(_ state: CaptureState) {
        self.state = state
        lastTransition = nil
    }

    private func perform(_ effects: [CaptureEffect]) {
        for effect in effects {
            switch effect {
            case .showHUD:
                effectHandlers.showHUD()
            case .hideHUD:
                effectHandlers.hideHUD()
            case .closeCaptureSetup:
                effectHandlers.closeCaptureSetup()
            case .showSourceSelector:
                effectHandlers.showSourceSelector()
            case .showRecordingSetup(let kind):
                effectHandlers.showRecordingSetup(kind)
            case .dismissScreenSelection:
                effectHandlers.dismissScreenSelection()
            case .dismissCaptureWindows:
                effectHandlers.dismissCaptureWindows()
            case .hideAppWindowsForCapture:
                effectHandlers.hideAppWindowsForCapture()
            case .focusActiveCaptureWindow:
                effectHandlers.focusActiveCaptureWindow()
            case .flashDisplay(let source):
                effectHandlers.flashDisplay(source)
            case .cancelRecordingStart:
                recordingStartTask?.cancel()
                recordingStartTask = nil
                effectHandlers.cancelRecordingStart()
            case .cancelScreenshotCapture:
                screenshotCaptureTask?.cancel()
                screenshotCaptureTask = nil
                effectHandlers.cancelScreenshotCapture()
            case .prepareRecordingFile(let source):
                effectHandlers.prepareRecordingFile(source)
            case .runRecordingStart(let source, let outputURL):
                recordingStartTask?.cancel()
                recordingStartTask = Task { [weak self] in
                    await self?.effectHandlers.runRecordingStart(source, outputURL)
                    await MainActor.run {
                        self?.recordingStartTask = nil
                    }
                }
            case .stopRecording(let source):
                Task { [weak self] in
                    await self?.effectHandlers.stopRecording(source)
                }
            case .runScreenshotCapture(let source):
                screenshotCaptureTask?.cancel()
                screenshotCaptureTask = Task { [weak self] in
                    await self?.effectHandlers.runScreenshotCapture(source)
                    await MainActor.run {
                        self?.screenshotCaptureTask = nil
                    }
                }
            }
        }
    }
}
