import AVFoundation
import CoreGraphics
import Foundation
import Observation
import SwiftUI

enum CaptureDeviceLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct CaptureOptionsState: Equatable {
    var includeMicrophone = false
    var includeSystemAudio = false
    var includeCamera = false
    var showCursor = true
    var showClicks = false
    var microphoneDevices: [CaptureDeviceInfo] = []
    var cameraDevices: [CaptureDeviceInfo] = []
    var selectedMicrophoneDeviceID: String?
    var selectedCameraDeviceID: String?
    var canChangeOptions = true
    var statusMessage: String?
    var deviceLoadPhase: CaptureDeviceLoadPhase = .idle

    var selectedMicrophoneDeviceName: String {
        guard let selectedMicrophoneDeviceID else {
            return "System Default"
        }
        return microphoneDevices.first(where: { $0.id == selectedMicrophoneDeviceID })?.name
            ?? "Previously Selected (Unavailable)"
    }

    var selectedCameraDeviceName: String {
        guard let selectedCameraDeviceID else {
            return "System Default"
        }
        return cameraDevices.first(where: { $0.id == selectedCameraDeviceID })?.name
            ?? "Previously Selected (Unavailable)"
    }

    var hasAvailableMicrophoneSelection: Bool {
        guard !microphoneDevices.isEmpty else { return false }
        guard let selectedMicrophoneDeviceID else { return true }
        return microphoneDevices.contains { $0.id == selectedMicrophoneDeviceID }
    }

    var hasAvailableCameraSelection: Bool {
        guard !cameraDevices.isEmpty else { return false }
        guard let selectedCameraDeviceID else { return true }
        return cameraDevices.contains { $0.id == selectedCameraDeviceID }
    }

    var recordingOptions: RecordingCaptureOptions {
        RecordingCaptureOptions(
            includeMicrophone: includeMicrophone,
            microphoneDeviceID: includeMicrophone && hasAvailableMicrophoneSelection ? selectedMicrophoneDeviceID : nil,
            includeSystemAudio: includeSystemAudio,
            includeCamera: includeCamera,
            cameraDeviceID: includeCamera && hasAvailableCameraSelection ? selectedCameraDeviceID : nil,
            showCursor: showCursor,
            showClicks: showClicks
        )
    }
}

enum CaptureOptionsEvent: Equatable {
    case availabilityChanged(Bool)
    case microphoneEnabledChanged(Bool)
    case systemAudioChanged(Bool)
    case cameraEnabledChanged(Bool)
    case deviceRefreshStarted
    case refreshDevicesRequested
    case devicesRefreshed(microphones: [CaptureDeviceInfo], cameras: [CaptureDeviceInfo])
    case deviceRefreshFailed(String)
    case systemAudioToggled
    case microphoneSelectionRequested
    case cameraSelectionRequested
    case microphoneSelected(String?)
    case cameraSelected(String?)
    case microphoneDisabled
    case cameraDisabled
    case cameraDisabledForCaptureFailure
    case cursorVisibilityChanged(Bool)
    case clickVisibilityChanged(Bool)
    case statusCleared
}

enum CaptureOptionsEffect: Equatable {
    case refreshDevices
    case showMicrophoneSelector
    case showCameraSelector
    case closeMicrophoneSelector
    case closeCameraSelector
    case setStatusMessage(String)
}

