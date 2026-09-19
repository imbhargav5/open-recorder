import SwiftUI

struct TimelineZoomTransitionControls: View {
    var region: TimelineZoomRegion
    var edits: TimelineEditDriver
    var outputDuration: Double
    var update: (TimelineZoomTransition?) -> Void
    var onEditingChanged: (Bool) -> Void

    private var transition: TimelineZoomTransition {
        region.transition ?? .defaults(for: region.animationPreset)
    }

    var body: some View {
        InspectorGroup(title: "Zoom transition", symbolName: "waveform.path", onReset: { update(nil) }) {
            Menu("Copy / Paste") { ZoomTransitionMenu(region: region, edits: edits) }
            InspectorSlider(title: "Zoom in", valueText: seconds(transition.enterDuration),
                value: value(\.enterDuration), range: 0...3, step: 0.01, onEditingChanged: onEditingChanged)
            InspectorSlider(title: "Zoom out", valueText: seconds(transition.exitDuration),
                value: value(\.exitDuration), range: 0...3, step: 0.01, onEditingChanged: onEditingChanged)
            Picker("Motion", selection: value(\.motion)) {
                ForEach(CameraLayoutTransition.Motion.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if transition.motion == .ease {
                Picker("Easing", selection: value(\.easing)) {
                    ForEach(TimelineZoomEasing.allCases) { Text($0.title).tag($0) }
                }
            } else {
                InspectorSlider(title: "Bounce", valueText: "\(Int(transition.bounce * 100))%",
                    value: value(\.bounce), range: 0...1, step: 0.01, onEditingChanged: onEditingChanged)
            }
            if region.transition != nil, transition.enterDuration + transition.exitDuration > outputDuration {
                Text("Both transitions are shortened proportionally to fit this zoom.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(region.transition == nil
                 ? "Using the saved zoom style. Adjust a control to customize this zoom’s entrance and exit."
                 : "Times use playback seconds. The zoom continues through camera layout and scene transitions.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seconds(_ value: Double) -> String { value == 0 ? "Instant" : String(format: "%.2f s", value) }
    private func value<T>(_ keyPath: WritableKeyPath<TimelineZoomTransition, T>) -> Binding<T> {
        Binding(get: { transition[keyPath: keyPath] }, set: {
            var next = transition
            next[keyPath: keyPath] = $0
            update(next.clamped)
        })
    }
}

struct ZoomTransitionMenu: View {
    var region: TimelineZoomRegion
    var edits: TimelineEditDriver

    var body: some View {
        Button {
            ZoomTransitionStore.shared.copy(region.transition ?? .defaults(for: region.animationPreset))
        } label: {
            Label("Copy Zoom Transition", systemImage: "doc.on.doc")
        }
        Button {
            if let transition = ZoomTransitionStore.shared.copiedTransition {
                edits.applyZoomTransition(transition, to: [region.id])
            }
        } label: {
            Label("Paste Zoom Transition", systemImage: "doc.on.clipboard")
        }.disabled(ZoomTransitionStore.shared.copiedTransition == nil)
        Button {
            edits.applyZoomTransition(region.transition ?? .defaults(for: region.animationPreset), to: edits.zoomRegions.map(\.id))
        } label: {
            Label("Copy to All Zoom Transitions", systemImage: "rectangle.stack")
        }.disabled(edits.zoomRegions.count < 2)
    }
}
