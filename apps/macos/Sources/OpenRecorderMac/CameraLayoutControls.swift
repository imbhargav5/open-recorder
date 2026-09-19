import SwiftUI

struct CameraLayoutControls: View {
    @Binding var settings: FacecamSettings
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraLayoutPicker(selection: layoutBinding)
            if layoutBinding.wrappedValue.hasScreenPanel {
                CameraSidePicker(selection: sideBinding, layout: settings.resolvedLayout)
                CameraScreenFitPicker(selection: screenFitBinding)
                InspectorSwitch(title: "Match camera corners", isOn: matchCornersBinding)
                if !settings.resolvedMatchCameraCorners {
                    InspectorSlider(title: "Screen Radius", valueText: "\(Int(settings.resolvedScreenCornerRadius))px",
                        value: screenRadiusBinding, range: 0...100, step: 1, onEditingChanged: onEditingChanged)
                }
                InspectorSlider(title: "Camera Width", valueText: "\(Int(widthBinding.wrappedValue))%",
                    value: widthBinding, range: 10...70, step: 1, onEditingChanged: onEditingChanged)
                InspectorSlider(title: "Gap", valueText: "\(Int(gapBinding.wrappedValue))%",
                    value: gapBinding, range: 0...12, step: 1, onEditingChanged: onEditingChanged)
            }
            if layoutBinding.wrappedValue != .overlay {
                InspectorSwitch(title: "Keep face centered", isOn: Binding(
                    get: { settings.keepsFaceCentered }, set: { settings.centerFace = $0 }))
                InspectorSlider(title: "Padding", valueText: "\(Int(paddingBinding.wrappedValue))%",
                    value: paddingBinding, range: 0...20, step: 1, onEditingChanged: onEditingChanged)
                Text(layoutBinding.wrappedValue == .cameraOnly
                    ? "Camera fills the canvas. Screen audio is kept."
                    : (settings.resolvedScreenFit == .cover
                        ? "Cover fills the screen panel, cropping the edges."
                        : "Fit keeps the full screen visible at its original aspect ratio."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Divider()
            CameraTransitionControls(settings: $settings, onEditingChanged: onEditingChanged)
        }
    }

    private var layoutBinding: Binding<CameraLayout> {
        Binding(get: { settings.resolvedLayout }, set: { settings.layout = $0.rawValue })
    }
    private var screenFitBinding: Binding<CameraScreenFit> {
        Binding(get: { settings.resolvedScreenFit }, set: { settings.screenFit = $0.rawValue })
    }
    private var matchCornersBinding: Binding<Bool> {
        Binding(get: { settings.resolvedMatchCameraCorners }, set: {
            if !$0 && settings.screenCornerRadius == nil { settings.screenCornerRadius = settings.cornerRadius }
            settings.matchCameraCorners = $0
        })
    }
    private var screenRadiusBinding: Binding<Double> {
        value(\.screenCornerRadius, resolved: \.resolvedScreenCornerRadius)
    }
    private var sideBinding: Binding<Bool> {
        Binding(get: { settings.resolvedCameraOnLeft }, set: { settings.cameraOnLeft = $0 })
    }
    private func value(_ keyPath: WritableKeyPath<FacecamSettings, Double?>,
                       resolved: KeyPath<FacecamSettings, Double>) -> Binding<Double> {
        Binding(get: { settings[keyPath: resolved] }, set: { settings[keyPath: keyPath] = $0 })
    }
    private var widthBinding: Binding<Double> { value(\.cameraWidthPercent, resolved: \.resolvedCameraWidth) }
    private var gapBinding: Binding<Double> { value(\.layoutGap, resolved: \.resolvedLayoutGap) }
    private var paddingBinding: Binding<Double> { value(\.layoutPadding, resolved: \.resolvedLayoutPadding) }
}


private struct CameraLayoutPicker: View {
    @Binding var selection: CameraLayout
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(CameraLayout.allCases) { layout in
                CameraOptionTile(title: layout == .sideBySide ? "Screen + camera" : layout.title,
                                 help: layout.title, isSelected: selection == layout) {
                    selection = layout
                } thumbnail: {
                    CameraLayoutThumbnail(layout: layout)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera layout")
    }
}

/// Shares the cursor-style tile appearance across layout, side and sizing choices.
private struct CameraOptionTile<Thumbnail: View>: View {
    var title: String
    var help: String
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var thumbnail: () -> Thumbnail

