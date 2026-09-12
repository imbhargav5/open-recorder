import AppKit
import SwiftUI

enum SceneEndpoint: String, CaseIterable { case start = "Start", end = "End" }
enum SceneTool: String, CaseIterable { case tilt = "Tilt", move = "Move" }

struct SceneInspector: View {
    @Binding var settings: SceneSettings
    @Binding var endpoint: SceneEndpoint
    var duration: Double
    var isImage = false
    var seek: (Double) -> Void = { _ in }
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var advanced = false

    private var pose: Binding<ScenePose> {
        scenePoseBinding(settings: $settings, endpoint: endpoint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("Scene").font(.headline)
                Text("Alpha")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.overlay, in: Capsule())
                    .accessibilityLabel("Scene is in alpha")
                Spacer()
                Button("Reset Scene") { settings = .identity; seek(0) }
                    .font(.system(size: 10)).buttonStyle(.plain)
            }.padding(.bottom, 8)
            Text("Tilt your media and frame. Your background stays upright.")
                .font(.system(size: 11)).foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            InspectorGroup(title: "Presets", symbolName: "square.grid.2x2", showsTopDivider: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(ScenePosePreset.allCases) { preset in
                        Button { pose.wrappedValue = preset.pose } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                    .rotationEffect(.degrees(preset.pose.rotation))
                                Text(preset.rawValue).font(.system(size: 10))
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.bordered)
                    }
                }
            }
            InspectorGroup(title: "Transform", symbolName: "rotate.3d", onReset: { pose.wrappedValue = .identity }) {
                if settings.motion.enabled {
                    Picker("Edit pose", selection: $endpoint) {
                        ForEach(SceneEndpoint.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    .onChange(of: endpoint) { _, value in
                        seek(value == .start ? settings.motion.startTime : settings.motion.endTime)
                    }
                }
                poseSlider("Horizontal Tilt", keyPath: \.tiltY, range: -60...60, step: 1, suffix: "°")
                poseSlider("Vertical Tilt", keyPath: \.tiltX, range: -60...60, step: 1, suffix: "°")
                poseSlider("Rotation", keyPath: \.rotation, range: -180...180, step: 1, suffix: "°")
                poseSlider("Scale", keyPath: \.scale, range: 0.25...2, step: 0.01, suffix: "×")
                poseSlider("Position X", keyPath: \.x, range: -1...1, step: 0.01)
                poseSlider("Position Y", keyPath: \.y, range: -1...1, step: 0.01)
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    poseSlider("Perspective", keyPath: \.perspective, range: 0...1, step: 0.01)
                }.font(.system(size: 11))
            }
            InspectorGroup(title: "Mockup", symbolName: "macwindow", onReset: {
                settings.mockup = .none; settings.edgeHighlight = false; settings.darkMockup = true
            }) {
                Picker("Frame", selection: $settings.mockup) {
                    ForEach(MockupStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if settings.mockup != .none {
                    Picker("Style", selection: $settings.darkMockup) {
                        Text("Light").tag(false); Text("Dark").tag(true)
                    }.pickerStyle(.segmented)
                }
                Toggle("Edge highlight", isOn: $settings.edgeHighlight).toggleStyle(.switch).controlSize(.small)
            }
            InspectorGroup(title: "Motion", symbolName: "play.rectangle", onReset: {
                settings.motion = SceneMotion().clamped(to: duration); seek(0)
            }) {
                Toggle("Animate", isOn: Binding(get: { settings.motion.enabled }, set: { enabled in
                    var next = settings
                    next.motion.enabled = enabled
                    next.motion = next.motion.clamped(to: duration)
                    settings = next
                    if enabled { endpoint = .start; seek(next.motion.startTime) }
                })).toggleStyle(.switch).controlSize(.small)
                if settings.motion.enabled {
                    Menu("Motion preset") {
                        ForEach(SceneMotionPreset.allCases) { preset in
                            Button(preset.rawValue) {
                                var next = settings
                                (next.motion.startPose, next.motion.endPose) = preset.poses
                                settings = next
                                endpoint = .start; seek(next.motion.startTime)
                            }
                        }
                    }.menuStyle(.borderlessButton)
                    if isImage {
                        InspectorSlider(title: "Duration", valueText: String(format: "%.2fs", settings.imageDuration),
                            value: $settings.imageDuration, range: 0.25...60, step: 0.25, onEditingChanged: onEditingChanged)
                    }
                    SceneRangeControl(motion: $settings.motion, duration: duration, onEditingChanged: onEditingChanged)
                    timeSlider("Start", start: true)
                    timeSlider("End", start: false)
                    Picker("Easing", selection: $settings.motion.easing) {
                        ForEach(SceneEasing.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text("One movement; holds its pose before and after.")
                        .font(.system(size: 10)).foregroundStyle(Theme.fgMuted)
                }
            }
        }
        .controlSize(.small)
        .foregroundStyle(Theme.fg)
    }

    private func poseSlider(_ title: String, keyPath: WritableKeyPath<ScenePose, Double>, range: ClosedRange<Double>, step: Double, suffix: String = "") -> some View {
        InspectorSlider(title: title, valueText: String(format: step >= 1 ? "%.0f%@" : "%.2f%@", pose.wrappedValue[keyPath: keyPath], suffix),
            value: Binding(get: { pose.wrappedValue[keyPath: keyPath] }, set: { pose.wrappedValue[keyPath: keyPath] = $0 }),
            range: range, step: step, onEditingChanged: onEditingChanged)
    }

    private func timeSlider(_ title: String, start: Bool) -> some View {
        let binding = Binding<Double>(get: { start ? settings.motion.startTime : settings.motion.endTime }, set: { value in
            var next = settings.motion
            if start { next.startTime = min(value, max(0, next.endTime - 0.05)) }
            else { next.endTime = max(value, next.startTime + 0.05) }
            settings.motion = next.clamped(to: duration)
        })
        return InspectorSlider(title: title, valueText: String(format: "%.2fs", binding.wrappedValue),
            value: binding, range: 0...max(0.05, duration), step: 0.05, onEditingChanged: onEditingChanged)
    }
}

func scenePoseBinding(settings: Binding<SceneSettings>, endpoint: SceneEndpoint) -> Binding<ScenePose> {
    Binding(get: {
        let s = settings.wrappedValue
        return s.motion.enabled ? (endpoint == .start ? s.motion.startPose : s.motion.endPose) : s.pose
    }, set: { value in
        var s = settings.wrappedValue
        if s.motion.enabled {
            if endpoint == .start { s.motion.startPose = value.clamped } else { s.motion.endPose = value.clamped }
        } else { s.pose = value.clamped }
        settings.wrappedValue = s
    })
}

private struct SceneRangeControl: View {
    @Binding var motion: SceneMotion
    var duration: Double
    var onEditingChanged: (Bool) -> Void
    @State private var dragging = false
    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width - 12), total = max(0.05, duration)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.overlay)
                Capsule().fill(Theme.accent.opacity(0.6))
                    .frame(width: max(3, width * (motion.endTime - motion.startTime) / total))
                    .offset(x: 6 + width * motion.startTime / total)
                handle(start: true, width: width, total: total)
                handle(start: false, width: width, total: total)
            }.frame(height: 18)
        }.frame(height: 20).coordinateSpace(name: "sceneRange")
    }
    private func handle(start: Bool, width: CGFloat, total: Double) -> some View {
        Capsule().fill(.white).frame(width: 10, height: 20)
            .offset(x: 1 + width * (start ? motion.startTime : motion.endTime) / total)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("sceneRange")).onChanged { event in
                if !dragging { dragging = true; onEditingChanged(true) }
                let t = (event.location.x - 6) / width * total
                var next = motion
                if start { next.startTime = min(max(0, t), max(0, next.endTime - 0.05)) }
                else { next.endTime = max(t, next.startTime + 0.05) }
                motion = next.clamped(to: duration)
            }.onEnded { _ in dragging = false; onEditingChanged(false) })
            .accessibilityHidden(true)
    }
}

