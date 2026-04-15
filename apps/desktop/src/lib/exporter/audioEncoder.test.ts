// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AudioProcessor, applyAudioGainToBuffer } from "./audioEncoder";

describe("audioEncoder", () => {
	it("applies gain to float audio buffers and clamps output", () => {
		const samples = new Float32Array([0.25, -0.25, 0.8, -0.8]);

		applyAudioGainToBuffer(samples.buffer, "f32-planar", 0.5);
		expect(samples[0]).toBeCloseTo(0.125);
		expect(samples[1]).toBeCloseTo(-0.125);
		expect(samples[2]).toBeCloseTo(0.4);
		expect(samples[3]).toBeCloseTo(-0.4);

		applyAudioGainToBuffer(samples.buffer, "f32-planar", 4);
		expect(samples[0]).toBeCloseTo(0.5);
		expect(samples[1]).toBeCloseTo(-0.5);
		expect(samples[2]).toBeCloseTo(1);
		expect(samples[3]).toBeCloseTo(-1);
	});

	it("applies gain to unsigned 8-bit PCM around the midpoint", () => {
		const samples = new Uint8Array([128, 255, 0]);

		applyAudioGainToBuffer(samples.buffer, "u8", 0.5);

		expect(Array.from(samples)).toEqual([128, 192, 64]);
	});
});

describe("AudioProcessor metadata load timeout", () => {
	beforeEach(() => {
		vi.useFakeTimers();
	});

	afterEach(() => {
		vi.useRealTimers();
	});

	it("rejects with a timeout error when loadedmetadata never fires", async () => {
		const processor = new AudioProcessor();

		// jsdom never fires loadedmetadata for media elements, which simulates a corrupt
		// or stalled file. The process() call must reject once the 30s timeout elapses.
		const promise = processor.process(
			{} as never, // demuxer – not reached before timeout
			{} as never, // muxer   – not reached before timeout
			"blob:never-fires",
			[],
			[{ id: "s1", startMs: 0, endMs: 1000, speed: 2 as const }],
		);

		// Advance fake timers past the 30-second threshold.
		// Use the synchronous variant so the microtask queue is not flushed until the
		// subsequent `await`, by which point `expect().rejects` has already attached a
		// rejection handler to `promise` (avoiding an unhandled-rejection warning).
		vi.advanceTimersByTime(31_000);

		await expect(promise).rejects.toThrow("Metadata load timed out after 30s");
	});
});
