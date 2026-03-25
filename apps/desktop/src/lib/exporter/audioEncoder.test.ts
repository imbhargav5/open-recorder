import { describe, expect, it } from "vitest";
import { applyAudioGainToBuffer } from "./audioEncoder";

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
