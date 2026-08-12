import AppKit
import Foundation

struct CaptureSetupPreferences: Codable, Equatable {
    var mode: CaptureMode
    var preferredSourceKind: CaptureSourceKind
    var sourceReference: CaptureSourceReference?

    static let `default` = CaptureSetupPreferences(
        mode: .recording,
        preferredSourceKind: .display,
        sourceReference: nil
    )
}

enum CaptureSourceReference: Codable, Equatable {
    case display(displayID: UInt32?, displayIndex: Int?, name: String)
    case window(ownerBundleID: String, name: String)
    case area(CaptureArea)

    init?(source: CaptureSource) {
        switch source.kind {
        case .display:
            guard source.displayID != nil || source.displayIndex != nil else { return nil }
            self = .display(
                displayID: source.displayID,
                displayIndex: source.displayIndex,
                name: source.name
            )
        case .window:
            guard let ownerBundleID = source.ownerBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ownerBundleID.isEmpty,
                  !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            self = .window(ownerBundleID: ownerBundleID, name: source.name)
        case .area:
            guard let area = source.area else { return nil }
            self = .area(area)
        }
    }

    var sourceKind: CaptureSourceKind {
        switch self {
        case .display: .display
        case .window: .window
        case .area: .area
        }
    }

    func resolve(
        in sources: [CaptureSource],
        displayFrames: [UInt32: CGRect]
    ) -> CaptureSource? {
        switch self {
        case .display(let displayID, let displayIndex, let name):
            if let displayID {
                let matches = sources.filter { $0.kind == .display && $0.displayID == displayID }
                if matches.count == 1 {
                    return matches[0]
                }
            }
            if let displayIndex {
                let matches = sources.filter {
                    $0.kind == .display &&
                        $0.displayIndex == displayIndex &&
                        $0.name == name
                }
                if matches.count == 1 {
                    return matches[0]
                }
            }
            return nil

        case .window(let ownerBundleID, let name):
            let matches = sources.filter {
                $0.kind == .window &&
                    $0.ownerBundleID == ownerBundleID &&
                    $0.name == name
            }
            return matches.count == 1 ? matches[0] : nil

        case .area(let area):
            guard area.width > 0,
                  area.height > 0,
                  let displayID = area.displayID,
                  let displayFrame = displayFrames[displayID] else {
                return nil
            }
            let areaFrame = CGRect(
                x: area.x,
                y: area.y,
                width: area.width,
                height: area.height
            )
            guard displayFrame.contains(areaFrame) else { return nil }
            return CaptureSource(
                id: "area:interactive",
                kind: .area,
                name: "Selected Area",
                subtitle: "\(area.width) x \(area.height)",
                displayIndex: nil,
                displayID: area.displayID,
                windowID: nil,
                area: area,
                thumbnailData: nil
            )
        }
    }
}

@MainActor
struct CaptureSetupPreferencesStore {
    private static let defaultsKey = "capture.setup"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var live: CaptureSetupPreferencesStore {
        CaptureSetupPreferencesStore(defaults: .standard)
    }

    static func ephemeral() -> CaptureSetupPreferencesStore {
        let suiteName = "OpenRecorder.CaptureSetup.\(UUID().uuidString)"
        return CaptureSetupPreferencesStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    func load() -> CaptureSetupPreferences {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let preferences = try? JSONDecoder().decode(CaptureSetupPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    func save(_ preferences: CaptureSetupPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

extension NSScreen {
    static var captureDisplayFramesByID: [UInt32: CGRect] {
        Dictionary(uniqueKeysWithValues: screens.compactMap { screen in
            guard let displayID = screen.captureDisplayID else { return nil }
            return (displayID, screen.frame)
        })
    }

    var captureDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
