import AVFoundation
import Foundation

struct CaptureDeviceProvider {
    func devices(for mediaType: AVMediaType) -> [CaptureDeviceInfo] {
        let deviceTypes: [AVCaptureDevice.DeviceType] = mediaType == .video
            ? [.builtInWideAngleCamera, .external]
            : [.microphone]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: mediaType,
            position: .unspecified
        )
        let defaultID = AVCaptureDevice.default(for: mediaType)?.uniqueID
        return discovery.devices.map { device in
            CaptureDeviceInfo(
                id: device.uniqueID,
                name: device.localizedName,
                isDefault: device.uniqueID == defaultID
            )
        }
    }
}