extension CaptureOptionsState {
    mutating func applying(_ event: CaptureOptionsEvent) -> [CaptureOptionsEffect] {
        switch event {
        case .availabilityChanged(let canChange):
            canChangeOptions = canChange
            return []

        case .microphoneEnabledChanged(let isEnabled):
            guard canChangeOptions else { return lockedMutationEffects() }
            includeMicrophone = isEnabled
            return []

        case .systemAudioChanged(let isEnabled):
            guard canChangeOptions else { return lockedMutationEffects() }
            includeSystemAudio = isEnabled
            return []

        case .cameraEnabledChanged(let isEnabled):
            guard canChangeOptions else { return lockedMutationEffects() }
            includeCamera = isEnabled
            if isEnabled && selectedCameraDeviceID == nil {
                selectedCameraDeviceID = cameraDevices.first?.id
            }
            return []

        case .deviceRefreshStarted:
            deviceLoadPhase = .loading
            return []

        case .refreshDevicesRequested:
            return [.refreshDevices]

        case .devicesRefreshed(let microphones, let cameras):
            microphoneDevices = microphones
            cameraDevices = cameras
            deviceLoadPhase = .loaded
            return []

        case .deviceRefreshFailed(let message):
            deviceLoadPhase = .failed(message)
            return []

        case .systemAudioToggled:
            guard canChangeOptions else {
                let message = includeSystemAudio ? "System audio is on for this recording." : "System audio is off for this recording."
                statusMessage = message
                return [.setStatusMessage(message)]
            }
            includeSystemAudio.toggle()
            let message = includeSystemAudio ? "System audio on" : "System audio off"
            statusMessage = message
            return [.setStatusMessage(message)]

        case .microphoneSelectionRequested:
            guard canChangeOptions else { return lockedMutationEffects() }
            return [.showMicrophoneSelector]

        case .cameraSelectionRequested:
            guard canChangeOptions else { return lockedMutationEffects() }
            return [.showCameraSelector]

        case .microphoneSelected(let deviceID):
            guard canChangeOptions else { return lockedMutationEffects() }
            includeMicrophone = true
            selectedMicrophoneDeviceID = deviceID
            let message = "Microphone set to \(selectedMicrophoneDeviceName)"
            statusMessage = message
            return [.setStatusMessage(message), .closeMicrophoneSelector]

        case .cameraSelected(let deviceID):
            guard canChangeOptions else { return lockedMutationEffects() }
            includeCamera = true
            selectedCameraDeviceID = deviceID
            let message = "Camera set to \(selectedCameraDeviceName)"
            statusMessage = message
            return [.setStatusMessage(message), .closeCameraSelector]

        case .microphoneDisabled:
            guard canChangeOptions else { return lockedMutationEffects() }
            includeMicrophone = false
            let message = "Microphone off"
            statusMessage = message
            return [.setStatusMessage(message)]

        case .cameraDisabled:
            guard canChangeOptions else { return lockedMutationEffects() }
            includeCamera = false
            let message = "Camera off"
            statusMessage = message
            return [.setStatusMessage(message)]

        case .cameraDisabledForCaptureFailure:
            includeCamera = false
            return []

        case .cursorVisibilityChanged(let isVisible):
            guard canChangeOptions else { return lockedMutationEffects() }
            showCursor = isVisible
            return []

        case .clickVisibilityChanged(let isVisible):
            guard canChangeOptions else { return lockedMutationEffects() }
            showClicks = isVisible
            return []

        case .statusCleared:
            statusMessage = nil
            return []
        }
    }

    private mutating func lockedMutationEffects() -> [CaptureOptionsEffect] {
        let message = "Recording options are locked while capture is starting."
        statusMessage = message
        return [.setStatusMessage(message)]
    }
}

@Observable
@MainActor
final class CaptureOptionsDriver {
    private(set) var state = CaptureOptionsState()

    @ObservationIgnored private var refreshDevices: () -> (microphones: [CaptureDeviceInfo], cameras: [CaptureDeviceInfo]) = { ([], []) }
    @ObservationIgnored private var requestWindow: (NativeWindowCommandAction) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }
    @ObservationIgnored private var stateWillChange: () -> Void = {}

    func configure(
        refreshDevices: @escaping () -> (microphones: [CaptureDeviceInfo], cameras: [CaptureDeviceInfo]) = { ([], []) },
        requestWindow: @escaping (NativeWindowCommandAction) -> Void = { _ in },
        setStatusMessage: @escaping (String) -> Void = { _ in },
        stateWillChange: @escaping () -> Void = {}
    ) {
        self.refreshDevices = refreshDevices
        self.requestWindow = requestWindow
        self.setStatusMessage = setStatusMessage
        self.stateWillChange = stateWillChange
    }

    func send(_ event: CaptureOptionsEvent) {
        var nextState = state
        let effects = nextState.applying(event)
        if nextState != state {
            stateWillChange()
            state = nextState
        }
        perform(effects)
    }

    func binding(_ keyPath: WritableKeyPath<CaptureOptionsState, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { value in
                switch keyPath {
                case \.includeMicrophone:
                    self.send(.microphoneEnabledChanged(value))
                case \.includeSystemAudio:
                    self.send(.systemAudioChanged(value))
                case \.includeCamera:
                    self.send(.cameraEnabledChanged(value))
                case \.showCursor:
                    self.send(.cursorVisibilityChanged(value))
                case \.showClicks:
                    self.send(.clickVisibilityChanged(value))
                case \.canChangeOptions:
                    self.send(.availabilityChanged(value))
                default:
                    assertionFailure("Unsupported capture-options binding")
                }
            }
        )
    }

    private func perform(_ effects: [CaptureOptionsEffect]) {
        for effect in effects {
            switch effect {
            case .refreshDevices:
                let devices = refreshDevices()
                send(.devicesRefreshed(microphones: devices.microphones, cameras: devices.cameras))
            case .showMicrophoneSelector:
                requestWindow(.showMicrophoneSelector)
            case .showCameraSelector:
                requestWindow(.showCameraSelector)
            case .closeMicrophoneSelector:
                requestWindow(.closeMicrophoneSelector)
            case .closeCameraSelector:
                requestWindow(.closeCameraSelector)
            case .setStatusMessage(let message):
                setStatusMessage(message)
            }
        }
    }
}

