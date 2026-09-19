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
