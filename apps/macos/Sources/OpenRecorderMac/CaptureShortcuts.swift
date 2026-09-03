import AppKit
import Carbon
import Foundation

public enum CaptureShortcutAction: String, CaseIterable, Identifiable, Codable, Equatable, Hashable, Sendable {
    case deviceScreenshot = "deviceScreenshot"
    case dragScreenshot = "dragScreenshot"
    case deviceScreenRecord = "deviceScreenRecord"
    case dragScreenRecord = "dragScreenRecord"
    case toggleRecording = "toggleRecording"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deviceScreenshot: "Device Screenshot"
        case .dragScreenshot: "Drag Screenshot"
        case .deviceScreenRecord: "Device Screen Record"
        case .dragScreenRecord: "Drag Screen Record"
        case .toggleRecording: "Toggle Recording"
        }
    }

    public var subtitle: String {
        switch self {
        case .deviceScreenshot: "Capture full screen instantly"
        case .dragScreenshot: "Select and capture custom area"
        case .deviceScreenRecord: "Open screen recorder with full screen selected"
        case .dragScreenRecord: "Select area to record with Open Recorder"
        case .toggleRecording: "Start or stop active recording"
        }
    }

    public var defaultKeyCombination: KeyCombination {
        switch self {
        case .deviceScreenshot:
            return KeyCombination(keyCode: UInt32(kVK_ANSI_3), modifiers: [.option, .shift])
        case .dragScreenshot:
            return KeyCombination(keyCode: UInt32(kVK_ANSI_4), modifiers: [.option, .shift])
        case .deviceScreenRecord:
            return KeyCombination(keyCode: UInt32(kVK_ANSI_5), modifiers: [.option, .shift])
        case .dragScreenRecord:
            return KeyCombination(keyCode: UInt32(kVK_ANSI_6), modifiers: [.option, .shift])
        case .toggleRecording:
            return KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option, .shift])
        }
    }
}

public struct ShortcutModifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let shift = ShortcutModifiers(rawValue: 1 << 1)
    public static let option = ShortcutModifiers(rawValue: 1 << 2)
    public static let control = ShortcutModifiers(rawValue: 1 << 3)

    public var displayString: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []
        if eventModifierFlags.contains(.command) { modifiers.insert(.command) }
        if eventModifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventModifierFlags.contains(.option) { modifiers.insert(.option) }
        if eventModifierFlags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}

public struct KeyCombination: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers

    public var id: String { displayString }

    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        let modString = modifiers.displayString
        let keyString = KeyCombination.keyString(for: keyCode)
        return "\(modString)\(keyString)"
    }

    public var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    public static func keyString(for keyCode: UInt32) -> String {
        keyLabel(for: keyCode) ?? "Key(\(keyCode))"
    }

    static func keyLabel(for keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_KeypadDecimal: return "⌨."
        case kVK_ANSI_KeypadMultiply: return "⌨×"
        case kVK_ANSI_KeypadPlus: return "⌨+"
        case kVK_ANSI_KeypadClear: return "⌨Clear"
        case kVK_ANSI_KeypadDivide: return "⌨÷"
        case kVK_ANSI_KeypadEnter: return "⌨↩"
        case kVK_ANSI_KeypadMinus: return "⌨−"
        case kVK_ANSI_KeypadEquals: return "⌨="
        case kVK_ANSI_Keypad0: return "⌨0"
        case kVK_ANSI_Keypad1: return "⌨1"
        case kVK_ANSI_Keypad2: return "⌨2"
        case kVK_ANSI_Keypad3: return "⌨3"
        case kVK_ANSI_Keypad4: return "⌨4"
        case kVK_ANSI_Keypad5: return "⌨5"
        case kVK_ANSI_Keypad6: return "⌨6"
        case kVK_ANSI_Keypad7: return "⌨7"
        case kVK_ANSI_Keypad8: return "⌨8"
        case kVK_ANSI_Keypad9: return "⌨9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Help: return "Help"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default: return nil
        }
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
             kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            true
        default:
            false
        }
    }
}

