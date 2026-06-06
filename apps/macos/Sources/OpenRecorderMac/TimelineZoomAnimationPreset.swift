import Foundation

enum TimelineZoomAnimationPreset: String, CaseIterable, Codable, Hashable, Identifiable {
    case balanced
    case subtle
    case snappy
    case cinematic
    case guided

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .subtle: "Subtle"
        case .snappy: "Snappy"
        case .cinematic: "Cinematic"
        case .guided: "Guided"
        }
    }

    var shortTitle: String {
        switch self {
        case .balanced: "Bal"
        case .subtle: "Sub"
        case .snappy: "Snap"
        case .cinematic: "Cine"
        case .guided: "Guide"
        }
    }

    var configuration: TimelineZoomAnimationConfiguration {
        switch self {
        case .balanced:
            TimelineZoomAnimationConfiguration(
                depth: TimelineZoomDepth.defaultDepth,
                leadInSeconds: 0.25,
                holdAfterClickSeconds: 1.35,
                mergeThresholdSeconds: 0.9,
                minimumGapSeconds: 0.2,
                minimumDurationSeconds: 0.10,
                minimumConfidence: 0.45,
                rampInSeconds: 0.45,
                rampOutSeconds: 0.35,
                easing: .smoothstep,
                followsCursor: false,
                safeZoneRatio: 0.25,
                focusClampRange: 0.08...0.92
            )
        case .subtle:
            TimelineZoomAnimationConfiguration(
                depth: 1.35,
                leadInSeconds: 0.18,
                holdAfterClickSeconds: 0.90,
                mergeThresholdSeconds: 0.65,
                minimumGapSeconds: 0.28,
                minimumDurationSeconds: 0.16,
                minimumConfidence: 0.72,
                rampInSeconds: 0.24,
                rampOutSeconds: 0.30,
                easing: .smoothstep,
                followsCursor: false,
                safeZoneRatio: 0.30,
                focusClampRange: 0.12...0.88
            )
        case .snappy:
            TimelineZoomAnimationConfiguration(
                depth: 1.85,
                leadInSeconds: 0.12,
                holdAfterClickSeconds: 0.82,
                mergeThresholdSeconds: 0.45,
                minimumGapSeconds: 0.12,
                minimumDurationSeconds: 0.10,
                minimumConfidence: 0.35,
                rampInSeconds: 0.18,
                rampOutSeconds: 0.22,
                easing: .easeOut,
                followsCursor: false,
                safeZoneRatio: 0.22,
                focusClampRange: 0.08...0.92
            )
        case .cinematic:
            TimelineZoomAnimationConfiguration(
                depth: 1.95,
                leadInSeconds: 0.45,
                holdAfterClickSeconds: 1.85,
                mergeThresholdSeconds: 2.0,
                minimumGapSeconds: 0.18,
                minimumDurationSeconds: 0.35,
                minimumConfidence: 0.48,
                rampInSeconds: 0.48,
                rampOutSeconds: 0.62,
                easing: .easeInOut,
                followsCursor: false,
                safeZoneRatio: 0.28,
                focusClampRange: 0.08...0.92
            )
        case .guided:
            TimelineZoomAnimationConfiguration(
                depth: 1.80,
                leadInSeconds: 0.32,
                holdAfterClickSeconds: 1.65,
                mergeThresholdSeconds: 1.55,
                minimumGapSeconds: 0.16,
                minimumDurationSeconds: 0.25,
                minimumConfidence: 0.40,
                rampInSeconds: 0.42,
                rampOutSeconds: 0.50,
                easing: .smoothstep,
                followsCursor: true,
                safeZoneRatio: 0.25,
                focusClampRange: 0.08...0.92
            )
        }
    }

    static func storedValue(_ rawValue: String?) -> TimelineZoomAnimationPreset {
        guard let rawValue,
              let preset = TimelineZoomAnimationPreset(rawValue: rawValue) else {
            return .balanced
        }
        return preset
    }
}

struct TimelineZoomAnimationConfiguration: Equatable {
    var depth: Double
    var leadInSeconds: Double
    var holdAfterClickSeconds: Double
    var mergeThresholdSeconds: Double
    var minimumGapSeconds: Double
    var minimumDurationSeconds: Double
    var minimumConfidence: Double
    var rampInSeconds: Double
    var rampOutSeconds: Double
    var easing: TimelineZoomEasing
    var followsCursor: Bool
    var safeZoneRatio: Double
    var focusClampRange: ClosedRange<Double>
}

enum TimelineZoomEasing: Equatable {
    case smoothstep
    case easeOut
    case easeInOut

    func value(_ rawValue: Double) -> Double {
        let x = min(max(rawValue, 0), 1)
        switch self {
        case .smoothstep:
            return x * x * (3 - 2 * x)
        case .easeOut:
            return 1 - pow(1 - x, 3)
        case .easeInOut:
            return x < 0.5
                ? 4 * x * x * x
                : 1 - pow(-2 * x + 2, 3) / 2
        }
    }
}
