// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// ── Close-count tracker ───────────────────────────────────────────────────────
const closeCounts = new Map<string, number>();
let frameIdCounter = 0;

function makeVideoFrame(label?: string): VideoFrame {
	const id = label ?? `frame-${++frameIdCounter}`;
	closeCounts.set(id, 0);

	const frame: VideoFrame = {
		_id: id,
		timestamp: 0,
		codedWidth: 1280,
		codedHeight: 720,
		displayWidth: 1280,
		displayHeight: 720,
		close: vi.fn(() => {
			const prev = closeCounts.get(id) ?? 0;
			closeCounts.set(id, prev + 1);
		}),
		clone: vi.fn((): VideoFrame => makeVideoFrame(`${id}-clone`)),
		allocationSize: vi.fn(() => 0),
		copyTo: vi.fn(),
	} as unknown as VideoFrame;

	return frame;
}

// ── StreamingVideoDecoder mock ────────────────────────────────────────────────
type FrameCallback = (
	frame: VideoFrame,
	exportTimestampUs: number,
	sourceTimestampMs: number,
) => Promise<void>;

let savedCallback: FrameCallback | null = null;
let resolveDecodeAll: (() => void) | null = null;
const mockDecoderDestroy = vi.fn(() => {
	resolveDecodeAll?.();
	resolveDecodeAll = null;
});
const mockDecodeAll = vi.fn(
	async (_fps: number, _trim: unknown, _speed: unknown, cb: FrameCallback) => {
		savedCallback = cb;
		await new Promise<void>((resolve) => {
			resolveDecodeAll = resolve;
		});
	},
);
const mockLoadMetadata = vi.fn(async () => ({
	width: 1280,
	height: 720,
	duration: 2,
	streamDuration: 2,
	frameRate: 30,
	codec: "avc1",
	hasAudio: false,
	audioCodec: undefined,
}));

vi.mock("./streamingDecoder", () => ({
	StreamingVideoDecoder: class {
		loadMetadata = mockLoadMetadata;
		decodeAll = mockDecodeAll;
		destroy = mockDecoderDestroy;
		cancel = vi.fn();
	},
}));

// ── Import under test (after mock registration) ───────────────────────────────
const { SyncedVideoProvider } = await import("./syncedVideoProvider");

// ── Helpers ───────────────────────────────────────────────────────────────────
function assertNoDoubleClose() {
	for (const [id, count] of closeCounts) {
		expect(count, `Frame "${id}" was closed ${count} times — expected at most 1`).toBeLessThanOrEqual(1);
	}
}