enum SourceSelectorLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct SourceSelectorRefreshResult: Equatable {
    var sourceIDs: [String]
    var errorMessage: String?

    static func loaded(sourceIDs: [String]) -> SourceSelectorRefreshResult {
        SourceSelectorRefreshResult(sourceIDs: sourceIDs, errorMessage: nil)
    }
}

struct SourceSelectorState: Equatable {
    var sourceTab: SourceSelectorTab
    var preferredHeight: CGFloat = SourceSelectorWindowMetrics.compactHeight
    var visibleTabs: [SourceSelectorTab]
    var committedSourceID: String?
    var pendingSourceID: String?
    var availableSourceIDs: Set<String> = []
    var loadPhase: SourceSelectorLoadPhase = .idle

    init(sourceTab: SourceSelectorTab = .screens, visibleTabs: [SourceSelectorTab] = SourceSelectorTab.allCases) {
        self.sourceTab = sourceTab
        self.visibleTabs = visibleTabs
    }

    func sources(from allSources: [CaptureSource]) -> [CaptureSource] {
        switch sourceTab {
        case .screens:
            return allSources.filter { $0.kind == .display }
        case .windows:
            return allSources.filter { $0.kind == .window }
        case .area:
            return allSources.filter { $0.kind == .area }
        }
    }

}

enum SourceSelectorEvent: Equatable {
    case visibleTabsChanged([SourceSelectorTab])
    case tabSelected(SourceSelectorTab)
    case preferredSourceKindSynced(CaptureSourceKind?)
    case committedSelectionSynced(String?)
    case sourceSelected(String)
    case sourcesChanged([String])
    case heightMeasured(CGFloat)
    case refreshRequested
    case refreshCompleted(SourceSelectorRefreshResult)
    case cancelRequested
    case drawAreaRequested
}

enum SourceSelectorEffect: Equatable {
    case refreshSources
    case cancel
    case select(String)
    case drawArea
}

extension SourceSelectorState {
    mutating func applying(_ event: SourceSelectorEvent) -> [SourceSelectorEffect] {
        switch event {
        case .visibleTabsChanged(let tabs):
            visibleTabs = tabs
            if !visibleTabs.contains(sourceTab), let firstTab = visibleTabs.first {
                sourceTab = firstTab
            }
            return []

        case .tabSelected(let tab):
            guard visibleTabs.contains(tab) else { return [] }
            sourceTab = tab
            return []

        case .preferredSourceKindSynced(let kind):
            guard let kind else { return [] }
            let nextTab = SourceSelectorTab(sourceKind: kind)
            sourceTab = visibleTabs.contains(nextTab) ? nextTab : sourceTab
            return []

        case .committedSelectionSynced(let sourceID):
            committedSourceID = sourceID
            pendingSourceID = sourceID
            return []

        case .sourceSelected(let sourceID):
            guard availableSourceIDs.contains(sourceID) else { return [] }
            committedSourceID = sourceID
            pendingSourceID = sourceID
            return [.select(sourceID)]

        case .sourcesChanged(let sourceIDs):
            availableSourceIDs = Set(sourceIDs)
            return []

        case .heightMeasured(let cardHeight):
            let nextHeight = ceil(cardHeight + (SourceSelectorWindowMetrics.outerPadding * 2))
            guard abs(preferredHeight - nextHeight) > 0.5 else { return [] }
            preferredHeight = nextHeight
            return []

        case .refreshRequested:
            loadPhase = .loading
            return [.refreshSources]
        case .refreshCompleted(let result):
            let sourceIDs = Set(result.sourceIDs)
            availableSourceIDs = sourceIDs
            if let pendingSourceID, !sourceIDs.contains(pendingSourceID) {
                self.pendingSourceID = nil
            }
            if let committedSourceID, !sourceIDs.contains(committedSourceID) {
                self.committedSourceID = nil
            }
            if let errorMessage = result.errorMessage {
                loadPhase = .failed(errorMessage)
            } else {
                loadPhase = .loaded
            }
            return []
        case .cancelRequested:
            pendingSourceID = committedSourceID
            return [.cancel]
        case .drawAreaRequested:
            return [.drawArea]
        }
    }
}