struct SceneCanvasTools: View {
    @Binding var tool: SceneTool
    var body: some View {
        HStack(spacing: 10) {
            Picker("Scene tool", selection: $tool) {
                ForEach(SceneTool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 140)
            Text("Drag to \(tool.rawValue.lowercased()) · ⇧ for precision")
                .font(.system(size: 10)).foregroundStyle(Theme.fgMuted)
        }.padding(.vertical, 6)
    }
}

struct SceneCanvasGesture: ViewModifier {
    var enabled: Bool
    var tool: SceneTool
    @Binding var pose: ScenePose
    var onEditingChanged: (Bool) -> Void
    @State private var original: ScenePose?

    func body(content: Content) -> some View {
        content.overlay {
            if enabled {
                GeometryReader { proxy in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2).onChanged { event in
                            if original == nil { original = pose; onEditingChanged(true) }
                            guard var next = original else { return }
                            let precision = NSEvent.modifierFlags.contains(.shift) ? 0.2 : 1.0
                            let dx = event.translation.width / max(1, proxy.size.width) * precision
                            let dy = event.translation.height / max(1, proxy.size.height) * precision
                            if tool == .tilt { next.tiltY += dx * 120; next.tiltX += dy * 120 }
                            else { next.x += dx; next.y += dy }
                            pose = next.clamped
                        }.onEnded { _ in original = nil; onEditingChanged(false) })
                }
            }
        }
        .onDisappear { if original != nil { original = nil; onEditingChanged(false) } }
    }
}

struct CanvasAspectPicker: View {
    @Binding var selection: VideoPreviewAspectPreset
    var body: some View {
        Picker("Canvas", selection: $selection) {
            ForEach(VideoPreviewAspectPreset.allCases) { Text($0.title).tag($0) }
        }.controlSize(.small)
    }
}
