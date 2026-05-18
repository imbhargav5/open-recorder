import SwiftUI

enum CaptureDeviceSelectorWindowMetrics {
    static let width: CGFloat = 360
    static let height: CGFloat = 360
    static let minWidth: CGFloat = 320
    static let minHeight: CGFloat = 260
}

struct MicrophoneSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    private var options: CaptureOptionsState {
        model.captureOptions.state
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose Microphone")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Pick the input to use for the next recording.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)

            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    StudioButton(hitTarget: .rounded(8)) {
                        selectNoMicrophone()
                    } label: {
                        microphoneRow(
                            title: "No Microphone",
                            subtitle: "Do not record microphone audio",
                            isSelected: !options.includeMicrophone
                        )
                    }

                    StudioButton(hitTarget: .rounded(8)) {
                        selectMicrophone(nil)
                    } label: {
                        microphoneRow(
                            title: "System Default",
                            subtitle: "Use the current macOS default",
                            isSelected: options.includeMicrophone && options.selectedMicrophoneDeviceID == nil
                        )
                    }

                    ForEach(options.microphoneDevices) { device in
                        StudioButton(hitTarget: .rounded(8)) {
                            selectMicrophone(device.id)
                        } label: {
                            microphoneRow(
                                title: device.name,
                                subtitle: device.isDefault ? "Current macOS default" : "Microphone",
                                isSelected: options.includeMicrophone && options.selectedMicrophoneDeviceID == device.id
                            )
                        }
                    }

                    if options.microphoneDevices.isEmpty {
                        Text("No devices found")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 220)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack {
                Spacer()
                StudioButton(hitTarget: .rounded(8)) {
                    model.cancelMicrophoneSelection()
                    dismissWindow(id: "microphone-selector")
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(Color.studioPanel.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioBorder)
        }
        .padding(16)
        .background(Color.studioBackground.ignoresSafeArea())
    }

    private func selectMicrophone(_ deviceID: String?) {
        model.selectMicrophoneDevice(deviceID)
        dismissWindow(id: "microphone-selector")
    }

    private func selectNoMicrophone() {
        model.selectNoMicrophoneInput()
        dismissWindow(id: "microphone-selector")
    }

    private func microphoneRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.brand : Color.white.opacity(0.34))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(isSelected ? Color.brand.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.brand.opacity(0.36) : Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

struct CameraSelectorWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    private var options: CaptureOptionsState {
        model.captureOptions.state
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose Camera")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Pick the camera to use for the next recording.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)

            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    StudioButton(hitTarget: .rounded(8)) {
                        selectNoCamera()
                    } label: {
                        cameraRow(
                            title: "No Camera",
                            subtitle: "Do not record facecam video",
                            isSelected: !options.includeCamera
                        )
                    }

                    StudioButton(hitTarget: .rounded(8)) {
                        selectCamera(nil)
                    } label: {
                        cameraRow(
                            title: "System Default",
                            subtitle: "Use the current macOS default",
                            isSelected: options.includeCamera && options.selectedCameraDeviceID == nil
                        )
                    }

                    ForEach(options.cameraDevices) { device in
                        StudioButton(hitTarget: .rounded(8)) {
                            selectCamera(device.id)
                        } label: {
                            cameraRow(
                                title: device.name,
                                subtitle: device.isDefault ? "Current macOS default" : "Camera",
                                isSelected: options.includeCamera && options.selectedCameraDeviceID == device.id
                            )
                        }
                    }

                    if options.cameraDevices.isEmpty {
                        Text("No devices found")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 220)

            Rectangle()
                .fill(Color.studioBorder)
                .frame(height: 1)

            HStack {
                Spacer()
                StudioButton(hitTarget: .rounded(8)) {
                    model.cancelCameraSelection()
                    dismissWindow(id: "camera-selector")
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(Color.studioPanel.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.studioBorder)
        }
        .padding(16)
        .background(Color.studioBackground.ignoresSafeArea())
    }

    private func selectCamera(_ deviceID: String?) {
        model.selectCameraDevice(deviceID)
        dismissWindow(id: "camera-selector")
    }

    private func selectNoCamera() {
        model.selectNoCameraInput()
        dismissWindow(id: "camera-selector")
    }

    private func cameraRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.brand : Color.white.opacity(0.34))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(isSelected ? Color.brand.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.brand.opacity(0.36) : Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
