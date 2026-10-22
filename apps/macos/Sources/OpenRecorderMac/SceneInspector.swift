import AppKit
import SwiftUI

enum SceneEndpoint: String, CaseIterable { case start = "Start", end = "End" }
enum SceneTool: String, CaseIterable { case tilt = "Tilt", move = "Move" }

struct SceneInspector: View {
    @Binding var settings: SceneSettings
    @Binding var endpoint: SceneEndpoint
    var duration: Double
    var isImage = false
    var hasCamera = false
    var edits: TimelineEditDriver? = nil
    var currentTime: Double = 0
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
            if hasCamera {
                InspectorGroup(title: "Camera", symbolName: "camera.fill") {
                    SceneBooleanTabs(title: "Camera follows scene", isOn: Binding(
                        get: { settings.resolvedCameraFollowsScene },
                        set: { settings.cameraFollowsScene = $0 }),
                                     enabledTitle: "Follow scene", enabledSymbol: "camera.metering.center.weighted",
                                     disabledTitle: "Stay fixed", disabledSymbol: "camera")
                    Text(settings.resolvedCameraFollowsScene
                         ? "Screen and camera rotate, tilt, scale and move together."
                         : "The camera stays upright and keeps its layout position while the screen moves.")
                        .font(.system(size: 11)).foregroundStyle(Theme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
                settings.browserURL = "https://example.com"; settings.browserURLAlignment = .left
                settings.browserToolbarStyle = .standard; settings.browserShowTrafficLights = true
                settings.browserShowNavButtons = true; settings.browserShowLock = true
            }) {
                Picker("Frame", selection: $settings.mockup) {
                    ForEach(MockupStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if settings.mockup != .none {
                    Picker("Style", selection: $settings.darkMockup) {
                        Text("Light").tag(false); Text("Dark").tag(true)
                    }.pickerStyle(.segmented)
                }
                if settings.mockup == .browser {
                    BrowserURLField(url: $settings.browserURL)
                    BrowserToolbarGrid(settings: $settings)
                }
                SceneBooleanTabs(title: "Edge highlight", isOn: $settings.edgeHighlight,
                                 enabledTitle: "Highlight", enabledSymbol: "rectangle.inset.filled",
                                 disabledTitle: "Plain", disabledSymbol: "rectangle")
            }
            MagnifierLensInspector(settings: $settings, onEditingChanged: onEditingChanged)
            InspectorGroup(title: "Privacy", symbolName: "eye.slash", onReset: {
                settings.sensitiveData = nil
                edits?.send(.updateBlurRegions([]))
            }) {
                SceneBooleanTabs(title: "Blur regions", isOn: Binding(
                    get: { settings.resolvedSensitiveData.enabled },
                    set: { var cfg = settings.resolvedSensitiveData; cfg.enabled = $0; settings.sensitiveData = cfg }
                ), enabledTitle: "Blur", enabledSymbol: "eye.slash.fill",
                   disabledTitle: "Clear", disabledSymbol: "eye")
                if settings.resolvedSensitiveData.enabled {
                    Text("Drag over the preview to add a timed blur at the playhead. Each blur is independent, with its own strength and duration.")
                        .font(.system(size: 10)).foregroundStyle(Theme.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let edits {
                        let blurRegions = edits.snapshot.blurRegions
                        if !blurRegions.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(blurRegions.enumerated()), id: \.element.id) { index, blur in
                                    blurRegionEditor(blur, index: index, edits: edits)
                                }
                            }
                        }
                        if blurRegions.isEmpty {
                            Text("No blur regions yet. Drag on the preview to add one at the current time.")
                                .font(.system(size: 10)).foregroundStyle(Theme.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Clear all blur regions") {
                            edits.send(.updateBlurRegions([]))
                        }
                        .disabled(blurRegions.isEmpty)
                        .controlSize(.small)
                    }
                }
            }
            InspectorGroup(title: "Motion", symbolName: "play.rectangle", onReset: {
                settings.motion = SceneMotion().clamped(to: duration); seek(0)
            }) {
                SceneBooleanTabs(title: "Animate", isOn: Binding(get: { settings.motion.enabled }, set: { enabled in
                    var next = settings
                    next.motion.enabled = enabled
                    next.motion = next.motion.clamped(to: duration)
                    settings = next
                    if enabled { endpoint = .start; seek(next.motion.startTime) }
                }), enabledTitle: "Animate", enabledSymbol: "play.rectangle.fill",
                   disabledTitle: "Still", disabledSymbol: "pause.rectangle")
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

}

/// A dedicated Lens page keeps the effect discoverable instead of burying it
/// beneath Scene transform and mockup controls.
struct MagnifierLensInspector: View {
    @Binding var settings: SceneSettings
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("Lens").font(.headline)
                Text("Beta")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.overlay, in: Capsule())
                Spacer()
                Button("Reset Lens") { settings.magnifierLens = nil }
                    .font(.system(size: 10)).buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            Text("A circular liquid-glass lens magnifies the content at your cursor. Motion blur responds to cursor velocity in preview and export.")
                .font(.system(size: 11)).foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            InspectorGroup(title: "Liquid Glass Lens", symbolName: "magnifyingglass", showsTopDivider: false) {
                SceneBooleanTabs(title: "Lens mode", isOn: Binding(
                    get: { settings.resolvedMagnifierLens.enabled },
                    set: { var cfg = settings.resolvedMagnifierLens; cfg.enabled = $0; settings.magnifierLens = cfg }
                ), enabledTitle: "Cursor lens", enabledSymbol: "magnifyingglass",
                   disabledTitle: "Off", disabledSymbol: "circle.slash")
                if settings.resolvedMagnifierLens.enabled {
                    magnifierSlider("Radius", keyPath: \.radius, range: 40...400, step: 5, suffix: "px")
                    magnifierSlider("Magnification", keyPath: \.magnification, range: 1.2...5, step: 0.1, suffix: "×")
                    magnifierSlider("Glass edge blur", keyPath: \.glassBlurEdge, range: 0...30, step: 1, suffix: "px")
                    magnifierSlider("Glass highlight", keyPath: \.glassOpacity, range: 0...0.5, step: 0.01, suffix: "")
                    magnifierSlider("Border", keyPath: \.borderWidth, range: 0...10, step: 0.5, suffix: "px")
                    magnifierSlider("Optics motion blur", keyPath: \.motionBlurAmount, range: 0...30, step: 1, suffix: "")
                    SceneBooleanTabs(title: "Tracking", isOn: Binding(
                        get: { settings.resolvedMagnifierLens.followsCursor },
                        set: { var cfg = settings.resolvedMagnifierLens; cfg.followsCursor = $0; settings.magnifierLens = cfg }
                    ), enabledTitle: "Follow cursor", enabledSymbol: "cursorarrow.motionlines",
                       disabledTitle: "Fixed", disabledSymbol: "pin.fill")
                }
            }
        }
        .controlSize(.small)
        .foregroundStyle(Theme.fg)
    }

