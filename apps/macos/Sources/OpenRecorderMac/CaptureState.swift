import Foundation

enum HUDPresentationState: Hashable {
    case visible
    case hidden

    var isVisible: Bool {
        self == .visible
    }
}

enum CaptureRecoveryAction: Hashable {
    case waitForCurrentCapture
    case chooseSource
    case drawArea
    case openScreenRecordingSettings
    case openMicrophoneSettings
    case openCameraSettings
    case chooseMicrophone
    case chooseCamera
}

enum CaptureMediaAuthorizationState: Hashable {
    case undetermined
    case authorized
    case denied
}

enum CaptureBlocker: Hashable {
    case captureAlreadyRunning
    case sourceRequired
    case sourceUnavailable(name: String)
    case areaSelectionRequired
    case screenRecordingPermissionRequired
    case screenRecordingPermissionNeedsRestart
    case microphonePermissionDenied
    case cameraPermissionDenied
    case microphoneUnavailable(deviceID: String?)
    case cameraUnavailable(deviceID: String?)

    var recoveryAction: CaptureRecoveryAction {
        switch self {
        case .captureAlreadyRunning:
            .waitForCurrentCapture
        case .sourceRequired, .sourceUnavailable:
            .chooseSource
        case .areaSelectionRequired:
            .drawArea
        case .screenRecordingPermissionRequired, .screenRecordingPermissionNeedsRestart:
            .openScreenRecordingSettings
        case .microphonePermissionDenied:
            .openMicrophoneSettings
        case .cameraPermissionDenied:
            .openCameraSettings
        case .microphoneUnavailable:
            .chooseMicrophone
        case .cameraUnavailable:
            .chooseCamera
        }
    }

    var message: String {
        switch self {
        case .captureAlreadyRunning:
            "Finish or cancel the current capture before starting another."
        case .sourceRequired:
            "Choose a source first."
        case .sourceUnavailable(let name):
            "\(name) is no longer available. Choose another source."
        case .areaSelectionRequired:
            "Draw the area you want to capture."
        case .screenRecordingPermissionRequired:
            "Screen Recording permission is required."
        case .screenRecordingPermissionNeedsRestart:
            "Screen Recording permission is still unavailable. You may need to restart Open Recorder after enabling it."
        case .microphonePermissionDenied:
            "Microphone permission is denied. Open System Settings to record narration."
        case .cameraPermissionDenied:
            "Camera permission is denied. Open System Settings to record facecam video."
        case .microphoneUnavailable:
            "The selected microphone is unavailable. Choose another microphone or turn it off."
        case .cameraUnavailable:
            "The selected camera is unavailable. Choose another camera or turn it off."
        }
    }
}

struct CaptureReadiness: Hashable {
    var source: CaptureSource?
    var blockers: [CaptureBlocker]
    var isChecking: Bool

    var canCapture: Bool {
        !isChecking && blockers.isEmpty
    }

    var primaryBlocker: CaptureBlocker? {
        blockers.first
    }
}

enum CapturePhase: Hashable {
    case idle
    case setup(CaptureMode)
    case sourceSelecting(CaptureMode)
    case choosingMode
    case choosingSourceType(CaptureMode)
    case screenSelecting(CaptureMode)
    case selectingSource(CaptureMode)
    case ready(CaptureMode, CaptureSource)
    case areaSelecting(CaptureMode)
    case countingDownRecording(CaptureSource)
    case startingRecording(CaptureSource, stopRequested: Bool)
    case recording(CaptureSource)
    case stoppingRecording(CaptureSource)
    case capturingScreenshot(CaptureSource)

    var requiresHiddenCaptureUI: Bool {
        switch self {
        case .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording,
             .capturingScreenshot:
            true
        case .idle,
             .setup,
             .sourceSelecting,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting:
            false
        }
    }

    var mode: CaptureMode? {
        switch self {
        case .idle, .choosingMode:
            nil
        case .setup(let mode),
             .sourceSelecting(let mode):
            mode
        case .selectingSource(let mode),
             .choosingSourceType(let mode),
             .screenSelecting(let mode),
             .areaSelecting(let mode):
            mode
        case .ready(let mode, _):
            mode
        case .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording:
            .recording
        case .capturingScreenshot:
            .screenshot
        }
    }

