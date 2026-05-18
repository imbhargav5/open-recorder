import AVFoundation
import CoreGraphics
import Foundation
import Observation
import SwiftUI

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

    var selectedMicrophoneDeviceName: String {
        guard let selectedMicrophoneDeviceID,
              let device = microphoneDevices.first(where: { $0.id == selectedMicrophoneDeviceID }) else {
            return "System Default"
        }
        return device.name
    }

    var selectedCameraDeviceName: String {
        guard let selectedCameraDeviceID,
              let device = cameraDevices.first(where: { $0.id == selectedCameraDeviceID }) else {
            return "System Default"
        }
        return device.name
    }

    var recordingOptions: RecordingCaptureOptions {
        RecordingCaptureOptions(
            includeMicrophone: includeMicrophone,
            microphoneDeviceID: includeMicrophone ? selectedMicrophoneDeviceID : nil,
            includeSystemAudio: includeSystemAudio,
            includeCamera: includeCamera,
            cameraDeviceID: includeCamera ? selectedCameraDeviceID : nil,
            showCursor: showCursor,
            showClicks: showClicks
        )
    }
}

enum CaptureOptionsEvent: Equatable {
    case availabilityChanged(Bool)
    case devicesRefreshed(microphones: [CaptureDeviceInfo], cameras: [CaptureDeviceInfo])
    case systemAudioToggled
    case microphoneSelectionRequested
    case cameraSelectionRequested
    case microphoneSelected(String?)
    case cameraSelected(String?)
    case microphoneDisabled
    case cameraDisabled
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

        case .devicesRefreshed(let microphones, let cameras):
            microphoneDevices = microphones
            cameraDevices = cameras
            if let selectedMicrophoneDeviceID,
               !microphones.contains(where: { $0.id == selectedMicrophoneDeviceID }) {
                self.selectedMicrophoneDeviceID = nil
            }
            if let selectedCameraDeviceID,
               !cameras.contains(where: { $0.id == selectedCameraDeviceID }) {
                self.selectedCameraDeviceID = nil
            }
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
            return [.refreshDevices, .showMicrophoneSelector]

        case .cameraSelectionRequested:
            return [.refreshDevices, .showCameraSelector]

        case .microphoneSelected(let deviceID):
            includeMicrophone = true
            selectedMicrophoneDeviceID = deviceID
            let message = "Microphone set to \(selectedMicrophoneDeviceName)"
            statusMessage = message
            return [.setStatusMessage(message), .closeMicrophoneSelector]

        case .cameraSelected(let deviceID):
            includeCamera = true
            selectedCameraDeviceID = deviceID
            let message = "Camera set to \(selectedCameraDeviceName)"
            statusMessage = message
            return [.setStatusMessage(message), .closeCameraSelector]

        case .microphoneDisabled:
            includeMicrophone = false
            let message = "Microphone off"
            statusMessage = message
            return [.setStatusMessage(message)]

        case .cameraDisabled:
            includeCamera = false
            let message = "Camera off"
            statusMessage = message
            return [.setStatusMessage(message)]

        case .cursorVisibilityChanged(let isVisible):
            showCursor = isVisible
            return []

        case .clickVisibilityChanged(let isVisible):
            showClicks = isVisible
            return []

        case .statusCleared:
            statusMessage = nil
            return []
        }
    }
}

@Observable
@MainActor
final class CaptureOptionsDriver {
    var state = CaptureOptionsState()

    @ObservationIgnored private var refreshDevices: () -> (microphones: [CaptureDeviceInfo], cameras: [CaptureDeviceInfo]) = { ([], []) }
    @ObservationIgnored private var requestWindow: (NativeWindowCommandAction) -> Void = { _ in }
    @ObservationIgnored private var setStatusMessage: (String) -> Void = { _ in }

    func configure(
        refreshDevices: @escaping () -> (microphones: [CaptureDeviceInfo], cameras: [CaptureDeviceInfo]) = { ([], []) },
        requestWindow: @escaping (NativeWindowCommandAction) -> Void = { _ in },
        setStatusMessage: @escaping (String) -> Void = { _ in }
    ) {
        self.refreshDevices = refreshDevices
        self.requestWindow = requestWindow
        self.setStatusMessage = setStatusMessage
    }

