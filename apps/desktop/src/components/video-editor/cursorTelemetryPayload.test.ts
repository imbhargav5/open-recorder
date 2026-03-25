import { describe, expect, it } from "vitest";

import { normalizeCursorTelemetryPayload } from "./cursorTelemetryPayload";

describe("normalizeCursorTelemetryPayload", () => {
	it("normalizes legacy pixel samples and merges click events", () => {
		const normalized = normalizeCursorTelemetryPayload(
			{
				samples: [
					{
						x: 960,
						y: 540,
						timestamp: 1000,
						cursor_type: "ibeam",
					},
					{
						x: 1920,
						y: 1080,
						timestamp: 2000,
						cursor_type: "pointingHand",
					},
				],
				clicks: [
					{
						x: 960,
						y: 540,
						timestamp: 1500,
						type: "left",
					},
				],
			},
			{
				videoWidth: 1920,
				videoHeight: 1080,
				durationMs: 4000,
			},
		);

		expect(normalized).toEqual([
			{
				timeMs: 1000,
				cx: 0.5,
				cy: 0.5,
				interactionType: "move",
				cursorType: "text",
			},
			{
				timeMs: 1500,
				cx: 0.5,
				cy: 0.5,
				interactionType: "click",
				cursorType: undefined,
			},
			{
				timeMs: 2000,
				cx: 1,
				cy: 1,
				interactionType: "move",
				cursorType: "pointer",
			},
		]);
	});

	it("supports seconds-based timestamps by scaling and rebasing them", () => {
		const normalized = normalizeCursorTelemetryPayload(
			[
				{
					cx: 0.25,
					cy: 0.5,
					t: 10,
				},
				{
					cx: 0.5,
					cy: 0.75,
					t: 12,
					clickType: "right",
				},
			],
			{
				durationMs: 2500,
			},
		);

		expect(normalized).toEqual([
			{
				timeMs: 0,
				cx: 0.25,
				cy: 0.5,
				interactionType: "move",
				cursorType: undefined,
			},
			{
				timeMs: 2000,
				cx: 0.5,
				cy: 0.75,
				interactionType: "right-click",
				cursorType: undefined,
			},
		]);
	});

	it("falls back to observed coordinate extents when dimensions are missing", () => {
		const normalized = normalizeCursorTelemetryPayload({
			samples: [
				{ x: 400, y: 200, timestamp: 0 },
				{ x: 800, y: 400, timestamp: 1000 },
			],
		});

		expect(normalized).toEqual([
			{
				timeMs: 0,
				cx: 0.5,
				cy: 0.5,
				interactionType: "move",
				cursorType: undefined,
			},
			{
				timeMs: 1000,
				cx: 1,
				cy: 1,
				interactionType: "move",
				cursorType: undefined,
			},
		]);
	});
});
