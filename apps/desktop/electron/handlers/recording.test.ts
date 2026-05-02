import { describe, expect, it, vi } from "vitest";
import { createDefaultState } from "../state";
import { registerRecordingHandlers } from "./recording";

function registerHandlers() {
	const handlers = new Map<string, (args: unknown) => unknown>();
	const state = createDefaultState();
	const emit = vi.fn();

	registerRecordingHandlers(
		(channel, handler) => {
			handlers.set(channel, handler);
		},
		() => state,
		(updater) => updater(state),
		() => "/tmp",
		emit,
	);

	return { handlers, state, emit };
}

describe("recording handlers", () => {
	it("does not throw the unavailable ScreenCaptureKit start error in Electron", async () => {
		const { handlers } = registerHandlers();
		const start = handlers.get("start_native_screen_recording");

		await expect(start?.({})).resolves.toBe("");
	});

	it("clears recording state when native stop is requested", async () => {
		const { handlers, state, emit } = registerHandlers();
		state.nativeScreenRecordingActive = true;
		state.currentVideoPath = "/tmp/recording.webm";

		await expect(handlers.get("stop_native_screen_recording")?.({})).resolves.toBe(
			"/tmp/recording.webm",
		);

		expect(state.nativeScreenRecordingActive).toBe(false);
		expect(emit).toHaveBeenCalledWith("recording-state-changed", false);
	});
});