struct ShortcutCapturedKey: Equatable {
    var combination: KeyCombination
    var charactersIgnoringModifiers: String

    init(combination: KeyCombination, charactersIgnoringModifiers: String) {
        self.combination = combination
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }

    init(event: NSEvent) {
        combination = KeyCombination(
            keyCode: UInt32(event.keyCode),
            modifiers: ShortcutModifiers(eventModifierFlags: event.modifierFlags)
        )
        charactersIgnoringModifiers = event.charactersIgnoringModifiers ?? event.characters ?? ""
    }
}

enum ShortcutCaptureValidationError: Equatable {
    case unsupportedKey
    case missingRequiredModifier
    case duplicate(CaptureShortcutAction)
    case applicationMenu(String)
    case unavailable

    var message: String {
        switch self {
        case .unsupportedKey:
            "That key cannot be used as a global shortcut."
        case .missingRequiredModifier:
            "Add Command, Control, or Option. Function keys can be used on their own."
        case .duplicate(let action):
            "Already used by \(action.title)."
        case .applicationMenu(let title):
            "Already used by the \(title) menu command."
        case .unavailable:
            "That shortcut is reserved by macOS or another application."
        }
    }
}

enum ShortcutCapturePolicy {
    static func isCancelKey(_ keyCode: UInt32) -> Bool {
        keyCode == UInt32(kVK_Escape)
    }

    static func validationError(for combination: KeyCombination) -> ShortcutCaptureValidationError? {
        guard !isCancelKey(combination.keyCode),
              KeyCombination.keyLabel(for: combination.keyCode) != nil else {
            return .unsupportedKey
        }

        if KeyCombination.isFunctionKey(combination.keyCode) {
            return nil
        }

        let requiredModifiers: ShortcutModifiers = [.command, .control, .option]
        guard !combination.modifiers.intersection(requiredModifiers).isEmpty else {
            return .missingRequiredModifier
        }
        return nil
    }
}

struct ShortcutRecorderSession: Equatable {
    enum Phase: Equatable {
        case idle
        case recording(CaptureShortcutAction)
        case awaitingRelease(CaptureShortcutAction, keyCode: UInt32)
    }

    private(set) var phase: Phase = .idle
    private(set) var previewModifiers: ShortcutModifiers = []
    private(set) var errorMessage: String?

    var activeAction: CaptureShortcutAction? {
        switch phase {
        case .idle: nil
        case .recording(let action), .awaitingRelease(let action, _): action
        }
    }

    var isActive: Bool { activeAction != nil }

    func isRecording(_ action: CaptureShortcutAction) -> Bool {
        activeAction == action
    }

    func isAwaitingRelease(_ action: CaptureShortcutAction) -> Bool {
        guard case .awaitingRelease(let activeAction, _) = phase else { return false }
        return activeAction == action
    }

    mutating func begin(_ action: CaptureShortcutAction) {
        phase = .recording(action)
        previewModifiers = []
        errorMessage = nil
    }

    mutating func updateModifiers(_ modifiers: ShortcutModifiers) {
        guard case .recording = phase else { return }
        previewModifiers = modifiers
    }

    mutating func reject(_ error: ShortcutCaptureValidationError) {
        guard case .recording = phase else { return }
        errorMessage = error.message
    }

    mutating func accept(_ combination: KeyCombination) {
        guard case .recording(let action) = phase else { return }
        phase = .awaitingRelease(action, keyCode: combination.keyCode)
        previewModifiers = combination.modifiers
        errorMessage = nil
    }

    mutating func completeKeyRelease(_ keyCode: UInt32) -> Bool {
        guard case .awaitingRelease(_, let expectedKeyCode) = phase,
              expectedKeyCode == keyCode else {
            return false
        }
        cancel()
        return true
    }