    func send(_ event: CaptureOptionsEvent) {
        perform(state.applying(event))
    }

    func binding(_ keyPath: WritableKeyPath<CaptureOptionsState, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { value in
                switch keyPath {
                case \.showCursor:
                    self.send(.cursorVisibilityChanged(value))
                case \.showClicks:
                    self.send(.clickVisibilityChanged(value))
                default:
                    self.state[keyPath: keyPath] = value
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

struct SourceSelectorState: Equatable {
    var sourceTab: SourceSelectorTab
    var preferredHeight: CGFloat = SourceSelectorWindowMetrics.compactHeight
    var visibleTabs: [SourceSelectorTab]

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
    case tabSelected(SourceSelectorTab)
    case preferredSourceKindSynced(CaptureSourceKind?)
    case heightMeasured(CGFloat)
    case refreshRequested
    case cancelRequested
    case shareRequested
    case drawAreaRequested
}

enum SourceSelectorEffect: Equatable {
    case refreshSources
    case cancel
    case share
    case drawArea
}

extension SourceSelectorState {
    mutating func applying(_ event: SourceSelectorEvent) -> [SourceSelectorEffect] {
        switch event {
        case .tabSelected(let tab):
            guard visibleTabs.contains(tab) else { return [] }
            sourceTab = tab
            return []

        case .preferredSourceKindSynced(let kind):
            guard let kind else { return [] }
            let nextTab = SourceSelectorTab(sourceKind: kind)
            sourceTab = visibleTabs.contains(nextTab) ? nextTab : sourceTab
            return []

        case .heightMeasured(let cardHeight):
            let nextHeight = ceil(cardHeight + (SourceSelectorWindowMetrics.outerPadding * 2))
            guard abs(preferredHeight - nextHeight) > 0.5 else { return [] }
            preferredHeight = nextHeight
            return []

        case .refreshRequested:
            return [.refreshSources]
        case .cancelRequested:
            return [.cancel]
        case .shareRequested:
            return [.share]
        case .drawAreaRequested:
            return [.drawArea]
        }
    }
}

@Observable
@MainActor
final class SourceSelectorDriver {
    var state: SourceSelectorState

    @ObservationIgnored private var refreshSources: () -> Void = {}
    @ObservationIgnored private var cancel: () -> Void = {}
    @ObservationIgnored private var share: () -> Void = {}
    @ObservationIgnored private var drawArea: () -> Void = {}

    init(sourceTab: SourceSelectorTab = .screens, visibleTabs: [SourceSelectorTab] = SourceSelectorTab.allCases) {
        state = SourceSelectorState(sourceTab: sourceTab, visibleTabs: visibleTabs)
    }

    func configure(
        refreshSources: @escaping () -> Void = {},
        cancel: @escaping () -> Void = {},
        share: @escaping () -> Void = {},
        drawArea: @escaping () -> Void = {}
    ) {
        self.refreshSources = refreshSources
        self.cancel = cancel
        self.share = share
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
                refreshSources()
            case .cancel:
                cancel()
            case .share:
                share()
            case .drawArea:
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
                statusMessage = "Accessibility access is enabled."
                return [.refreshPermissions]
            case .promptAlreadyShown:
                accessibilityPermissionState = .requestAlreadyShown
                statusMessage = "Enable Accessibility access in System Settings to capture shortcuts and cursor details."
                return [.openAccessibilitySettings, .refreshPermissions]
            case .promptShownWithoutGrant:
                accessibilityPermissionState = .requestAlreadyShown
                statusMessage = "Enable Accessibility access in System Settings to capture shortcuts and cursor details."
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
    var state: OnboardingMachineState

    @ObservationIgnored private var currentPermissions: () -> (screen: ScreenRecordingPermissionState, accessibility: AccessibilityPermissionState)
    @ObservationIgnored private var requestScreenPermission: () -> ScreenRecordingPermissionRequestOutcome
    @ObservationIgnored private var requestAccessibilityPermission: () -> AccessibilityPermissionRequestOutcome
    @ObservationIgnored private var openScreenRecordingSettings: () -> Void
    @ObservationIgnored private var openAccessibilitySettings: () -> Void
    @ObservationIgnored private var completeOnboarding: () -> Bool

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
        completeOnboarding: @escaping () -> Bool
    ) {
        self.currentPermissions = currentPermissions
        self.requestScreenPermission = requestScreenPermission
        self.requestAccessibilityPermission = requestAccessibilityPermission
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.openAccessibilitySettings = openAccessibilitySettings
        self.completeOnboarding = completeOnboarding
    }

    func send(_ event: OnboardingEvent) {
        perform(state.applying(event))
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
    var serviceHealth: HealthPayload?
    var paths: AppPaths?
    var createZoomsAutomatically: Bool
    var statusMessage = ""
    var isRefreshingService = false
}

enum SettingsEvent: Equatable {
    case appeared(serviceHealth: HealthPayload?, paths: AppPaths?)
    case serviceRefreshRequested
    case serviceRefreshSucceeded(serviceHealth: HealthPayload?, paths: AppPaths?)
    case serviceRefreshFailed(String)
    case autoZoomPreferenceSynced(Bool)
    case autoZoomPreferenceChanged(Bool)
    case folderOpenRequested(String?)
    case screenRecordingSettingsRequested
    case accessibilitySettingsRequested
    case onboardingReviewRequested
}

enum SettingsEffect: Equatable {
    case refreshService
    case persistAutoZoomPreference(Bool)
    case openFolder(String)
    case openScreenRecordingSettings
    case openAccessibilitySettings
    case showOnboarding
}

extension SettingsMachineState {
    mutating func applying(_ event: SettingsEvent) -> [SettingsEffect] {
        switch event {
        case .appeared(let serviceHealth, let paths):
            self.serviceHealth = serviceHealth
            self.paths = paths
            return []

        case .serviceRefreshRequested:
            isRefreshingService = true
            statusMessage = "Checking service..."
            return [.refreshService]

        case .serviceRefreshSucceeded(let serviceHealth, let paths):
            isRefreshingService = false
            self.serviceHealth = serviceHealth
            self.paths = paths
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
    var state: SettingsMachineState

    @ObservationIgnored private var refreshService: () -> Void = {}
    @ObservationIgnored private var persistAutoZoomPreference: (Bool) -> Void = { _ in }
    @ObservationIgnored private var openFolder: (String) -> Void = { _ in }
    @ObservationIgnored private var openScreenRecordingSettings: () -> Void = {}
    @ObservationIgnored private var openAccessibilitySettings: () -> Void = {}
    @ObservationIgnored private var showOnboarding: () -> Void = {}

    init(createZoomsAutomatically: Bool) {
        state = SettingsMachineState(createZoomsAutomatically: createZoomsAutomatically)
    }

    func configure(
        refreshService: @escaping () -> Void = {},
        persistAutoZoomPreference: @escaping (Bool) -> Void = { _ in },
        openFolder: @escaping (String) -> Void = { _ in },
        openScreenRecordingSettings: @escaping () -> Void = {},
        openAccessibilitySettings: @escaping () -> Void = {},
        showOnboarding: @escaping () -> Void = {}
    ) {
        self.refreshService = refreshService
        self.persistAutoZoomPreference = persistAutoZoomPreference
        self.openFolder = openFolder
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.openAccessibilitySettings = openAccessibilitySettings
        self.showOnboarding = showOnboarding
    }

    func send(_ event: SettingsEvent) {
        perform(state.applying(event))
    }

    var autoZoomBinding: Binding<Bool> {
        Binding(
            get: { self.state.createZoomsAutomatically },
            set: { self.send(.autoZoomPreferenceChanged($0)) }
        )
    }

    private func perform(_ effects: [SettingsEffect]) {
        for effect in effects {
            switch effect {
            case .refreshService:
                refreshService()
            case .persistAutoZoomPreference(let value):
                persistAutoZoomPreference(value)
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
