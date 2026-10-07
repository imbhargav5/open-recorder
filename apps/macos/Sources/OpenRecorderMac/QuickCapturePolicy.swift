import AppKit

enum ScreenshotAfterCapture: String, CaseIterable, Identifiable {
    case edit, copy, save

    var id: String { rawValue }
    var title: String {
        switch self {
        case .edit: "Open editor"
        case .copy: "Copy to clipboard"
        case .save: "Save to screenshots folder"
        }
    }
}

enum CaptureShortcutRegistrationState: Equatable {
    case active, disabled, suspended, unavailable

    var title: String {
        switch self {
        case .active: "Active"
        case .disabled: "Off"
        case .suspended: "Paused while changing a shortcut"
        case .unavailable: "Unavailable — macOS or another app may be using this shortcut."
        }
    }
}

struct QuickCaptureTargetContext {
    var displayID: UInt32?
    var ownerBundleID: String?
    var orderedWindowIDs: [UInt32]

    @MainActor static func current() -> Self {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let application = NSWorkspace.shared.frontmostApplication
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windowIDs = windows.compactMap { window -> UInt32? in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == application?.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
        return Self(displayID: displayID, ownerBundleID: application?.bundleIdentifier, orderedWindowIDs: windowIDs)
    }

    func target(in sources: [CaptureSource], kind: CaptureSourceKind) -> CaptureSource? {
        let candidates = sources.filter { $0.kind == kind }
        switch kind {
        case .display:
            return candidates.first { $0.displayID == displayID && displayID != nil }
                ?? (candidates.count == 1 ? candidates.first : nil)
        case .window:
            for id in orderedWindowIDs {
                if let source = candidates.first(where: { $0.windowID == id && $0.ownerBundleID == ownerBundleID }) {
                    return source
                }
            }
            return nil
        case .area:
            return nil
        }
    }
}