    var body: some View {
        StudioButton(hitTarget: .rounded(Theme.radiusMd), help: help, action: action) {
            VStack(spacing: 5) {
                thumbnail()
                    .frame(width: 50, height: 34)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
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

private struct CameraSidePicker: View {
    @Binding var selection: Bool
    var layout: CameraLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Camera side")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 2), spacing: 6) {
                ForEach([true, false], id: \.self) { left in
                    CameraOptionTile(title: left ? "Left" : "Right", help: left ? "Camera on the left" : "Camera on the right",
                                     isSelected: selection == left) {
                        selection = left
                    } thumbnail: {
                        CameraLayoutThumbnail(layout: layout)
                            .scaleEffect(x: left == (layout == .split) ? 1 : -1, y: 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera side")
    }
}

private struct CameraScreenFitPicker: View {
    @Binding var selection: CameraScreenFit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Screen sizing")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 2), spacing: 6) {
                ForEach(CameraScreenFit.allCases) { fit in
                    CameraOptionTile(title: fit.title,
                                     help: fit == .fit ? "Keep the full screen visible" : "Fill the panel, cropping the edges",
                                     isSelected: selection == fit) {
                        selection = fit
                    } thumbnail: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 48, height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.3))
                                    .frame(width: 44, height: fit == .fit ? 14 : 24)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.system(size: fit == .fit ? 11 : 18))
                                    }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.primary.opacity(0.65), lineWidth: 1)
                            }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screen sizing")
    }
}

private struct CameraLayoutThumbnail: View {
    var layout: CameraLayout

    var body: some View {
        Group {
            switch layout {
            case .overlay:
                panel(width: 48, height: 28, camera: false)
                    .overlay(alignment: .bottomTrailing) {
                        panel(width: 16, height: 16, camera: true).padding(2)
                    }
            case .cameraOnly:
                panel(width: 48, height: 28, camera: true)
            case .split:
                HStack(spacing: 4) {
                    panel(width: 22, height: 28, camera: true)
                    panel(width: 22, height: 28, camera: false)
                }
            case .sideBySide:
                HStack(spacing: 4) {
                    panel(width: 30, height: 28, camera: false)
                    panel(width: 14, height: 14, camera: true)
                }
            }
        }
    }

    private func panel(width: CGFloat, height: CGFloat, camera: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.primary.opacity(camera ? 0.35 : 0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.primary.opacity(camera ? 0.85 : 0.45), lineWidth: 1)
            }
            .overlay {
                Image(systemName: camera ? "person.fill" : "rectangle")
                    .font(.system(size: min(width, height) * (camera ? 0.55 : 0.4), weight: .medium))
            }
            .frame(width: width, height: height)
    }
}


private struct CameraTransitionControls: View {
    @Binding var settings: FacecamSettings
    var onEditingChanged: (Bool) -> Void

    var body: some View {
        DisclosureGroup("Layout transition") {
            VStack(alignment: .leading, spacing: 12) {
                InspectorSlider(title: "Duration", valueText: transition.duration == 0 ? "Instant" : String(format: "%.2f s", transition.duration),
                    value: value(\.duration), range: 0...2, step: 0.01, onEditingChanged: onEditingChanged)
                    .help("Shorter is faster. The chosen duration is used in playback and export. If the incoming segment is shorter, the transition uses its full length.")
                if transition.duration > 0 {
                    Picker("Motion", selection: value(\.motion)) {
                        ForEach(CameraLayoutTransition.Motion.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if transition.motion == .ease {
                        Picker("Easing", selection: value(\.easing)) {
                            ForEach(CameraLayoutTransition.Easing.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                    } else {
                        InspectorSlider(title: "Bounce", valueText: percent(transition.bounce),
                            value: value(\.bounce), range: 0...1, step: 0.01, onEditingChanged: onEditingChanged)
                            .help("Low bounce is gently damped. Higher bounce adds a playful spring.")
                    }
                    InspectorSlider(title: "Blur", valueText: percent(transition.blur),
                        value: value(\.blur), range: 0...1, step: 0.01, onEditingChanged: onEditingChanged)
                    InspectorSlider(title: "Fade", valueText: percent(transition.fade),
                        value: value(\.fade), range: 0...1, step: 0.01, onEditingChanged: onEditingChanged)
                }
                Text("Controls how the screen and camera move into this layout. Blur and fade peak midway, then clear.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Reset transition") { settings.layoutTransition = nil }
                    .disabled(settings.layoutTransition == nil)
                    .help("Restore the smooth 0.42-second default, with blur and fade off.")
            }
            .padding(.top, 8)
        }
    }

    private var transition: CameraLayoutTransition { settings.resolvedLayoutTransition }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func value<T>(_ keyPath: WritableKeyPath<CameraLayoutTransition, T>) -> Binding<T> {
        Binding(get: { transition[keyPath: keyPath] }, set: {
            var next = transition
            next[keyPath: keyPath] = $0
            settings.layoutTransition = next.clamped
        })
    }
}
