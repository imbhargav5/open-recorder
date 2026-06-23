import CoreGraphics
import XCTest
@preconcurrency import ScreenCaptureKit
@testable import OpenRecorderMac

@MainActor
final class NativeScreenRecorderConfigurationTests: XCTestCase {
    func testStreamConfigurationCapturesSystemAudioWhenEnabled() {
        let configuration = NativeScreenRecorder.makeStreamConfiguration(
            width: 1920,
            height: 1080,
            sourceRect: nil,
            options: RecordingCaptureOptions(
                includeMicrophone: false,
                microphoneDeviceID: nil,
                includeSystemAudio: true,
                includeCamera: false,
                cameraDeviceID: nil,
                showCursor: true,
                showClicks: false
            )
        )

        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertEqual(configuration.width, 1920)
        XCTAssertEqual(configuration.height, 1080)
        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertNil(configuration.microphoneCaptureDeviceID)
        XCTAssertEqual(configuration.sampleRate, 48_000)
        XCTAssertEqual(configuration.channelCount, 2)
        XCTAssertFalse(configuration.excludesCurrentProcessAudio)
        XCTAssertFalse(configuration.showsCursor)
    }

    func testStreamConfigurationCapturesSelectedMicrophoneWhenEnabled() {
        let configuration = NativeScreenRecorder.makeStreamConfiguration(
            width: 1280,
            height: 720,
            sourceRect: nil,
            options: RecordingCaptureOptions(
                includeMicrophone: true,
                microphoneDeviceID: "external-mic",
                includeSystemAudio: false,
                includeCamera: false,
                cameraDeviceID: nil,
                showCursor: true,
                showClicks: false
            )
        )

        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertTrue(configuration.captureMicrophone)
        XCTAssertEqual(configuration.microphoneCaptureDeviceID, "external-mic")
    }

    func testStreamConfigurationLeavesSystemAudioOffByDefault() {
        let configuration = NativeScreenRecorder.makeStreamConfiguration(
            width: 1280,
            height: 720,
            sourceRect: CGRect(x: 20, y: 30, width: 640, height: 360),
            options: RecordingCaptureOptions(
                includeMicrophone: false,
                microphoneDeviceID: "stale-device",
                includeSystemAudio: false,
                includeCamera: false,
                cameraDeviceID: nil,
                showCursor: false,
                showClicks: true
            )
        )

        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertEqual(configuration.width, 1280)
        XCTAssertEqual(configuration.height, 720)
        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertNil(configuration.microphoneCaptureDeviceID)
        XCTAssertFalse(configuration.showsCursor)
        XCTAssertTrue(configuration.showMouseClicks)
        XCTAssertEqual(configuration.sourceRect, CGRect(x: 20, y: 30, width: 640, height: 360))
    }

    func testStreamConfigurationCapturesMicrophoneWhenEnabled() {
        let configuration = NativeScreenRecorder.makeStreamConfiguration(
            width: 1280,
            height: 720,
            sourceRect: nil,
            options: RecordingCaptureOptions(
                includeMicrophone: true,
                microphoneDeviceID: "built-in-microphone",
                includeSystemAudio: false,
                includeCamera: false,
                cameraDeviceID: nil,
                showCursor: false,
                showClicks: false
            )
        )

        XCTAssertTrue(configuration.captureMicrophone)
        XCTAssertEqual(configuration.microphoneCaptureDeviceID, "built-in-microphone")
    }
}
