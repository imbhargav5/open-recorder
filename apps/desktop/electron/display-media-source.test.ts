import { describe, expect, it } from "vitest";
import { resolveDisplayMediaSource } from "./display-media-source";
import type { SelectedSource } from "./state";

type TestCapturerSource = Parameters<typeof resolveDisplayMediaSource>[1][number];

function screenSource(id: string, displayId: string, name = "Screen"): TestCapturerSource {
	return { id, display_id: displayId, name };
}

function windowSource(id: string, name = "Window"): TestCapturerSource {
	return { id, display_id: "", name };
}

describe("resolveDisplayMediaSource", () => {
	it("prefers the stable display id over a stale sequential screen id", () => {
		const selectedSource: SelectedSource = {
			id: "screen:1:0",
			name: "External Display",
			sourceType: "screen",
			display_id: "200",
		};
		const sources = [
			screenSource("screen:1:0", "100", "Built-in Display"),
			screenSource("screen:2:0", "200", "External Display"),
		];

		expect(resolveDisplayMediaSource(selectedSource, sources)).toBe(sources[1]);
	});

	it("matches windows by exact source id", () => {
		const selectedSource: SelectedSource = {
			id: "window:123:0",
			name: "Demo Window",
			sourceType: "window",
		};
		const sources = [screenSource("screen:1:0", "100"), windowSource("window:123:0")];

		expect(resolveDisplayMediaSource(selectedSource, sources)).toBe(sources[1]);
	});

	it("falls back to the first screen when no selected source matches", () => {
		const sources = [windowSource("window:123:0"), screenSource("screen:1:0", "100")];

		expect(resolveDisplayMediaSource(null, sources)).toBe(sources[1]);
	});
});