    private func magnifierSlider(_ title: String, keyPath: WritableKeyPath<MagnifierLensConfig, Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        let value = settings.resolvedMagnifierLens[keyPath: keyPath]
        return InspectorSlider(title: title, valueText: String(format: step >= 1 ? "%.0f%@" : "%.2f%@", value, suffix),
            value: Binding(get: { value }, set: {
                var cfg = settings.resolvedMagnifierLens; cfg[keyPath: keyPath] = $0; settings.magnifierLens = cfg
            }), range: range, step: step, onEditingChanged: onEditingChanged)
    }
}

extension SceneInspector {

    private func blurRegionEditor(_ blur: TimelineBlurRegion, index: Int, edits: TimelineEditDriver) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Blur \(index + 1)")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Int(blur.region.width * 100))×\(Int(blur.region.height * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.fgMuted)
                Spacer()
                Button {
                    edits.send(.removeBlurRegion(id: blur.id))
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.fgMuted)
                .help("Remove blur \(index + 1)")
            }
            InspectorSlider(title: "Strength", valueText: "\(Int(blur.blurRadius))",
                value: blurValueBinding(blur.id, edits: edits, keyPath: \.blurRadius), range: 5...60, step: 1,
                onEditingChanged: onEditingChanged)
            InspectorSlider(title: "Start", valueText: String(format: "%.2fs", blur.span.start),
                value: blurSpanBinding(blur.id, edits: edits, start: true), range: 0...max(0.05, duration), step: 0.05,
                onEditingChanged: onEditingChanged)
            InspectorSlider(title: "End", valueText: String(format: "%.2fs", blur.span.end),
                value: blurSpanBinding(blur.id, edits: edits, start: false), range: 0...max(0.05, duration), step: 0.05,
                onEditingChanged: onEditingChanged)
        }
        .padding(8)
        .background(Theme.overlay, in: RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
    }

    private func blurValueBinding(_ id: TimelineRegionID, edits: TimelineEditDriver,
                                  keyPath: WritableKeyPath<TimelineBlurRegion, Double>) -> Binding<Double> {
        Binding(get: { edits.snapshot.blurRegions.first(where: { $0.id == id })?[keyPath: keyPath] ?? 25 }, set: { value in
            var next = edits.snapshot.blurRegions
            guard let index = next.firstIndex(where: { $0.id == id }) else { return }
            next[index][keyPath: keyPath] = value
            edits.send(.updateBlurRegions(next))
        })
    }

    private func blurSpanBinding(_ id: TimelineRegionID, edits: TimelineEditDriver, start: Bool) -> Binding<Double> {
        Binding(get: {
            guard let region = edits.snapshot.blurRegions.first(where: { $0.id == id }) else { return 0 }
            return start ? region.span.start : region.span.end
        }, set: { value in
            var next = edits.snapshot.blurRegions
            guard let index = next.firstIndex(where: { $0.id == id }) else { return }
            let other = start ? next[index].span.end : next[index].span.start
            if start { next[index].span.start = min(value, max(0, other - 0.10)) }
            else { next[index].span.end = max(value, min(duration, other + 0.10)) }
            next[index].span = next[index].span.normalized(duration: duration)
            edits.send(.updateBlurRegions(next))
        })
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

private struct BrowserToolbarGrid: View {
    @Binding var settings: SceneSettings
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("URL position")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                LazyVGrid(columns: columns, spacing: 6) {
                    browserTile(title: "Left", symbol: "text.alignleft",
                                isSelected: settings.browserURLAlignment == .left) {
                        settings.browserURLAlignment = .left
                    }
                    browserTile(title: "Center", symbol: "text.aligncenter",
                                isSelected: settings.browserURLAlignment == .center) {
                        settings.browserURLAlignment = .center
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Toolbar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                LazyVGrid(columns: columns, spacing: 6) {
                    browserTile(title: "Standard", symbol: "rectangle.topthird.inset.filled",
                                isSelected: settings.browserToolbarStyle == .standard) {
                        settings.browserToolbarStyle = .standard
                    }
                    browserTile(title: "Compact", symbol: "rectangle.tophalf.inset.filled",
                                isSelected: settings.browserToolbarStyle == .compact) {
                        settings.browserToolbarStyle = .compact
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Browser elements")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.fgMuted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 3), spacing: 6) {
                    browserTile(title: "Lights", symbol: "circle.lefthalf.filled",
                                isSelected: settings.browserShowTrafficLights) {
                        settings.browserShowTrafficLights.toggle()
                    }
                    browserTile(title: "Nav", symbol: "arrow.left.arrow.right",
                                isSelected: settings.browserShowNavButtons) {
                        settings.browserShowNavButtons.toggle()
                    }
                    browserTile(title: "Lock", symbol: "lock.fill",
                                isSelected: settings.browserShowLock) {
                        settings.browserShowLock.toggle()
                    }
                }
            }
        }
    }

    private func browserTile(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), help: title, action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.86))
            .background(isSelected ? Color.white.opacity(0.18) : Theme.overlay,
                        in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.85) : Theme.overlay)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A short binary segmented control makes optional effects read as an explicit
/// choice, using the same control language as the scene's other tab choices.
private struct SceneBooleanTabs: View {
    var title: String
    @Binding var isOn: Bool
    var enabledTitle: String
    var enabledSymbol: String
    var disabledTitle: String
    var disabledSymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.fgMuted)
            HStack(spacing: 6) {
                choice(title: enabledTitle, symbol: enabledSymbol, isSelected: isOn) { isOn = true }
                choice(title: disabledTitle, symbol: disabledSymbol, isSelected: !isOn) { isOn = false }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func choice(title: String, symbol: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), help: title, action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.86))
            .background(isSelected ? Color.white.opacity(0.18) : Theme.overlay,
                        in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.85) : Theme.overlay)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

private struct BrowserURLField: NSViewRepresentable {
    @Binding var url: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = url
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.placeholderString = "URL"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if !context.coordinator.isEditing {
            field.stringValue = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: $url) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var url: Binding<String>
        var isEditing = false
        init(url: Binding<String>) { self.url = url }

        func controlTextDidBeginEditing(_ obj: Notification) { isEditing = true }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            url.wrappedValue = field.stringValue
        }
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            url.wrappedValue = field.stringValue
            isEditing = false
        }
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