@Observable
@MainActor
final class SourceSelectorDriver {
    private(set) var state: SourceSelectorState

    @ObservationIgnored private var refreshSources: () async -> SourceSelectorRefreshResult = { .loaded(sourceIDs: []) }
    @ObservationIgnored private var cancel: () -> Void = {}
    @ObservationIgnored private var select: (String) -> Void = { _ in }
    @ObservationIgnored private var drawArea: () -> Void = {}
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(sourceTab: SourceSelectorTab = .screens, visibleTabs: [SourceSelectorTab] = SourceSelectorTab.allCases) {
        state = SourceSelectorState(sourceTab: sourceTab, visibleTabs: visibleTabs)
    }

    func configure(
        refreshSources: @escaping () async -> SourceSelectorRefreshResult = { .loaded(sourceIDs: []) },
        cancel: @escaping () -> Void = {},
        select: @escaping (String) -> Void = { _ in },
        drawArea: @escaping () -> Void = {}
    ) {
        self.refreshSources = refreshSources
        self.cancel = cancel
        self.select = select
        self.drawArea = drawArea
    }

    func send(_ event: SourceSelectorEvent) {
        perform(state.applying(event))
    }

    var sourceTabBinding: Binding<SourceSelectorTab> {
        Binding(
            get: { self.state.sourceTab },
            set: { self.send(.tabSelected($0)) }
        )
    }

    private func perform(_ effects: [SourceSelectorEffect]) {
        for effect in effects {
            switch effect {
            case .refreshSources:
                refreshTask?.cancel()
                refreshTask = Task { [weak self] in
                    guard let self else { return }
                    let result = await refreshSources()
                    guard !Task.isCancelled else { return }
                    send(.refreshCompleted(result))
                    refreshTask = nil
                }
            case .cancel:
                refreshTask?.cancel()
                refreshTask = nil
                cancel()
            case .select(let sourceID):
                refreshTask?.cancel()
                refreshTask = nil
                select(sourceID)
            case .drawArea:
                refreshTask?.cancel()
                refreshTask = nil
                drawArea()
            }
        }
    }
}

struct OnboardingMachineState: Equatable {
    var screenRecordingPermissionState: ScreenRecordingPermissionState
    var accessibilityPermissionState: AccessibilityPermissionState
    var statusMessage = ""

    var canContinue: Bool {
        screenRecordingPermissionState == .granted
    }
}

enum OnboardingEvent: Equatable {
    case appeared
    case appBecameActive
    case timerTicked
    case screenPermissionButtonTapped
    case accessibilityPermissionButtonTapped
    case permissionsRefreshed(screen: ScreenRecordingPermissionState, accessibility: AccessibilityPermissionState)
    case screenPermissionRequested(ScreenRecordingPermissionRequestOutcome)
    case accessibilityPermissionRequested(AccessibilityPermissionRequestOutcome)
    case continueRequested
    case completed
}

enum OnboardingEffect: Equatable {
    case refreshPermissions
    case requestScreenPermission
    case requestAccessibilityPermission
    case openScreenRecordingSettings
    case openAccessibilitySettings
    case completeOnboarding
}