    var source: CaptureSource? {
        switch self {
        case .ready(_, let source),
             .countingDownRecording(let source),
             .startingRecording(let source, _),
             .recording(let source),
             .stoppingRecording(let source),
             .capturingScreenshot(let source):
            source
        case .idle,
             .setup,
             .sourceSelecting,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .areaSelecting:
            nil
        }
    }

    var recordingPhase: RecordingPhase {
        switch self {
        case .countingDownRecording:
            .countingDown
        case .startingRecording:
            .starting
        case .recording:
            .recording
        case .stoppingRecording:
            .stopping
        case .idle,
             .setup,
             .sourceSelecting,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting,
             .capturingScreenshot:
            .idle
        }
    }
}

typealias HUDPhase = CapturePhase

enum CaptureEvent: Hashable {
    case beginCapture(CaptureMode, runtimeIsRecording: Bool)
    case chooseSourceType(CaptureSourceType)
    case requestSourceSelector(CaptureSourceKind?)
    case cancelSourceSelection
    case selectSource(CaptureSource)
    case requestScreenSelection
    case completeScreenSelection(CaptureSource)
    case cancelScreenSelection(message: String?)
    case requestInteractiveAreaSelection
    case completeInteractiveAreaSelection(CaptureSource)
    case cancelInteractiveAreaSelection
    case restoreSetup(CaptureMode, CaptureSource?, preferredSourceKind: CaptureSourceKind)
    case cancelCapture
    case showHUD
    case hideHUD
    case showEditor
    case recordingStartRequested
    case recordingFilePrepared(CaptureSource, URL)
    case recordingFilePreparationFailed(CaptureSource, message: String)
    case recordingCountdownStarted(CaptureSource)
    case recordingStarting(CaptureSource)
    case recordingStarted(CaptureSource)
    case recordingStopRequested
    case recordingStopping(CaptureSource?)
    case recordingStopped(message: String?)
    case recordingRestored(CaptureSource, message: String?)
    case recordingFailed(CaptureSource?, message: String)
    case screenshotRequested
    case screenshotCapturing(CaptureSource)
    case screenshotSucceeded
    case screenshotCanceled
    case screenshotRestored(CaptureSource, message: String)
    case refreshSelectedSource(CaptureSource?)
}

enum CaptureEffect: Hashable {
    case showHUD
    case hideHUD
    case closeCaptureSetup
    case showSourceSelector
    case showAreaSelector
    case showRecordingSetup(CaptureSourceKind)
    case dismissScreenSelection
    case dismissCaptureWindows
    case hideAppWindowsForCapture
    case focusActiveCaptureWindow
    case flashDisplay(CaptureSource)
    case cancelRecordingStart
    case cancelScreenshotCapture
    case prepareRecordingFile(CaptureSource)
    case runRecordingStart(CaptureSource, URL)
    case stopRecording(CaptureSource?)
    case runScreenshotCapture(CaptureSource)
}

struct CaptureTransition: Hashable {
    var state: CaptureState
    var effects: [CaptureEffect] = []
    var statusMessage: String?
}

struct CaptureState: Hashable {
    var phase: CapturePhase
    var presentation: HUDPresentationState
    var selectedSource: CaptureSource?
    var preferredSourceKind: CaptureSourceKind?

    init(
        phase: CapturePhase = .setup(.recording),
        presentation: HUDPresentationState = .visible,
        selectedSource: CaptureSource? = nil,
        preferredSourceKind: CaptureSourceKind? = nil
    ) {
        self.phase = phase
        self.presentation = phase.requiresHiddenCaptureUI ? .hidden : presentation
        self.selectedSource = phase.source ?? selectedSource
        self.preferredSourceKind = preferredSourceKind
    }

    static var idle: CaptureState {
        CaptureState(phase: .idle)
    }

    static var choosingMode: CaptureState {
        CaptureState(phase: .choosingMode)
    }