    mutating func cancel() {
        phase = .idle
        previewModifiers = []
        errorMessage = nil
    }
}

public struct ShortcutItem: Codable, Equatable, Identifiable, Sendable {
    public var id: CaptureShortcutAction
    public var isEnabled: Bool
    public var keyCombination: KeyCombination

    public init(id: CaptureShortcutAction, isEnabled: Bool = true, keyCombination: KeyCombination) {
        self.id = id
        self.isEnabled = isEnabled
        self.keyCombination = keyCombination
    }
}

public struct ShortcutPreferences: Codable, Equatable, Sendable {
    public var shortcuts: [CaptureShortcutAction: ShortcutItem]

    public init(shortcuts: [CaptureShortcutAction: ShortcutItem] = [:]) {
        self.shortcuts = shortcuts
    }

    public static var defaultPreferences: ShortcutPreferences {
        var map: [CaptureShortcutAction: ShortcutItem] = [:]
        for action in CaptureShortcutAction.allCases {
            map[action] = ShortcutItem(id: action, isEnabled: true, keyCombination: action.defaultKeyCombination)
        }
        return ShortcutPreferences(shortcuts: map)
    }

    public func item(for action: CaptureShortcutAction) -> ShortcutItem {
        shortcuts[action] ?? ShortcutItem(id: action, isEnabled: true, keyCombination: action.defaultKeyCombination)
    }

    public mutating func setItem(_ item: ShortcutItem) {
        shortcuts[item.id] = item
    }

    func conflictingAction(
        for combination: KeyCombination,
        excluding action: CaptureShortcutAction
    ) -> CaptureShortcutAction? {
        CaptureShortcutAction.allCases.first { candidateAction in
            guard candidateAction != action else { return false }
            let candidate = item(for: candidateAction)
            return candidate.keyCombination == combination
        }
    }
}

@MainActor
struct ShortcutAvailabilityValidator {
    var canRegister: @MainActor (KeyCombination) -> Bool

    init(canRegister: @escaping @MainActor (KeyCombination) -> Bool = GlobalShortcutAvailability.canRegister) {
        self.canRegister = canRegister
    }

    func validationError(
        for capturedKey: ShortcutCapturedKey,
        editing action: CaptureShortcutAction,
        preferences: ShortcutPreferences,
        applicationMenu: NSMenu? = NSApp.mainMenu
    ) -> ShortcutCaptureValidationError? {
        let combination = capturedKey.combination
        if let error = ShortcutCapturePolicy.validationError(for: combination) {
            return error
        }
        if let conflictingAction = preferences.conflictingAction(for: combination, excluding: action) {
            return .duplicate(conflictingAction)
        }
        if let item = matchingMenuItem(
            in: applicationMenu,
            charactersIgnoringModifiers: capturedKey.charactersIgnoringModifiers,
            modifiers: combination.modifiers.eventModifierFlags
        ) {
            return .applicationMenu(item.title)
        }
        guard canRegister(combination) else {
            return .unavailable
        }
        return nil
    }

    private func matchingMenuItem(
        in menu: NSMenu?,
        charactersIgnoringModifiers: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem? {
        guard let menu else { return nil }
        let relevantFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let normalizedCharacters = charactersIgnoringModifiers.lowercased()

        for item in menu.items {
            if let match = matchingMenuItem(
                in: item.submenu,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                modifiers: modifiers
            ) {
                return match
            }

            guard item.isEnabled,
                  !item.isHidden,
                  !item.keyEquivalent.isEmpty,
                  item.keyEquivalent.lowercased() == normalizedCharacters,
                  item.keyEquivalentModifierMask.intersection(relevantFlags)
                    == modifiers.intersection(relevantFlags) else {
                continue
            }
            return item
        }
        return nil
    }
}

@MainActor
private enum GlobalShortcutAvailability {
    static func canRegister(_ combination: KeyCombination) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("ORvr"), id: UInt32.max)
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        return status == noErr
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