extension OnboardingMachineState {
    mutating func applying(_ event: OnboardingEvent) -> [OnboardingEffect] {
        switch event {
        case .appeared, .appBecameActive, .timerTicked:
            return [.refreshPermissions]

        case .screenPermissionButtonTapped:
            return [.requestScreenPermission]

        case .accessibilityPermissionButtonTapped:
            return [.requestAccessibilityPermission]

        case .permissionsRefreshed(let screen, let accessibility):
            screenRecordingPermissionState = screen
            accessibilityPermissionState = accessibility
            if canContinue && statusMessage.localizedCaseInsensitiveContains("required") {
                statusMessage = ""
            }
            return []

        case .screenPermissionRequested(let outcome):
            switch outcome {
            case .granted:
                screenRecordingPermissionState = .granted
                statusMessage = "Screen Recording is enabled."
                return [.refreshPermissions]
            case .promptAlreadyShown:
                screenRecordingPermissionState = .requestAlreadyShown
                statusMessage = "Enable Screen Recording in System Settings, then quit and reopen Open Recorder if macOS asks."
                return [.openScreenRecordingSettings, .refreshPermissions]
            case .promptShownWithoutGrant:
                screenRecordingPermissionState = .requestAlreadyShown
                statusMessage = "Enable Screen Recording in System Settings, then quit and reopen Open Recorder if macOS asks."
                return [.refreshPermissions]
            }

        case .accessibilityPermissionRequested(let outcome):
            switch outcome {
            case .granted:
                accessibilityPermissionState = .granted
                statusMessage = "Optional Accessibility enhancements are enabled."
                return [.refreshPermissions]
            case .promptAlreadyShown:
                accessibilityPermissionState = .requestAlreadyShown
                statusMessage = "Optional: enable Accessibility in System Settings for shortcuts and additional cursor details."
                return [.openAccessibilitySettings, .refreshPermissions]
            case .promptShownWithoutGrant:
                accessibilityPermissionState = .requestAlreadyShown
                statusMessage = "Optional: enable Accessibility in System Settings for shortcuts and additional cursor details."
                return [.refreshPermissions]
            }

        case .continueRequested:
            guard canContinue else {
                statusMessage = "Screen Recording permission is required before continuing."
                return []
            }
            statusMessage = ""
            return [.completeOnboarding]

        case .completed:
            statusMessage = ""
            return []
        }
    }
}

@Observable
@MainActor
final class OnboardingDriver {
    private(set) var state: OnboardingMachineState

    @ObservationIgnored private var currentPermissions: () -> (screen: ScreenRecordingPermissionState, accessibility: AccessibilityPermissionState)
    @ObservationIgnored private var requestScreenPermission: () -> ScreenRecordingPermissionRequestOutcome
    @ObservationIgnored private var requestAccessibilityPermission: () -> AccessibilityPermissionRequestOutcome
    @ObservationIgnored private var openScreenRecordingSettings: () -> Void
    @ObservationIgnored private var openAccessibilitySettings: () -> Void
    @ObservationIgnored private var completeOnboarding: () -> Bool
    @ObservationIgnored private var stateWillChange: () -> Void = {}

    init(
        screenRecordingPermissionState: ScreenRecordingPermissionState,
        accessibilityPermissionState: AccessibilityPermissionState
    ) {
        state = OnboardingMachineState(
            screenRecordingPermissionState: screenRecordingPermissionState,
            accessibilityPermissionState: accessibilityPermissionState
        )
        currentPermissions = { (screenRecordingPermissionState, accessibilityPermissionState) }
        requestScreenPermission = { .promptAlreadyShown }
        requestAccessibilityPermission = { .promptAlreadyShown }
        openScreenRecordingSettings = {}
        openAccessibilitySettings = {}
        completeOnboarding = { false }
    }

    func configure(
        currentPermissions: @escaping () -> (screen: ScreenRecordingPermissionState, accessibility: AccessibilityPermissionState),
        requestScreenPermission: @escaping () -> ScreenRecordingPermissionRequestOutcome,
        requestAccessibilityPermission: @escaping () -> AccessibilityPermissionRequestOutcome,
        openScreenRecordingSettings: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        completeOnboarding: @escaping () -> Bool,
        stateWillChange: @escaping () -> Void = {}
    ) {
        self.currentPermissions = currentPermissions
        self.requestScreenPermission = requestScreenPermission
        self.requestAccessibilityPermission = requestAccessibilityPermission
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.openAccessibilitySettings = openAccessibilitySettings
        self.completeOnboarding = completeOnboarding
        self.stateWillChange = stateWillChange
    }

