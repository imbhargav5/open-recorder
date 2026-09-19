import SwiftUI

struct CameraLayoutControls: View {
    @Binding var settings: FacecamSettings
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Layout", selection: layoutBinding) {
                ForEach(CameraLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .pickerStyle(.menu)
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