    static func setup(
        _ mode: CaptureMode,
        source: CaptureSource? = nil,
        preferredSourceKind: CaptureSourceKind = .display
    ) -> CaptureState {
        CaptureState(
            phase: .setup(mode),
            selectedSource: source,
            preferredSourceKind: source?.kind ?? preferredSourceKind
        )
    }

    static func sourceSelecting(
        _ mode: CaptureMode,
        source: CaptureSource? = nil,
        preferredSourceKind: CaptureSourceKind = .display
    ) -> CaptureState {
        CaptureState(
            phase: .sourceSelecting(mode),
            selectedSource: source,
            preferredSourceKind: preferredSourceKind
        )
    }

    static func choosingSourceType(_ mode: CaptureMode) -> CaptureState {
        CaptureState(phase: .choosingSourceType(mode))
    }

    static func screenSelecting(_ mode: CaptureMode) -> CaptureState {
        CaptureState(phase: .screenSelecting(mode), preferredSourceKind: .display)
    }

    static func selectingSource(_ mode: CaptureMode) -> CaptureState {
        CaptureState(phase: .selectingSource(mode))
    }

    static func ready(_ mode: CaptureMode, _ source: CaptureSource) -> CaptureState {
        CaptureState(phase: .ready(mode, source), selectedSource: source, preferredSourceKind: source.kind)
    }

    static func areaSelecting(_ mode: CaptureMode) -> CaptureState {
        CaptureState(phase: .areaSelecting(mode), preferredSourceKind: .area)
    }

    static func countingDownRecording(_ source: CaptureSource) -> CaptureState {
        CaptureState(phase: .countingDownRecording(source), selectedSource: source, preferredSourceKind: source.kind)
    }

    static func startingRecording(_ source: CaptureSource, stopRequested: Bool = false) -> CaptureState {
        CaptureState(
            phase: .startingRecording(source, stopRequested: stopRequested),
            selectedSource: source,
            preferredSourceKind: source.kind
        )
    }

    static func recording(_ source: CaptureSource) -> CaptureState {
        CaptureState(phase: .recording(source), selectedSource: source, preferredSourceKind: source.kind)
    }

    static func stoppingRecording(_ source: CaptureSource) -> CaptureState {
        CaptureState(phase: .stoppingRecording(source), selectedSource: source, preferredSourceKind: source.kind)
    }

    static func capturingScreenshot(_ source: CaptureSource) -> CaptureState {
        CaptureState(phase: .capturingScreenshot(source), selectedSource: source, preferredSourceKind: source.kind)
    }

    func withPhase(_ phase: CapturePhase) -> CaptureState {
        var next = self
        next.setPhase(phase)
        return next
    }

    func withPresentation(_ presentation: HUDPresentationState) -> CaptureState {
        CaptureState(
            phase: phase,
            presentation: presentation,
            selectedSource: selectedSource,
            preferredSourceKind: preferredSourceKind
        )
    }

    var mode: CaptureMode? {
        phase.mode
    }

    var source: CaptureSource? {
        phase.source ?? selectedSource
    }

    var recordingPhase: RecordingPhase {
        phase.recordingPhase
    }

    var isAreaSelectionActive: Bool {
        if case .areaSelecting = phase {
            return true
        }
        return false
    }

    var isCaptureOccupied: Bool {
        switch phase {
        case .idle, .choosingMode, .setup:
            false
        case .sourceSelecting,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting,
             .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording,
             .capturingScreenshot:
            true
        }
    }

    var captureFlow: CaptureFlow {
        switch phase {
        case .idle, .choosingMode:
            .choice
        case .setup(let mode),
             .sourceSelecting(let mode):
            mode == .screenshot ? .screenshotSetup : .recordingSetup
        case .choosingSourceType(let mode),
             .screenSelecting(let mode),
             .selectingSource(let mode),
             .ready(let mode, _),
             .areaSelecting(let mode):
            mode == .screenshot ? .screenshotSetup : .recordingSetup
        case .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording:
            .recording
        case .capturingScreenshot:
            .screenshotSetup
        }
    }