    func send(_ event: OnboardingEvent) {
        var nextState = state
        let effects = nextState.applying(event)
        if nextState != state {
            stateWillChange()
            state = nextState
        }
        perform(effects)
    }

    private func perform(_ effects: [OnboardingEffect]) {
        for effect in effects {
            switch effect {
            case .refreshPermissions:
                let permissions = currentPermissions()
                send(.permissionsRefreshed(screen: permissions.screen, accessibility: permissions.accessibility))
            case .requestScreenPermission:
                send(.screenPermissionRequested(requestScreenPermission()))
            case .requestAccessibilityPermission:
                send(.accessibilityPermissionRequested(requestAccessibilityPermission()))
            case .openScreenRecordingSettings:
                openScreenRecordingSettings()
            case .openAccessibilitySettings:
                openAccessibilitySettings()
            case .completeOnboarding:
                if completeOnboarding() {
                    send(.completed)
                }
            }
        }
    }
}

struct SettingsMachineState: Equatable {
    var createZoomsAutomatically: Bool
    var autoZoomAnimationPreset: TimelineZoomAnimationPreset = .balanced
    var shortcuts: ShortcutPreferences = .defaultPreferences
    var statusMessage = ""
    var isRefreshingService = false
}

enum SettingsEvent: Equatable {
    case serviceRefreshRequested
    case serviceRefreshStarted
    case serviceRefreshSucceeded
    case serviceRefreshFailed(String)
    case autoZoomPreferenceSynced(Bool)
    case autoZoomPreferenceChanged(Bool)
    case autoZoomAnimationPresetSynced(TimelineZoomAnimationPreset)
    case autoZoomAnimationPresetChanged(TimelineZoomAnimationPreset)
    case shortcutsSynced(ShortcutPreferences)
    case shortcutItemChanged(ShortcutItem)
    case shortcutsResetToDefaults
    case folderOpenRequested(String?)
    case screenRecordingSettingsRequested
    case accessibilitySettingsRequested
    case onboardingReviewRequested
}

enum SettingsEffect: Equatable {
    case refreshService
    case persistAutoZoomPreference(Bool)
    case persistAutoZoomAnimationPreset(TimelineZoomAnimationPreset)
    case persistShortcuts(ShortcutPreferences)
    case openFolder(String)
    case openScreenRecordingSettings
    case openAccessibilitySettings
    case showOnboarding
}

extension SettingsMachineState {
    mutating func applying(_ event: SettingsEvent) -> [SettingsEffect] {
        switch event {
        case .serviceRefreshRequested:
            isRefreshingService = true
            statusMessage = "Checking service..."
            return [.refreshService]

        case .serviceRefreshStarted:
            isRefreshingService = true
            statusMessage = "Checking service..."
            return []

        case .serviceRefreshSucceeded:
            isRefreshingService = false
            statusMessage = "Rust service ready"
            return []

        case .serviceRefreshFailed(let message):
            isRefreshingService = false
            statusMessage = message
            return []

        case .autoZoomPreferenceSynced(let value):
            createZoomsAutomatically = value
            return []

        case .autoZoomPreferenceChanged(let value):
            guard createZoomsAutomatically != value else { return [] }
            createZoomsAutomatically = value
            return [.persistAutoZoomPreference(value)]

        case .autoZoomAnimationPresetSynced(let preset):
            autoZoomAnimationPreset = preset
            return []

        case .autoZoomAnimationPresetChanged(let preset):
            guard autoZoomAnimationPreset != preset else { return [] }
            autoZoomAnimationPreset = preset
            return [.persistAutoZoomAnimationPreset(preset)]

        case .shortcutsSynced(let shortcuts):
            self.shortcuts = shortcuts
            return []

        case .shortcutItemChanged(let item):
            shortcuts.setItem(item)
            return [.persistShortcuts(shortcuts)]

        case .shortcutsResetToDefaults:
            shortcuts = .defaultPreferences
            return [.persistShortcuts(shortcuts)]

        case .folderOpenRequested(let path):
            guard let path else { return [] }
            return [.openFolder(path)]

        case .screenRecordingSettingsRequested:
            return [.openScreenRecordingSettings]

        case .accessibilitySettingsRequested:
            return [.openAccessibilitySettings]

        case .onboardingReviewRequested:
            return [.showOnboarding]
        }
    }
}