// ── Tests ─────────────────────────────────────────────────────────────────────
describe("SyncedVideoProvider", () => {
	beforeEach(() => {
		closeCounts.clear();
		frameIdCounter = 0;
		savedCallback = null;
		resolveDecodeAll = null;
		mockDecodeAll.mockClear();
		mockDecoderDestroy.mockClear();
		mockLoadMetadata.mockClear();
	});

	afterEach(() => {
		resolveDecodeAll?.();
		resolveDecodeAll = null;
	});

	// ── destroy() idempotency ─────────────────────────────────────────────────
	describe("destroy() idempotency", () => {
		it("does not throw when destroy() is called on a fresh instance", () => {
			const provider = new SyncedVideoProvider();
			expect(() => provider.destroy()).not.toThrow();
		});

		it("does not throw when destroy() is called twice", () => {
			const provider = new SyncedVideoProvider();
			provider.destroy();
			expect(() => provider.destroy()).not.toThrow();
		});

		it("returns null from getFrameAt after destroy()", async () => {
			const provider = new SyncedVideoProvider();
			provider.destroy();
			await expect(provider.getFrameAt(500)).resolves.toBeNull();
		});
	});

	// ── Race condition: destroy() mid-decode ──────────────────────────────────
	describe("destroy() mid-decode — no double-close", () => {
		it("closes each frame exactly once when destroy() is called after a frame is enqueued", async () => {
			const provider = new SyncedVideoProvider();
			const initPromise = provider.initialize("test.mp4", 30);

			// Wait for loadMetadata + decodeAll wiring
			await new Promise((r) => setTimeout(r, 0));
			expect(savedCallback).not.toBeNull();

			// Emit one frame from the decoder
			const rawFrame = makeVideoFrame("raw-1");
			const callbackPromise = savedCallback!(rawFrame, 0, 100);

			// Let the callback run (enqueue the clone)
			await new Promise((r) => setTimeout(r, 0));

			// Destroy while the frame is still in pendingFrames / decode in-flight
			provider.destroy();

			// Drain remaining async work
			await callbackPromise.catch(() => {});
			await initPromise.catch(() => {});

			assertNoDoubleClose();

			// The raw frame must be closed by the callback (ownership transfer fix)
			expect(closeCounts.get("raw-1")).toBe(1);
			// The enqueued clone must be closed exactly once by destroy()
			expect(closeCounts.get("raw-1-clone")).toBe(1);
		});

		it("closes frames arriving after destroy() exactly once (no stale pendingFrames)", async () => {
			const provider = new SyncedVideoProvider();
			const initPromise = provider.initialize("test.mp4", 30);

			await new Promise((r) => setTimeout(r, 0));
			expect(savedCallback).not.toBeNull();

			// Destroy before any frames are emitted
			provider.destroy();

			// Now emit a frame — the callback should see destroyed=true and close it
			const lateFrame = makeVideoFrame("late-1");
			await savedCallback!(lateFrame, 0, 100).catch(() => {});

			await initPromise.catch(() => {});

			assertNoDoubleClose();
			// The late frame must be closed by the guard at the top of the callback
			expect(closeCounts.get("late-1")).toBe(1);
			// No clone should have been created (callback returned early)
			expect(closeCounts.has("late-1-clone")).toBe(false);
		});

		it("does not crash when destroy() is called while the callback backpressure loop is active", async () => {
			// Fill the queue past the backpressure threshold (24) so the 25th callback
			// enters the `while (pendingFrames.length > 24 && !done)` loop.
			// destroy() is called before the 4 ms setTimeout fires; the loop then exits
			// because done=true, and no frame should be closed more than once.
			mockDecodeAll.mockImplementationOnce(
				async (_fps: number, _trim: unknown, _speed: unknown, cb: FrameCallback) => {
					for (let i = 0; i < 25; i++) {
						const f = makeVideoFrame(`raw-bp-${i}`);
						await cb(f, i * 33333, i * 33);
					}
				},
			);

			const provider = new SyncedVideoProvider();
			const initPromise = provider.initialize("test.mp4", 30);

			// Frames 0-23 enqueue quickly (no backpressure); frame 24 hits the 4 ms wait.
			// Yield enough to let frames 0-23 complete but arrive before the 4 ms elapses.
			await new Promise((r) => setTimeout(r, 1));

			provider.destroy();

			// Wait well past the 4 ms backpressure delay so the callback fully unwinds.
			await new Promise((r) => setTimeout(r, 20));
			await initPromise.catch(() => {});

			assertNoDoubleClose();
		});
	});

	// ── Normal flow: frames returned to caller are independent clones ─────────
	describe("getFrameAt normal flow", () => {
		it("returns null before any frames arrive", async () => {
			const provider = new SyncedVideoProvider();
			const initPromise = provider.initialize("test.mp4", 30);

			// Wait for decodeAll to be wired up
			await new Promise((r) => setTimeout(r, 0));
			expect(savedCallback).not.toBeNull();

			// Signal the mock decoder to finish (no frames emitted → done=true)
			resolveDecodeAll?.();
			resolveDecodeAll = null;
			await initPromise.catch(() => {});

			// done is now true; getFrameAt must return null without hanging
			await expect(provider.getFrameAt(500)).resolves.toBeNull();
			provider.destroy();
		});

		it("returns a cloned frame for a queued timestamp", async () => {
			const provider = new SyncedVideoProvider();
			const initPromise = provider.initialize("test.mp4", 30);

			await new Promise((r) => setTimeout(r, 0));
			expect(savedCallback).not.toBeNull();

			// Emit one frame at t=100 ms
			const rawFrame = makeVideoFrame("gf-raw");
			await savedCallback!(rawFrame, 0, 100);

			// Finish decode so done=true and getFrameAt doesn't block on next frame
			resolveDecodeAll?.();
			resolveDecodeAll = null;
			await initPromise.catch(() => {});

			const result = await provider.getFrameAt(200);
			expect(result).not.toBeNull();

			// The returned frame is a clone — close it ourselves
			result!.close();

			provider.destroy();
		});
	});
});
