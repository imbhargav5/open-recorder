import AVFoundation
import XCTest
@testable import OpenRecorderMac

final class TimelineAudioWaveformTests: XCTestCase {
    func testNoAudioWaveformHasNoSamples() {
        XCTAssertFalse(TimelineAudioWaveform.none.isAvailable)
        XCTAssertTrue(TimelineAudioWaveform.none.samples.isEmpty)
    }

    func testAvailableWaveformClampsSamples() {
        let waveform = TimelineAudioWaveform.available(samples: [-0.4, 0.25, 1.8])

        XCTAssertTrue(waveform.isAvailable)
        XCTAssertEqual(waveform.samples, [0, 0.25, 1])
    }

    func testWaveformBarRendererPreservesPeakWhenResampling() {
        var samples = Array(repeating: 0.1, count: 60)
        samples[28] = 0.95

        let bars = TimelineWaveformBarRenderer.resampledLevels(from: samples, width: 60)

        XCTAssertLessThan(bars.count, samples.count)
        XCTAssertTrue(bars.contains { $0 >= 0.95 })
    }

    func testWaveformBarRendererClampsSmoothedLevels() {
        let levels = TimelineWaveformBarRenderer.smoothedDisplayLevels(from: [-0.5, 1.8, 0.4])

        XCTAssertEqual(levels.count, 3)
        XCTAssertTrue(levels.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testEmptyWaveformReturnsQuietSamples() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: [],
            channelCount: 1,
            targetCount: 5
        )

        XCTAssertEqual(samples.count, 5)
        XCTAssertTrue(samples.allSatisfy { abs($0 - TimelineWaveformDownsampler.quietLevel) < 0.0001 })
    }

    func testNonPositiveTargetCountReturnsNoSamples() {
        XCTAssertTrue(
            TimelineWaveformDownsampler.downsample(
                interleavedSamples: [0.7, 0.2, 0.4],
                channelCount: 1,
                targetCount: 0
            ).isEmpty
        )
    }

