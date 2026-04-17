/**
 * Cursor telemetry IPC handlers.
 * Mirrors src-tauri/src/commands/cursor.rs.
 */

import fs from "node:fs";
import type { AppState, CursorTelemetryPoint } from "../state.js";

function telemetryPathForVideo(videoPath: string): string {
	return videoPath
		.replace(/\.mov$/, "")
		.replace(/\.mp4$/, "")
		.replace(/\.webm$/, "")
		.concat(".cursor.json");
}

function cursorTelemetryPayload(samples: CursorTelemetryPoint[]): unknown {
	return { samples, clicks: [] };
}

async function writeCursorTelemetrySidecar(
	videoPath: string,
	samples: CursorTelemetryPoint[],
): Promise<void> {
	const telemetryPath = telemetryPathForVideo(videoPath);
	const payload = cursorTelemetryPayload(samples);
	await fs.promises.writeFile(telemetryPath, JSON.stringify(payload, null, 2));
}

export function registerCursorHandlers(
	handle: (channel: string, handler: (args: unknown) => unknown) => void,
	getState: () => AppState,
	setState: (updater: (s: AppState) => void) => void,
): void {
	handle("get_cursor_telemetry", (args) => {
		const { videoPath } = args as { videoPath: string };
		const telemetryPath = telemetryPathForVideo(videoPath);
		try {
			const data = fs.readFileSync(telemetryPath, "utf-8");
			return JSON.parse(data);
		} catch {
			return cursorTelemetryPayload([]);
		}
	});

	handle("start_cursor_telemetry_capture", () => {
		const state = getState();
		if (state.cursorTelemetryCapture !== null) {
			throw new Error("Cursor telemetry capture is already running");
		}

		setState((s) => {
			s.cursorTelemetry = [];
		});

		const samples: CursorTelemetryPoint[] = [];
		let running = true;

		// On Linux we could poll X11, on macOS use native APIs.
		// For now, use a simple interval-based sampler as a stub.
		const startedAt = Date.now();
		const intervalId = setInterval(() => {
			if (!running) return;
			// In a real implementation, query cursor position from the OS.
			// For now, emit a placeholder sample so the array is non-empty.
			const point: CursorTelemetryPoint = {
				x: 0,
				y: 0,
				timestamp: Date.now() - startedAt,
				cursor_type: "arrow",
				click_type: undefined,
			};
			samples.push(point);
		}, 33);

		setState((s) => {
			s.cursorTelemetryCapture = {
				stop: () => {
					running = false;
					clearInterval(intervalId);
				},
				samples,
				intervalId,
			};
		});

		return null;
	});

	handle("stop_cursor_telemetry_capture", async (args) => {
		const { videoPath } = args as { videoPath?: string };
		const state = getState();
		const capture = state.cursorTelemetryCapture;

		if (!capture) {
			if (videoPath?.trim()) {
				await writeCursorTelemetrySidecar(videoPath, []);
			}
			return null;
		}

		capture.stop();
		const samples = [...capture.samples];

		setState((s) => {
			s.cursorTelemetryCapture = null;
		});

		if (videoPath?.trim()) {
			setState((s) => {
				s.cursorTelemetry = samples;
			});
			await writeCursorTelemetrySidecar(videoPath, samples);
		} else {
			setState((s) => {
				s.cursorTelemetry = [];
			});
		}

		return null;
	});

	handle("set_cursor_scale", (args) => {
		const { scale } = args as { scale: number };
		setState((s) => {
			s.cursorScale = scale;
		});
		return null;
	});

	handle("get_system_cursor_assets", () => {
		const cached = getState().cachedSystemCursorAssets;
		if (cached !== null) return cached;
		// Cursor assets are loaded from platform-specific binaries on macOS.
		// Return empty object for other platforms.
		return {};
	});
}
