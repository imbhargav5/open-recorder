import Foundation
import Observation

struct CaptureEffectHandlers {
    var showHUD: () -> Void = {}
    var hideHUD: () -> Void = {}
    var closeCaptureSetup: () -> Void = {}
    var showSourceSelector: () -> Void = {}
    var showAreaSelector: () -> Void = {}
    var showRecordingSetup: (CaptureSourceKind) -> Void = { _ in }
    var dismissScreenSelection: () -> Void = {}
    var dismissCaptureWindows: () -> Void = {}
    var focusActiveCaptureWindow: () -> Void = {}
    var flashDisplay: (CaptureSource) -> Void = { _ in }
    var cancelRecordingStart: () -> Void = {}
    var cancelScreenshotCapture: () -> Void = {}
    var prepareRecordingFile: (CaptureSource) -> Void = { _ in }
    var runRecordingStart: (CaptureSource, URL) -> Void = { _, _ in }
    var stopRecording: (CaptureSource?) -> Void = { _ in }
    var runScreenshotCapture: (CaptureSource) -> Void = { _ in }
}

@Observable
@MainActor
final class CaptureDriver {
    var state: CaptureState
    var lastTransition: CaptureTransition?

    @ObservationIgnored private var transitionHandler: (CaptureTransition) -> Void = { _ in }
    @ObservationIgnored private var effectObserver: ([CaptureEffect]) -> Void = { _ in }
    @ObservationIgnored private var effectHandlers = CaptureEffectHandlers()

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
            case .showAreaSelector:
                effectHandlers.showAreaSelector()
            case .showRecordingSetup(let kind):
                effectHandlers.showRecordingSetup(kind)
            case .dismissScreenSelection:
                effectHandlers.dismissScreenSelection()
            case .dismissCaptureWindows:
                effectHandlers.dismissCaptureWindows()
            case .focusActiveCaptureWindow:
                effectHandlers.focusActiveCaptureWindow()
            case .flashDisplay(let source):
                effectHandlers.flashDisplay(source)
            case .cancelRecordingStart:
                effectHandlers.cancelRecordingStart()
            case .cancelScreenshotCapture:
                effectHandlers.cancelScreenshotCapture()
            case .prepareRecordingFile(let source):
                effectHandlers.prepareRecordingFile(source)
            case .runRecordingStart(let source, let outputURL):
                effectHandlers.runRecordingStart(source, outputURL)
            case .stopRecording(let source):
                effectHandlers.stopRecording(source)
            case .runScreenshotCapture(let source):
                effectHandlers.runScreenshotCapture(source)
            }
        }
    }
}
