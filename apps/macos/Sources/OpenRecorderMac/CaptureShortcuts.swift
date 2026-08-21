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

    public var availablePresets: [KeyCombination] {
        switch self {
        case .deviceScreenshot:
            return [
                KeyCombination(keyCode: UInt32(kVK_ANSI_3), modifiers: [.option, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_3), modifiers: [.command, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_3), modifiers: [.control, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_S), modifiers: [.option, .shift])
            ]
        case .dragScreenshot:
            return [
                KeyCombination(keyCode: UInt32(kVK_ANSI_4), modifiers: [.option, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_4), modifiers: [.control, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_A), modifiers: [.option, .shift])
            ]
        case .deviceScreenRecord:
            return [
                KeyCombination(keyCode: UInt32(kVK_ANSI_5), modifiers: [.option, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_5), modifiers: [.control, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option, .shift])
            ]
        case .dragScreenRecord:
            return [
                KeyCombination(keyCode: UInt32(kVK_ANSI_6), modifiers: [.option, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_6), modifiers: [.command, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_6), modifiers: [.control, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_D), modifiers: [.option, .shift])
            ]
        case .toggleRecording:
            return [
                KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command, .shift]),
                KeyCombination(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option])
            ]
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
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        default: return "Key(\(keyCode))"
        }
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
}