    var requiresHiddenCaptureUI: Bool {
        phase.requiresHiddenCaptureUI
    }

    var canShowCaptureUI: Bool {
        !requiresHiddenCaptureUI
    }

    func canChangeRecordingOptions(runtimeIsRecording: Bool) -> Bool {
        recordingPhase == .idle && !runtimeIsRecording
    }

    func canStartNewCapture(runtimeIsRecording: Bool) -> Bool {
        recordingPhase == .idle &&
            !runtimeIsRecording &&
            !isAreaSelectionActive &&
            !isCaptureOccupied
    }

    func readiness(
        availableSources: [CaptureSource],
        screenRecordingPermissionState: ScreenRecordingPermissionState,
        options: CaptureOptionsState,
        runtimeIsRecording: Bool,
        microphoneAuthorization: CaptureMediaAuthorizationState = .authorized,
        cameraAuthorization: CaptureMediaAuthorizationState = .authorized,
        isChecking: Bool = false
    ) -> CaptureReadiness {
        let selectedSource = source
        var blockers: [CaptureBlocker] = []

        if runtimeIsRecording || recordingPhase != .idle {
            blockers.append(.captureAlreadyRunning)
        }

        switch screenRecordingPermissionState {
        case .granted:
            break
        case .requestAvailable:
            blockers.append(.screenRecordingPermissionRequired)
        case .requestAlreadyShown:
            blockers.append(.screenRecordingPermissionNeedsRestart)
        }

        if let selectedSource {
            switch selectedSource.kind {
            case .area:
                if selectedSource.area == nil {
                    blockers.append(.areaSelectionRequired)
                }
            case .display, .window:
                if !availableSources.contains(where: { $0.representsSameCaptureSource(as: selectedSource) }) {
                    blockers.append(.sourceUnavailable(name: selectedSource.name))
                }
            }
        } else {
            blockers.append(.sourceRequired)
        }

        if mode == .recording {
            if options.includeMicrophone {
                if microphoneAuthorization == .denied {
                    blockers.append(.microphonePermissionDenied)
                } else if !options.hasAvailableMicrophoneSelection {
                    blockers.append(.microphoneUnavailable(deviceID: options.selectedMicrophoneDeviceID))
                }
            }
            if options.includeCamera {
                if cameraAuthorization == .denied {
                    blockers.append(.cameraPermissionDenied)
                } else if !options.hasAvailableCameraSelection {
                    blockers.append(.cameraUnavailable(deviceID: options.selectedCameraDeviceID))
                }
            }
        }

        return CaptureReadiness(source: selectedSource, blockers: blockers, isChecking: isChecking)
    }

    func isDirectStopState(runtimeIsRecording: Bool) -> Bool {
        switch phase {
        case .countingDownRecording, .startingRecording, .recording:
            true
        case .idle,
             .setup,
             .sourceSelecting,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting,
             .stoppingRecording,
             .capturingScreenshot:
            runtimeIsRecording
        }
    }

    func shouldRegisterRecordingHotKey(runtimeIsRecording: Bool) -> Bool {
        guard !runtimeIsRecording else { return true }

        switch phase {
        case .setup(.recording):
            return source != nil
        case .ready(.recording, _),
             .countingDownRecording,
             .startingRecording,
             .recording:
            return true
        case .idle,
             .setup,
             .sourceSelecting,
             .choosingMode,
             .choosingSourceType,
             .screenSelecting,
             .selectingSource,
             .ready,
             .areaSelecting,
             .stoppingRecording,
             .capturingScreenshot:
            return false
        }
    }

