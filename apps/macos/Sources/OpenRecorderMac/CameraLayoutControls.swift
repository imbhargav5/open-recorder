import SwiftUI

struct CameraLayoutControls: View {
    @Binding var settings: FacecamSettings
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraLayoutPicker(selection: layoutBinding)
            if layoutBinding.wrappedValue.hasScreenPanel {
                Picker("Camera side", selection: sideBinding) {
                    Text("Left").tag(true)
                    Text("Right").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("Screen sizing", selection: screenFitBinding) {
                    ForEach(CameraScreenFit.allCases) { fit in
                        Text(fit.title).tag(fit)
                    }
                }
                .pickerStyle(.segmented)
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
                let isSelected = selection == layout
                StudioButton(hitTarget: .rounded(Theme.radiusMd), help: layout.title) {
                    selection = layout
                } label: {
                    VStack(spacing: 5) {
                        CameraLayoutThumbnail(layout: layout)
                            .frame(width: 50, height: 34)
                            .accessibilityHidden(true)
                        Text(layout == .sideBySide ? "Screen + camera" : layout.title)
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
                .accessibilityLabel(layout.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera layout")
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
                    .help("Shorter is faster. Long transitions are limited to half the incoming segment so the layout has time to settle.")
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