    func testInvalidChannelCountReturnsQuietSamples() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: [0.7, 0.2, 0.4],
            channelCount: 0,
            targetCount: 3
        )

        XCTAssertEqual(samples, TimelineWaveformDownsampler.quietSamples(targetCount: 3))
    }

    func testQuietSamplesRejectsNonPositiveTargetCounts() {
        XCTAssertTrue(TimelineWaveformDownsampler.quietSamples(targetCount: 0).isEmpty)
        XCTAssertTrue(TimelineWaveformDownsampler.quietSamples(targetCount: -3).isEmpty)
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

    func testDownsamplerIgnoresTrailingPartialFrame() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: [0.2, 0.4, 1.0],
            channelCount: 2,
            targetCount: 1
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0], 0.3, accuracy: 0.0001)
    }

    func testWaveformAlwaysUsesTargetSampleCount() {
        let samples = TimelineWaveformDownsampler.downsample(
            interleavedSamples: Array(repeating: Float(0.4), count: 100),
            channelCount: 1,
            targetCount: 12
        )

        XCTAssertEqual(samples.count, 12)
    }

    func testWaveformFrameOffsetUsesPresentationTimestamp() {
        let offset = TimelineAudioWaveformLoader.frameOffsetForPresentationTime(
            CMTime(seconds: 2.5, preferredTimescale: 600),
            sampleRate: 48_000,
            fallback: 12
        )

        XCTAssertEqual(offset, 120_000)
    }

    func testWaveformFrameOffsetFallsBackForInvalidPresentationTimestamp() {
        let offset = TimelineAudioWaveformLoader.frameOffsetForPresentationTime(
            CMTime.invalid,
            sampleRate: 48_000,
            fallback: 12
        )

        XCTAssertEqual(offset, 12)
    }

    func testShortTimelineTicksUseSecondLabels() {
        let ticks = TimelineRulerTickBuilder.ticks(duration: 7, maxTickCount: 8)

        XCTAssertEqual(ticks.map(\.time), [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(ticks.map(\.label), ["", "1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    }

    func testHalfSecondTicksAreUnlabeled() {
        let ticks = TimelineRulerTickBuilder.halfSecondTicks(duration: 3)

        XCTAssertEqual(ticks.map(\.time), [0.5, 1.5, 2.5])
        XCTAssertEqual(ticks.map(\.label), ["", "", ""])
    }

    func testVisibleHalfSecondTicksStayWithinWindow() {
        let ticks = TimelineRulerTickBuilder.halfSecondTicks(
            visibleStart: 1,
            visibleDuration: 3,
            totalDuration: 10
        )

        XCTAssertEqual(ticks.map(\.time), [1.5, 2.5, 3.5])
        XCTAssertEqual(ticks.map(\.label), ["", "", ""])
    }

    func testVisibleHalfSecondTicksSanitizeInvalidWindowInputs() {
        let ticks = TimelineRulerTickBuilder.halfSecondTicks(
            visibleStart: .nan,
            visibleDuration: .infinity,
            totalDuration: 3
        )

        XCTAssertEqual(ticks.map(\.time), [0.5, 1.5, 2.5])
        XCTAssertEqual(ticks.map(\.label), ["", "", ""])
    }

    func testLongTimelineTicksUseClockLabels() {
        let ticks = TimelineRulerTickBuilder.ticks(duration: 60, maxTickCount: 8)

        XCTAssertEqual(ticks.map(\.time), [0, 10, 20, 30, 40, 50, 60])
        XCTAssertEqual(ticks.map(\.label), ["0:00", "0:10", "0:20", "0:30", "0:40", "0:50", "1:00"])
    }

    func testVisibleTicksSanitizeInvalidWindowInputs() {
        let ticks = TimelineRulerTickBuilder.ticks(
            visibleStart: .nan,
            visibleDuration: .infinity,
            totalDuration: 4,
            maxTickCount: 4
        )

        XCTAssertEqual(ticks.map(\.time), [0, 2, 4])
        XCTAssertEqual(ticks.map(\.label), ["", "2s", "4s"])
    }

    func testVisibleTicksClampNegativeStartToZero() {
        let ticks = TimelineRulerTickBuilder.ticks(
            visibleStart: -2,
            visibleDuration: 3,
            totalDuration: 5,
            maxTickCount: 4
        )

        XCTAssertEqual(ticks.map(\.time), [0, 1, 2, 3])
        XCTAssertEqual(ticks.map(\.label), ["", "1s", "2s", "3s"])
    }

    func testDurationTicksUseFallbackForNonPositiveDuration() {
        let ticks = TimelineRulerTickBuilder.ticks(duration: 0, maxTickCount: 8)

        XCTAssertEqual(ticks.map(\.time), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ticks.map(\.label), ["", "1s", "2s", "3s", "4s", "5s", "6s"])
    }

    func testHalfSecondTicksUseFallbackForNonPositiveDuration() {
        let ticks = TimelineRulerTickBuilder.halfSecondTicks(duration: 0)

        XCTAssertEqual(ticks.map(\.time), [0.5, 1.5, 2.5, 3.5, 4.5, 5.5])
        XCTAssertEqual(ticks.map(\.label), ["", "", "", "", "", ""])
    }

    func testVisibleHalfSecondTicksClampNegativeStartToZero() {
        let ticks = TimelineRulerTickBuilder.halfSecondTicks(
            visibleStart: -2,
            visibleDuration: 3,
            totalDuration: 5
        )

        XCTAssertEqual(ticks.map(\.time), [0.5, 1.5, 2.5])
        XCTAssertEqual(ticks.map(\.label), ["", "", ""])
    }

    func testVisibleTicksClampStartBeyondTotalDuration() {
        let ticks = TimelineRulerTickBuilder.ticks(
            visibleStart: 12,
            visibleDuration: 4,
            totalDuration: 10,
            maxTickCount: 4
        )

        XCTAssertEqual(ticks.map(\.time), [10])
        XCTAssertEqual(ticks.map(\.label), ["10s"])
    }

    func testVisibleHalfSecondTicksClampStartBeyondTotalDuration() {
        let ticks = TimelineRulerTickBuilder.halfSecondTicks(
            visibleStart: 12,
            visibleDuration: 4,
            totalDuration: 10
        )

        XCTAssertTrue(ticks.isEmpty)
    }
}

final class TimelineSeekMapperTests: XCTestCase {
    func testMidpointMapsToHalfDuration() {
        XCTAssertEqual(TimelineSeekMapper.time(forX: 50, duration: 10, width: 100) ?? -1, 5, accuracy: 0.001)
    }

    func testNegativeXClampsToStart() {
        XCTAssertEqual(TimelineSeekMapper.time(forX: -20, duration: 10, width: 100) ?? -1, 0, accuracy: 0.001)
    }

    func testXBeyondWidthClampsToDuration() {
        XCTAssertEqual(TimelineSeekMapper.time(forX: 140, duration: 10, width: 100) ?? -1, 10, accuracy: 0.001)
    }

    func testInvalidDurationOrWidthReturnsNil() {
        XCTAssertNil(TimelineSeekMapper.time(forX: 50, duration: 0, width: 100))
        XCTAssertNil(TimelineSeekMapper.time(forX: 50, duration: 10, width: 0))
        XCTAssertNil(TimelineSeekMapper.time(forX: 50, duration: .nan, width: 100))
        XCTAssertNil(TimelineSeekMapper.time(forX: .infinity, duration: 10, width: 100))
    }

    func testViewportMappingUsesVisibleWindow() {
        let viewport = TimelineViewport(duration: 100, visibleStart: 20, visibleDuration: 10)

        XCTAssertEqual(TimelineSeekMapper.time(forX: 50, viewport: viewport, width: 100) ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(TimelineSeekMapper.time(forX: -20, viewport: viewport, width: 100) ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(TimelineSeekMapper.time(forX: 140, viewport: viewport, width: 100) ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(TimelineSeekMapper.x(forTime: 30, viewport: viewport, width: 100) ?? -1, 100, accuracy: 0.001)
    }

    func testViewportXMappingRejectsInvalidInputs() {
        let viewport = TimelineViewport(duration: 100, visibleStart: 20, visibleDuration: 10)

        XCTAssertNil(TimelineSeekMapper.x(forTime: .nan, viewport: viewport, width: 100))
        XCTAssertNil(TimelineSeekMapper.x(forTime: 25, viewport: viewport, width: 0))
    }
}

final class TimelineViewportTests: XCTestCase {
    func testFullDurationViewportTracksDurationShrink() {
        let viewport = TimelineViewport.reconciled(
            duration: 50,
            previous: TimelineViewport(duration: 100),
            currentTime: 10
        )

        XCTAssertEqual(viewport.duration, 50, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleDuration, 50, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleStart, 0, accuracy: 0.001)
    }

    func testZoomedVisibleDurationPersistsAcrossDurationChange() {
        let viewport = TimelineViewport.reconciled(
            duration: 50,
            previous: TimelineViewport(duration: 100, visibleStart: 30, visibleDuration: 20),
            currentTime: 35
        )

        XCTAssertEqual(viewport.duration, 50, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleDuration, 20, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleStart, 30, accuracy: 0.001)
    }

    func testShortDurationDisablesZoomAndUsesFullDuration() {
        let viewport = TimelineViewport.reconciled(
            duration: 1.5,
            previous: TimelineViewport(duration: 100, visibleStart: 30, visibleDuration: 20),
            currentTime: 1
        )

        XCTAssertFalse(viewport.isZoomEnabled)
        XCTAssertEqual(viewport.visibleDuration, 1.5, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleStart, 0, accuracy: 0.001)
    }

    func testViewportStartClampsNearEnd() {
        let viewport = TimelineViewport(duration: 100, visibleStart: 95, visibleDuration: 20)

        XCTAssertEqual(viewport.visibleStart, 80, accuracy: 0.001)
        XCTAssertEqual(viewport.visibleEnd, 100, accuracy: 0.001)
    }

    func testSliderValueClampsInvalidVisibleDuration() {
        XCTAssertEqual(TimelineViewport.sliderValue(forVisibleDuration: .nan, duration: 10), 0, accuracy: 0.001)
        XCTAssertEqual(TimelineViewport.sliderValue(forVisibleDuration: -4, duration: 10), 0, accuracy: 0.001)
    }
}

final class VideoPlaybackControllerPreviewSpeedTests: XCTestCase {
    @MainActor
    func testPreviewPlaybackSpeedCyclesThroughPreviewRates() {
        let playback = VideoPlaybackController()

        XCTAssertEqual(playback.previewPlaybackSpeed, 1)
        playback.cyclePreviewPlaybackSpeed()
        XCTAssertEqual(playback.previewPlaybackSpeed, 2)
        playback.cyclePreviewPlaybackSpeed()
        XCTAssertEqual(playback.previewPlaybackSpeed, 4)
        playback.cyclePreviewPlaybackSpeed()
        XCTAssertEqual(playback.previewPlaybackSpeed, 8)
        playback.cyclePreviewPlaybackSpeed()
        XCTAssertEqual(playback.previewPlaybackSpeed, 1)
    }

    @MainActor
    func testPreviewPlaybackSpeedMultipliesClipSpeedEdits() {
        let playback = VideoPlaybackController()
        playback.duration = 8
        playback.previewPlaybackSpeed = 2
        playback.setTimelineEdits(TimelineEditSnapshot(clipSplitTimes: [4], clipSpeeds: [1: 1.5]))

        XCTAssertEqual(playback.effectivePlaybackRate(at: 5), 3, accuracy: 0.001)
    }

    @MainActor
    func testPreviewPlaybackSpeedResetsOnLoadAndClear() {
        let playback = VideoPlaybackController()
        playback.previewPlaybackSpeed = 8

        playback.load(url: URL(fileURLWithPath: "/tmp/open-recorder-preview-speed-reset.mov"))
        XCTAssertEqual(playback.previewPlaybackSpeed, 1)

        playback.previewPlaybackSpeed = 4
        playback.clear()
        XCTAssertEqual(playback.previewPlaybackSpeed, 1)
    }
}

final class TimelineEditingPlanTests: XCTestCase {
    func testExportPlanDropsTrimmedRangesAndRetimesSpeed() {
        let edits = TimelineEditSnapshot(
            trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 3))],
            clipSplitTimes: [4, 6],
            clipSpeeds: [1: 2]
        )

        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)

        XCTAssertEqual(plan.outputDuration, 6, accuracy: 0.001)
        XCTAssertFalse(plan.segments.contains { $0.sourceStart >= 2 && $0.sourceEnd <= 3 })
        XCTAssertTrue(plan.segments.contains { $0.sourceStart == 4 && $0.sourceEnd == 6 && $0.speed == 2 })
    }

    func testExportPlanIncludesClipSplitBoundaries() {
        let edits = TimelineEditSnapshot(clipSplitTimes: [2])

        let plan = TimelineExportEditPlan.build(duration: 5, edits: edits)

        XCTAssertEqual(plan.segments.count, 2)
        XCTAssertEqual(plan.segments[0].sourceStart, 0, accuracy: 0.001)
        XCTAssertEqual(plan.segments[0].sourceEnd, 2, accuracy: 0.001)
        XCTAssertEqual(plan.segments[1].sourceStart, 2, accuracy: 0.001)
        XCTAssertEqual(plan.segments[1].sourceEnd, 5, accuracy: 0.001)
        XCTAssertEqual(plan.outputDuration, 5, accuracy: 0.001)
    }

    func testExportPlanRetimesInitialClipSpeedWithoutSplits() {
        let edits = TimelineEditSnapshot(clipSpeeds: [0: 2])

        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)

        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].speed, 2, accuracy: 0.001)
        XCTAssertEqual(plan.outputDuration, 4, accuracy: 0.001)
    }

    func testExportPlanOmitsDeletedClipSpan() {
        let edits = TimelineEditSnapshot(
            trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 5))],
            clipSplitTimes: [2, 5]
        )

        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)

        XCTAssertEqual(plan.outputDuration, 5, accuracy: 0.001)
        XCTAssertEqual(plan.segments.map(\.sourceStart), [0, 5])
        XCTAssertEqual(plan.segments.map(\.sourceEnd), [2, 8])
    }

    func testExportPlanMapsSourceSpanToEditedOutputSpans() {
        let edits = TimelineEditSnapshot(
            trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 3))],
            clipSplitTimes: [4, 6],
            clipSpeeds: [1: 2]
        )
        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)

        let spans = plan.outputSpans(forSourceSpan: TimelineSpan(start: 1, end: 6))

        XCTAssertEqual(spans.count, 3)
        XCTAssertEqual(spans[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(spans[0].end, 2, accuracy: 0.001)
        XCTAssertEqual(spans[1].start, 2, accuracy: 0.001)
        XCTAssertEqual(spans[1].end, 3, accuracy: 0.001)
        XCTAssertEqual(spans[2].start, 3, accuracy: 0.001)
        XCTAssertEqual(spans[2].end, 4, accuracy: 0.001)
    }

    func testExportPlanDropsFullyTrimmedSourceSpan() {
        let edits = TimelineEditSnapshot(
            trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 5))]
        )
        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)

        XCTAssertTrue(plan.outputSpans(forSourceSpan: TimelineSpan(start: 3, end: 4)).isEmpty)
    }

    func testExportZoomEffectIgnoresFullyTrimmedRegion() {
        let zoom = TimelineZoomRegion(span: TimelineSpan(start: 3, end: 4), depth: 2)
        let edits = TimelineEditSnapshot(
            zoomRegions: [zoom],
            trimRegions: [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 5))]
        )
        let plan = TimelineExportEditPlan.build(duration: 8, edits: edits)

        XCTAssertNil(TimelineZoomCanvasTransform.activeEffect(edits: edits, editPlan: plan, outputTime: 2.5))
    }

    @MainActor
    func testClipSplitUsesPlayheadAndDeduplicatesNearbySplits() {
        let edits = TimelineEditDriver()

        edits.addClipSplit(at: 3, duration: 10)
        edits.addClipSplit(at: 3.01, duration: 10)

        XCTAssertEqual(edits.clipSplitTimes.count, 1)
        XCTAssertEqual(edits.clipSplitTimes[0], 3, accuracy: 0.001)
    }

    @MainActor
    func testAddingTrimRegionIsDisabled() {
        let edits = TimelineEditDriver()

        edits.add(.trim, at: 3, duration: 10)

        XCTAssertTrue(edits.trimRegions.isEmpty)
        XCTAssertNil(edits.selectedKind)
        XCTAssertEqual(edits.statusMessage, "Use clip splitting instead of trim sections.")
    }

    @MainActor
    func testSelectingClipClearsRegionSelection() {
        let edits = TimelineEditDriver()
        edits.add(.zoom, at: 2, duration: 10)

        edits.selectClip(index: 1)

        XCTAssertNil(edits.selectedKind)
        XCTAssertNil(edits.selectedID)
        XCTAssertEqual(edits.selectedClipIndex, 1)
        XCTAssertTrue(edits.hasSelection)
    }

    @MainActor
    func testRemovingClipSplitClearsClipSelection() {
        let edits = TimelineEditDriver()
        edits.clipSplitTimes = [2, 4]
        edits.selectClip(index: 1)

        edits.removeClipSplit(at: 2, duration: 8)

        XCTAssertEqual(edits.clipSplitTimes, [4])
        XCTAssertNil(edits.selectedClipIndex)
        XCTAssertFalse(edits.hasSelection)
    }

    @MainActor
    func testDeletingSelectedClipAddsTrimRegion() {
        let edits = TimelineEditDriver()
        edits.clipSplitTimes = [2, 5]
        edits.selectClip(index: 1)

        edits.deleteSelection(duration: 8)

        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 2, end: 5)])
        XCTAssertNil(edits.selectedClipIndex)
        XCTAssertEqual(edits.statusMessage, "Deleted clip 2.")
    }

    @MainActor
    func testContextDeletingRecordingClipAddsExactTrimRegion() {
        let edits = TimelineEditDriver()
        edits.clipSplitTimes = [2, 5]

        XCTAssertTrue(edits.canDeleteRecordingClip(index: 1, duration: 8))

        edits.deleteRecordingClip(index: 1, duration: 8)

        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 2, end: 5)])
        XCTAssertEqual(edits.statusMessage, "Deleted clip 2.")
        XCTAssertFalse(edits.canDeleteRecordingClip(index: 1, duration: 8))
    }

    @MainActor
    func testContextDeletingOnlyPlayableRecordingClipIsBlocked() {
        let edits = TimelineEditDriver()
        edits.clipSplitTimes = [2]
        edits.trimRegions = [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 8))]

        XCTAssertFalse(edits.canDeleteRecordingClip(index: 0, duration: 8))

        edits.deleteRecordingClip(index: 0, duration: 8)

        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 2, end: 8)])
        XCTAssertEqual(edits.statusMessage, "Cannot delete the only playable clip.")
    }

    @MainActor
    func testDeletingSelectedClipIsUndoableAndRedoable() {
        let edits = TimelineEditDriver()
        edits.clipSplitTimes = [2, 5]
        edits.selectClip(index: 1)

        edits.deleteSelection(duration: 8)
        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 2, end: 5)])

        edits.undo()
        XCTAssertTrue(edits.trimRegions.isEmpty)

        edits.redo()
        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 2, end: 5)])
    }

    @MainActor
    func testDeletingOnlyPlayableClipIsBlocked() {
        let edits = TimelineEditDriver()
        edits.selectClip(index: 0)

        edits.deleteSelection(duration: 8)

        XCTAssertTrue(edits.trimRegions.isEmpty)
        XCTAssertEqual(edits.selectedClipIndex, 0)
        XCTAssertEqual(edits.statusMessage, "Cannot delete the only playable clip.")
        XCTAssertFalse(edits.canUndo)
    }

    @MainActor
    func testDeletingSelectedClipMergesAdjacentTrimRegions() {
        let edits = TimelineEditDriver()
        edits.clipSplitTimes = [2, 4, 6]
        edits.trimRegions = [TimelineTrimRegion(span: TimelineSpan(start: 2, end: 4))]
        edits.selectClip(index: 2)

        edits.deleteSelection(duration: 8)

        XCTAssertEqual(edits.trimRegions.map(\.span), [TimelineSpan(start: 2, end: 6)])
    }

    @MainActor
    func testSplittingClipCopiesSpeedToBothSlices() {
        let edits = TimelineEditDriver()
        edits.updateClipSpeed(index: 0, speed: 1.5)

        edits.addClipSplit(at: 3, duration: 8)

        let segments = edits.snapshot.clipSegments(duration: 8)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speed, 1.5, accuracy: 0.001)
        XCTAssertEqual(segments[1].speed, 1.5, accuracy: 0.001)
    }

    @MainActor
    func testUndoRedoAddedZoomRegion() {
        let edits = TimelineEditDriver()

        edits.add(.zoom, at: 2, duration: 10)

        XCTAssertEqual(edits.zoomRegions.count, 1)
        XCTAssertTrue(edits.canUndo)

        edits.undo()

        XCTAssertTrue(edits.zoomRegions.isEmpty)
        XCTAssertFalse(edits.canUndo)
        XCTAssertTrue(edits.canRedo)

        edits.redo()

        XCTAssertEqual(edits.zoomRegions.count, 1)
    }

    @MainActor
    func testUndoRedoClipSplitAndMerge() {
        let edits = TimelineEditDriver()

        edits.addClipSplit(at: 2, duration: 8)
        XCTAssertEqual(edits.clipSplitTimes, [2])

        edits.undo()
        XCTAssertTrue(edits.clipSplitTimes.isEmpty)

        edits.redo()
        XCTAssertEqual(edits.clipSplitTimes, [2])

        edits.removeClipSplit(at: 2, duration: 8)
        XCTAssertTrue(edits.clipSplitTimes.isEmpty)

        edits.undo()
        XCTAssertEqual(edits.clipSplitTimes, [2])
    }

    @MainActor
    func testUndoRedoDeleteResetZoomDepthAndClipSpeed() {
        let edits = TimelineEditDriver()
        edits.add(.zoom, at: 1, duration: 8)
        let zoomID = edits.zoomRegions[0].id
        edits.addClipSplit(at: 4, duration: 8)
        edits.selectClip(index: 0)
        edits.updateClipSpeed(index: 0, speed: 1.5)

        edits.undo()
        XCTAssertEqual(edits.clipSpeed(index: 0), 1.0)

        edits.redo()
        XCTAssertEqual(edits.clipSpeed(index: 0), 1.5)

        edits.updateZoomDepth(id: zoomID, depth: 2.0)
        XCTAssertEqual(edits.zoomRegions[0].depth, 2.0, accuracy: 0.001)

        edits.undo()
        XCTAssertEqual(edits.zoomRegions[0].depth, 1.75, accuracy: 0.001)

        edits.select(.zoom, id: zoomID)
        edits.deleteSelection()
        XCTAssertTrue(edits.zoomRegions.isEmpty)

        edits.undo()
        XCTAssertEqual(edits.zoomRegions.count, 1)

        edits.reset()
        XCTAssertFalse(edits.snapshot.hasEdits)

        edits.undo()
        XCTAssertTrue(edits.snapshot.hasEdits)
    }

    @MainActor
    func testTimelineTransactionCollapsesSpanUpdatesIntoOneUndoStep() {
        let edits = TimelineEditDriver()
        edits.add(.zoom, at: 1, duration: 8)
        let zoomID = edits.zoomRegions[0].id
        let originalSpan = edits.zoomRegions[0].span
        edits.resetHistory()

        edits.beginUndoTransaction()
        edits.updateSpan(kind: .zoom, id: zoomID, span: TimelineSpan(start: 2, end: 3), duration: 8)
        edits.updateSpan(kind: .zoom, id: zoomID, span: TimelineSpan(start: 3, end: 4), duration: 8)
        edits.endUndoTransaction()

        XCTAssertTrue(edits.canUndo)
        XCTAssertEqual(edits.zoomRegions[0].span, TimelineSpan(start: 3, end: 4))

        edits.undo()

        XCTAssertEqual(edits.zoomRegions[0].span, originalSpan)
        XCTAssertFalse(edits.canUndo)
        XCTAssertTrue(edits.canRedo)
    }

    @MainActor
    func testRedoIsClearedAfterNewTimelineEdit() {
        let edits = TimelineEditDriver()
        edits.add(.zoom, at: 1, duration: 8)
        edits.undo()
        XCTAssertTrue(edits.canRedo)

        edits.addClipSplit(at: 3, duration: 8)

        XCTAssertFalse(edits.canRedo)
    }

    @MainActor
    func testAddedRegionStartsAtPlayheadWhenNearClipEnd() {
        let edits = TimelineEditDriver()

        edits.add(.zoom, at: 9.8, duration: 10)

        let span = edits.zoomRegions.first?.span
        XCTAssertEqual(span?.start ?? -1, 9.8, accuracy: 0.001)
        XCTAssertEqual(span?.end ?? -1, 10, accuracy: 0.001)
    }

    func testSnapshotReturnsActiveRegions() {
        let zoom = TimelineZoomRegion(span: TimelineSpan(start: 1, end: 2), depth: 2.2)
        let annotation = TimelineAnnotationRegion(span: TimelineSpan(start: 1.5, end: 3.5), text: "Hello")
        let edits = TimelineEditSnapshot(
            zoomRegions: [zoom],
            annotationRegions: [annotation],
            clipSplitTimes: [3, 4],
            clipSpeeds: [1: 1.5]
        )

        XCTAssertEqual(edits.activeZoom(at: 1.25)?.depth, 2.2)
        XCTAssertEqual(edits.activeSpeed(at: 3.25, duration: 6), 1.5)
        XCTAssertEqual(edits.annotations(at: 2).first?.text, "Hello")
        XCTAssertNil(edits.activeZoom(at: 2.5))
    }
}