@Observable
@MainActor
final class SettingsDriver {
    private(set) var state: SettingsMachineState

    @ObservationIgnored private var refreshService: () -> Void = {}
    @ObservationIgnored private var persistAutoZoomPreference: (Bool) -> Void = { _ in }
    @ObservationIgnored private var persistAutoZoomAnimationPreset: (TimelineZoomAnimationPreset) -> Void = { _ in }
    @ObservationIgnored private var persistShortcuts: (ShortcutPreferences) -> Void = { _ in }
    @ObservationIgnored private var openFolder: (String) -> Void = { _ in }
    @ObservationIgnored private var openScreenRecordingSettings: () -> Void = {}
    @ObservationIgnored private var openAccessibilitySettings: () -> Void = {}
    @ObservationIgnored private var showOnboarding: () -> Void = {}
    @ObservationIgnored private var stateWillChange: () -> Void = {}

    init(
        createZoomsAutomatically: Bool,
        autoZoomAnimationPreset: TimelineZoomAnimationPreset = .balanced,
        shortcuts: ShortcutPreferences = .defaultPreferences
    ) {
        state = SettingsMachineState(
            createZoomsAutomatically: createZoomsAutomatically,
            autoZoomAnimationPreset: autoZoomAnimationPreset,
            shortcuts: shortcuts
        )
    }

    func configure(
        refreshService: @escaping () -> Void = {},
        persistAutoZoomPreference: @escaping (Bool) -> Void = { _ in },
        persistAutoZoomAnimationPreset: @escaping (TimelineZoomAnimationPreset) -> Void = { _ in },
        persistShortcuts: @escaping (ShortcutPreferences) -> Void = { _ in },
        openFolder: @escaping (String) -> Void = { _ in },
        openScreenRecordingSettings: @escaping () -> Void = {},
        openAccessibilitySettings: @escaping () -> Void = {},
        showOnboarding: @escaping () -> Void = {},
        stateWillChange: @escaping () -> Void = {}
    ) {
        self.refreshService = refreshService
        self.persistAutoZoomPreference = persistAutoZoomPreference
        self.persistAutoZoomAnimationPreset = persistAutoZoomAnimationPreset
        self.persistShortcuts = persistShortcuts
        self.openFolder = openFolder
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.openAccessibilitySettings = openAccessibilitySettings
        self.showOnboarding = showOnboarding
        self.stateWillChange = stateWillChange
    }

    func send(_ event: SettingsEvent) {
        var nextState = state
        let effects = nextState.applying(event)
        if nextState != state {
            stateWillChange()
            state = nextState
        }
        perform(effects)
    }

    var autoZoomBinding: Binding<Bool> {
        Binding(
            get: { self.state.createZoomsAutomatically },
            set: { self.send(.autoZoomPreferenceChanged($0)) }
        )
    }

    var autoZoomAnimationPresetBinding: Binding<TimelineZoomAnimationPreset> {
        Binding(
            get: { self.state.autoZoomAnimationPreset },
            set: { self.send(.autoZoomAnimationPresetChanged($0)) }
        )
    }

    func shortcutBinding(for action: CaptureShortcutAction) -> Binding<ShortcutItem> {
        Binding(
            get: { self.state.shortcuts.item(for: action) },
            set: { self.send(.shortcutItemChanged($0)) }
        )
    }

    private func perform(_ effects: [SettingsEffect]) {
        for effect in effects {
            switch effect {
            case .refreshService:
                refreshService()
            case .persistAutoZoomPreference(let value):
                persistAutoZoomPreference(value)
            case .persistAutoZoomAnimationPreset(let preset):
                persistAutoZoomAnimationPreset(preset)
            case .persistShortcuts(let shortcuts):
                persistShortcuts(shortcuts)
            case .openFolder(let path):
                openFolder(path)
            case .openScreenRecordingSettings:
                openScreenRecordingSettings()
            case .openAccessibilitySettings:
                openAccessibilitySettings()
            case .showOnboarding:
                showOnboarding()
            }
        }
    }
}