    func applying(_ event: CaptureEvent) -> CaptureTransition {
        var next = self
        var effects: [CaptureEffect] = []
        var statusMessage: String?

        func finish(_ state: CaptureState? = nil) -> CaptureTransition {
            CaptureTransition(state: state ?? next, effects: effects, statusMessage: statusMessage)
        }

        func modeForSelection() -> CaptureMode {
            next.mode ?? mode ?? .recording
        }

        switch event {
        case .beginCapture(let mode, let runtimeIsRecording):
            guard canStartNewCapture(runtimeIsRecording: runtimeIsRecording) else {
                statusMessage = "Finish or cancel the current capture before starting another."
                effects.append(.focusActiveCaptureWindow)
                return finish(self)
            }
            next.setPhase(.setup(mode), clearSource: false)
            next.preferredSourceKind = next.selectedSource?.kind ?? next.preferredSourceKind ?? .display
            statusMessage = next.selectedSource == nil ? "Choose a source." : nil
            effects.append(.dismissScreenSelection)
            effects.append(.showHUD)

        case .chooseSourceType(let sourceType):
            let mode = modeForSelection()
            switch sourceType {
            case .screen:
                next.setPhase(.screenSelecting(mode), clearSource: false)
                next.preferredSourceKind = .display
                statusMessage = "Choose a screen."
                effects.append(.dismissScreenSelection)
            case .window:
                next.setPhase(.selectingSource(mode), clearSource: false)
                next.preferredSourceKind = .window
                statusMessage = "Choose a window."
                effects.append(.showSourceSelector)
            case .area:
                next.setPhase(.selectingSource(mode), clearSource: false)
                next.preferredSourceKind = .area
                statusMessage = "Choose an area."
                effects.append(.showSourceSelector)
            }

        case .requestSourceSelector(let kind):
            let resolvedKind = kind ?? next.selectedSource?.kind ?? next.preferredSourceKind ?? .display
            next.setPhase(.sourceSelecting(modeForSelection()), clearSource: false)
            next.preferredSourceKind = resolvedKind
            statusMessage = "Choose what to capture."
            effects.append(.showSourceSelector)

        case .cancelSourceSelection:
            next.setPhase(.setup(modeForSelection()), clearSource: false)
            statusMessage = next.selectedSource.map { $0.kind == .area ? "Selected area" : "Selected \($0.name)" }
                ?? "Choose a source."
            effects.append(.showHUD)

        case .selectSource(let source):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            let mode = modeForSelection()
            next.setPhase(.setup(mode))
            statusMessage = source.kind == .area ? "Selected area" : "Selected \(source.name)"
            if mode == .recording {
                effects.append(.showHUD)
            }
            if source.kind == .display {
                effects.append(.flashDisplay(source))
            }

        case .requestScreenSelection:
            next.setPhase(.screenSelecting(modeForSelection()), clearSource: false)
            next.preferredSourceKind = .display
            statusMessage = "Choose a screen."
            effects.append(.dismissScreenSelection)

        case .completeScreenSelection(let source):
            guard source.kind == .display else {
                statusMessage = "Choose a screen."
                return finish(self)
            }
            next.selectedSource = source
            next.preferredSourceKind = .display
            next.setPhase(.setup(modeForSelection()))
            statusMessage = "Selected \(source.name)"
            effects.append(.dismissScreenSelection)
            effects.append(.showHUD)
            effects.append(.flashDisplay(source))

        case .cancelScreenSelection(let message):
            next.setPhase(.setup(modeForSelection()), clearSource: false)
            statusMessage = message ?? (next.selectedSource == nil ? "Choose a source." : nil)
            effects.append(.dismissScreenSelection)
            effects.append(.showHUD)

        case .requestInteractiveAreaSelection:
            next.setPhase(.areaSelecting(modeForSelection()), clearSource: false)
            next.preferredSourceKind = .area
            statusMessage = "Draw an area to capture."
            effects.append(.showAreaSelector)

        case .completeInteractiveAreaSelection(let source):
            next.selectedSource = source
            next.preferredSourceKind = .area
            let mode = modeForSelection()
            next.setPhase(.setup(mode))
            statusMessage = "Selected area"
            effects.append(.showHUD)

        case .cancelInteractiveAreaSelection:
            next.setPhase(.setup(modeForSelection()), clearSource: false)
            statusMessage = next.selectedSource.map {
                $0.kind == .area ? "Selected area" : "Selected \($0.name)"
            } ?? "Choose a source."
            effects.append(.showHUD)

        case .restoreSetup(let mode, let source, let preferredSourceKind):
            next.selectedSource = source
            next.preferredSourceKind = source?.kind ?? preferredSourceKind
            next.setPhase(.setup(mode), clearSource: source == nil)

        case .cancelCapture:
            let previousPhase = phase
            next.setPhase(.setup(modeForSelection()), clearSource: false)
            next.preferredSourceKind = next.selectedSource?.kind ?? next.preferredSourceKind ?? .display
            statusMessage = "Ready"
            effects.append(.dismissScreenSelection)
            effects.append(.cancelRecordingStart)
            effects.append(.cancelScreenshotCapture)
            if shouldCloseCaptureSetup(from: previousPhase, to: next.phase) {
                effects.append(.closeCaptureSetup)
            }

        case .showHUD:
            guard next.canShowCaptureUI else {
                next.presentation = .hidden
                return finish()
            }
            next.presentation = .visible
            effects.append(.showHUD)

        case .hideHUD:
            next.presentation = .hidden
            effects.append(.hideHUD)

        case .showEditor, .screenshotSucceeded, .screenshotCanceled:
            next.setPhase(.setup(modeForSelection()), clearSource: false)
            effects.append(.dismissScreenSelection)
            effects.append(.cancelRecordingStart)
            effects.append(.cancelScreenshotCapture)

        case .recordingStartRequested:
            guard let source = next.source else {
                statusMessage = "Choose a source first."
                return finish()
            }
            guard next.recordingPhase == .idle else {
                return finish()
            }
            effects.append(.prepareRecordingFile(source))

        case .recordingFilePrepared(let source, let outputURL):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.countingDownRecording(source))
            statusMessage = "Recording starts in 3..."
            effects.append(.dismissScreenSelection)
            effects.append(.hideAppWindowsForCapture)
            effects.append(.runRecordingStart(source, outputURL))

        case .recordingFilePreparationFailed(_, let message):
            statusMessage = message

        case .recordingCountdownStarted(let source):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.countingDownRecording(source))
            statusMessage = "Recording starts in 3..."
            effects.append(.dismissScreenSelection)
            effects.append(.hideAppWindowsForCapture)

