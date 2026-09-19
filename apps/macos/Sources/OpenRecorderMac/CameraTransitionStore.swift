import Foundation
import Observation

struct CameraTransitionPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var transition: CameraLayoutTransition
}

/// Presets are shared between projects and survive app restarts. The copied
/// transition is an in-app clipboard shared by all editing windows.
@MainActor @Observable
final class CameraTransitionStore {
    static let shared = CameraTransitionStore()
    static let defaultsKey = "cameraTransitionPresets.v1"

    private(set) var presets: [CameraTransitionPreset]
    private(set) var copiedTransition: CameraLayoutTransition?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([CameraTransitionPreset].self, from: $0) } ?? []
    }

    func copy(_ transition: CameraLayoutTransition) {
        copiedTransition = transition.clamped
    }

    @discardableResult
    func save(name: String, transition: CameraLayoutTransition) -> CameraTransitionPreset? {
        let base = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !base.isEmpty else { return nil }
        var name = base
        var suffix = 2
        while presets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(base) (\(suffix))"
            suffix += 1
        }
        let preset = CameraTransitionPreset(id: UUID(), name: name, transition: transition.clamped)
        presets.append(preset)
        persist()
        return preset
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
