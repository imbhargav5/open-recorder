/**
 * Cursor telemetry IPC handlers.
 * Mirrors src-tauri/src/commands/cursor.rs.
 */

import fs from "node:fs";
import { screen } from "electron";
import type {
	AppState,
	CursorTelemetryBounds,
	CursorTelemetryPoint,
	SelectedSource,
} from "../state.js";

const CURSOR_SAMPLE_INTERVAL_MS = 16;

function telemetryPathForVideo(videoPath: string): string {
	return videoPath
		.replace(/\.mov$/, "")
		.replace(/\.mp4$/, "")
		.replace(/\.webm$/, "")
		.concat(".cursor.json");
}

function clamp(value: number, min: number, max: number) {
	return Math.min(Math.max(value, min), max);
}

function getSourceDisplayId(source: SelectedSource | null) {
	const sourceDisplayId = source?.displayId ?? source?.display_id;
	if (!sourceDisplayId) return undefined;

	const numericDisplayId = Number(sourceDisplayId);
	return Number.isFinite(numericDisplayId) ? numericDisplayId : undefined;
}

function getDisplayBoundsForSource(source: SelectedSource | null): CursorTelemetryBounds {
	const displays = screen.getAllDisplays();
	const sourceDisplayId = getSourceDisplayId(source);
	const matchingDisplay =
		sourceDisplayId !== undefined
			? displays.find((display) => display.id === sourceDisplayId)
			: undefined;
	const cursorDisplay = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
	const fallbackDisplay = matchingDisplay ?? cursorDisplay ?? screen.getPrimaryDisplay();
	const { x, y, width, height } = fallbackDisplay.bounds;

	return { x, y, width, height };
}

function sampleCursorPoint(bounds: CursorTelemetryBounds, startedAt: number): CursorTelemetryPoint {
	const point = screen.getCursorScreenPoint();

	return {
		x: clamp(point.x - bounds.x, 0, bounds.width),
		y: clamp(point.y - bounds.y, 0, bounds.height),
		timestamp: Date.now() - startedAt,
		cursor_type: "arrow",
		click_type: undefined,
	};
}

function cursorTelemetryPayload(
	samples: CursorTelemetryPoint[],
	bounds?: CursorTelemetryBounds,
): unknown {
	return {
		width: bounds?.width,
		height: bounds?.height,
		samples,
		clicks: [],
	};
}

async function writeCursorTelemetrySidecar(
	videoPath: string,
	samples: CursorTelemetryPoint[],
	bounds?: CursorTelemetryBounds,
): Promise<void> {
	const telemetryPath = telemetryPathForVideo(videoPath);
	const payload = cursorTelemetryPayload(samples, bounds);
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
		const startedAt = Date.now();
		const bounds = getDisplayBoundsForSource(state.selectedSource);

		samples.push(sampleCursorPoint(bounds, startedAt));
		const intervalId = setInterval(() => {
			if (!running) return;
			samples.push(sampleCursorPoint(bounds, startedAt));
		}, CURSOR_SAMPLE_INTERVAL_MS);

		setState((s) => {
			s.cursorTelemetryCapture = {
				stop: () => {
					running = false;
					clearInterval(intervalId);
				},
				samples,
				bounds,
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
			await writeCursorTelemetrySidecar(videoPath, samples, capture.bounds);
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
