import { describe, expect, it } from "vitest";
import type { ZoomEaseType, ZoomRegion } from "../types";
import { createDefaultZoomEasing } from "../types";
import { easeOutScreenStudio } from "./mathUtils";
import { computeRegionStrength } from "./zoomRegionUtils";

function makeZoomRegion(overrides: Partial<ZoomRegion> = {}): ZoomRegion {
	return {
		id: "zoom-1",
		startMs: 1000,
		endMs: 2000,
		depth: 3,
		focus: { cx: 0.5, cy: 0.5 },
		...createDefaultZoomEasing(),
		...overrides,
	};
}

describe("zoomRegionUtils", () => {
	it("uses per-region ease-in and ease-out durations", () => {
		const region = makeZoomRegion({
			easeIn: { durationMs: 1000, type: "linear" },
			easeOut: { durationMs: 500, type: "linear" },
		});

		expect(computeRegionStrength(region, 500)).toBe(0);
		expect(computeRegionStrength(region, 1000)).toBeCloseTo(0.5);
		expect(computeRegionStrength(region, 1500)).toBe(1);
		expect(computeRegionStrength(region, 2250)).toBeCloseTo(0.5);
		expect(computeRegionStrength(region, 2501)).toBe(0);
	});

	it.each([
		["linear", 0.5],
		["ease-in", 0.125],
		["ease-out", 0.875],
		["ease-in-out", 0.5],
		["smooth", easeOutScreenStudio(0.5)],
	] satisfies Array<[ZoomEaseType, number]>)("applies %s easing to zoom-in strength", (type, expected) => {
		const region = makeZoomRegion({
			easeIn: { durationMs: 1000, type },
		});

		expect(computeRegionStrength(region, 1000)).toBeCloseTo(expected);
	});

	it.each([
		["linear", 0.5],
		["ease-in", 0.875],
		["ease-out", 0.125],
		["ease-in-out", 0.5],
		["smooth", 1 - easeOutScreenStudio(0.5)],
	] satisfies Array<[ZoomEaseType, number]>)("applies %s easing to zoom-out strength", (type, expected) => {
		const region = makeZoomRegion({
			easeOut: { durationMs: 1000, type },
		});

		expect(computeRegionStrength(region, 2500)).toBeCloseTo(expected);
	});
});