        case .recordingStarting(let source):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.startingRecording(source, stopRequested: false))
            statusMessage = "Starting recording..."
            effects.append(.dismissScreenSelection)
            effects.append(.hideAppWindowsForCapture)

        case .recordingStarted(let source):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.recording(source))
            statusMessage = "Recording \(source.name)"
            effects.append(.dismissScreenSelection)
            effects.append(.hideAppWindowsForCapture)

        case .recordingStopRequested:
            switch next.phase {
            case .countingDownRecording(let source):
                next.selectedSource = source
                next.preferredSourceKind = source.kind
                next.setPhase(.setup(.recording))
                statusMessage = "Recording canceled."
                effects.append(.cancelRecordingStart)
                effects.append(.showRecordingSetup(source.kind))
            case .startingRecording(let source, _):
                next.setPhase(.startingRecording(source, stopRequested: true))
                statusMessage = "Recording will stop after it starts."
            case .recording(let source):
                next.setPhase(.stoppingRecording(source))
                effects.append(.dismissCaptureWindows)
                effects.append(.stopRecording(source))
            case .stoppingRecording:
                break
            case .idle,
                 .setup,
                 .sourceSelecting,
                 .choosingMode,
                 .choosingSourceType,
                 .screenSelecting,
                 .selectingSource,
                 .ready,
                 .areaSelecting,
                 .capturingScreenshot:
                break
            }

        case .recordingStopping(let source):
            if let source {
                next.setPhase(.stoppingRecording(source))
                effects.append(.dismissCaptureWindows)
            }
            effects.append(.stopRecording(source))

        case .recordingStopped(let message):
            next.setPhase(.setup(.recording), clearSource: false)
            statusMessage = message
            effects.append(.dismissScreenSelection)
            effects.append(.cancelRecordingStart)

        case .recordingRestored(let source, let message):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.setup(.recording))
            statusMessage = message
            effects.append(.showRecordingSetup(source.kind))

        case .recordingFailed(let source, let message):
            if let source {
                next.selectedSource = source
                next.preferredSourceKind = source.kind
                next.setPhase(.setup(.recording))
                effects.append(.showRecordingSetup(source.kind))
            } else {
                next.setPhase(.setup(.recording), clearSource: true)
            }
            statusMessage = message

        case .screenshotRequested:
            guard let source = next.source else {
                statusMessage = "Choose a source first."
                return finish()
            }
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.capturingScreenshot(source))
            effects.append(.dismissScreenSelection)
            effects.append(.hideAppWindowsForCapture)
            effects.append(.runScreenshotCapture(source))

        case .screenshotCapturing(let source):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.capturingScreenshot(source))
            effects.append(.dismissScreenSelection)
            effects.append(.hideAppWindowsForCapture)

        case .screenshotRestored(let source, let message):
            next.selectedSource = source
            next.preferredSourceKind = source.kind
            next.setPhase(.setup(.screenshot))
            statusMessage = message
            effects.append(.showHUD)

        case .refreshSelectedSource(let source):
            switch next.phase {
            case .countingDownRecording,
                 .startingRecording,
                 .recording,
                 .stoppingRecording,
                 .capturingScreenshot:
                // A catalog refresh must not rewrite the source of in-flight runtime work.
                return finish(self)
            case .idle,
                 .setup,
                 .sourceSelecting,
                 .choosingMode,
                 .choosingSourceType,
                 .screenSelecting,
                 .selectingSource,
                 .ready,
                 .areaSelecting:
                break
            }
            guard let previousSource = next.selectedSource else {
                // Refreshing the catalog must never choose a source on the user's behalf.
                return finish(self)
            }
            guard previousSource.kind != .area else {
                // Interactive areas are local selections and do not appear in the source catalog.
                return finish(self)
            }
            guard let source,
                  source.representsSameCaptureSource(as: previousSource) else {
                next.selectedSource = nil
                if let mode = next.mode {
                    next.setPhase(.setup(mode), clearSource: true)
                }
                statusMessage = "\(previousSource.name) is no longer available. Choose another source."
                return finish()
            }

            next.selectedSource = source
            next.preferredSourceKind = source.kind
            if case .ready(let mode, _) = next.phase {
                next.setPhase(.ready(mode, source))
            }
        }

        return finish()
    }

    private mutating func setPhase(_ phase: CapturePhase, clearSource: Bool = false) {
        let previousRequiresHiddenCaptureUI = self.phase.requiresHiddenCaptureUI
        self.phase = phase
        if phase.requiresHiddenCaptureUI {
            presentation = .hidden
        } else if previousRequiresHiddenCaptureUI {
            presentation = .visible
        }
        if let source = phase.source {
            selectedSource = source
            preferredSourceKind = source.kind
        } else if clearSource {
            selectedSource = nil
        }
    }

    private func shouldCloseCaptureSetup(from previousPhase: CapturePhase, to nextPhase: CapturePhase) -> Bool {
        guard case .choosingMode = nextPhase else {
            return false
        }

        switch previousPhase {
        case .sourceSelecting, .choosingSourceType, .screenSelecting, .selectingSource, .ready, .areaSelecting:
            return true
        case .idle,
             .setup,
             .choosingMode,
             .countingDownRecording,
             .startingRecording,
             .recording,
             .stoppingRecording,
             .capturingScreenshot:
            return false
        }
    }
}

private extension CaptureSource {
    func representsSameCaptureSource(as other: CaptureSource) -> Bool {
        guard kind == other.kind else { return false }
        if id == other.id { return true }

        switch kind {
        case .display:
            if let displayID, let otherDisplayID = other.displayID {
                return displayID == otherDisplayID
            }
            return id == other.id
        case .window:
            if windowID != nil || other.windowID != nil {
                return windowID == other.windowID && ownerBundleID == other.ownerBundleID
            }
            return ownerBundleID != nil &&
                ownerBundleID == other.ownerBundleID &&
                !name.isEmpty &&
                name == other.name
        case .area:
            return id == other.id
        }
    }
}

typealias HUDState = CaptureState
