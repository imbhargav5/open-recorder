import XCTest
@testable import OpenRecorderMac

final class TimelineAudioWaveformTests: XCTestCase {
    func testEmptyWaveformReturnsQuietSamples() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: [],
            channelCount: 1,
            targetCount: 5
        )

        XCTAssertEqual(samples.count, 5)
        XCTAssertTrue(samples.allSatisfy { abs($0 - TimelineWaveformDownsampler.quietLevel) < 0.0001 })
    }

    func testConstantWaveformKeepsLevel() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: Array(repeating: Float(0.25), count: 20),
            channelCount: 1,
            targetCount: 4
        )

        XCTAssertEqual(samples.count, 4)
        for sample in samples {
            XCTAssertEqual(sample, 0.25, accuracy: 0.0001)
        }
    }

    func testWaveformPreservesSpikes() {
        var source = Array(repeating: Float(0), count: 16)
        source[7] = 0.92

        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: source,
            channelCount: 1,
            targetCount: 4
        )

        XCTAssertTrue(samples.contains { $0 >= 0.92 })
    }

    func testStereoWaveformAveragesChannels() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: [1.0, 0.0, 0.5, -0.5],
            channelCount: 2,
            targetCount: 2
        )

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(samples[1], 0.5, accuracy: 0.0001)
    }

    func testWaveformAlwaysUsesTargetSampleCount() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: Array(repeating: Float(0.4), count: 100),
            channelCount: 1,
            targetCount: 12
        )

        XCTAssertEqual(samples.count, 12)
    }

    func testShortTimelineTicksUseSecondLabels() {
        let ticks = TimelineRulerTickBuilder.ticks(duration: 7, maxTickCount: 8)

        XCTAssertEqual(ticks.map(\.time), [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(ticks.map(\.label), ["", "1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    }

    func testLongTimelineTicksUseClockLabels() {
        let ticks = TimelineRulerTickBuilder.ticks(duration: 60, maxTickCount: 8)

        XCTAssertEqual(ticks.map(\.time), [0, 10, 20, 30, 40, 50, 60])
        XCTAssertEqual(ticks.map(\.label), ["0:00", "0:10", "0:20", "0:30", "0:40", "0:50", "1:00"])
    }
}
