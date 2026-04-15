/**
 * Stale Closure Detection Tests for Jotai State Management
 *
 * Verifies that atoms used inside useEffect/useCallback/setInterval-like
 * patterns capture fresh values (via atom references + store.get) rather
 * than stale captured values.
 *
 * Pattern being tested:
 *   BAD  → capture the VALUE at setup time (goes stale)
 *   GOOD → capture the ATOM REFERENCE and call store.get() at read time (always fresh)
 */

import { atom } from "jotai";
import { createStore } from "jotai/vanilla";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { audioVolumeAtom, isPlayingAtom } from "@/atoms/videoEditor";
import { recordingActiveAtom, microphoneEnabledAtom } from "@/atoms/recording";
import { isCapturingAtom, recordingElapsedAtom } from "@/atoms/launch";

describe("stale closure detection", () => {
	it("captured value is stale after an atom write; atom reference is always fresh", () => {
		const store = createStore();
		const countAtom = atom(0);

		// Simulate capturing the VALUE (stale closure anti-pattern)
		const capturedValue = store.get(countAtom);

		store.set(countAtom, 42);

		// Stale capture: still sees the old value
		expect(capturedValue).toBe(0);

		// Fresh via atom reference: reads current value
		expect(store.get(countAtom)).toBe(42);
	});

	it("simulated setInterval using atom reference always reads current value", () => {
		const store = createStore();
		const counterAtom = atom(0);
		const ticks: number[] = [];

		// Simulate setInterval callback: captures atom ref, not value
		const intervalCallback = () => {
			ticks.push(store.get(counterAtom)); // always fresh
		};

		store.set(counterAtom, 1);
		intervalCallback();
		store.set(counterAtom, 2);
		intervalCallback();
		store.set(counterAtom, 3);
		intervalCallback();

		expect(ticks).toEqual([1, 2, 3]);
	});

	it("simulated setInterval with stale captured value misses updates", () => {
		const store = createStore();
		const counterAtom = atom(0);
		const ticks: number[] = [];

		// Capture the VALUE once (stale anti-pattern)
		const staleValue = store.get(counterAtom);
		const staleCallback = () => {
			ticks.push(staleValue); // always 0, never updates
		};

		store.set(counterAtom, 10);
		staleCallback();
		store.set(counterAtom, 20);
		staleCallback();

		// All ticks see the stale initial value
		expect(ticks).toEqual([0, 0]);
	});

	it("simulated useEffect cleanup captures atom ref and sees updates after re-run", () => {
		const store = createStore();
		const statusAtom = atom("idle");
		const observedStatuses: string[] = [];

		// Simulate useEffect body that reads atom on each execution
		const runEffect = () => {
			observedStatuses.push(store.get(statusAtom));
		};

		runEffect(); // first "render"
		store.set(statusAtom, "recording");
		runEffect(); // second "render"
		store.set(statusAtom, "done");
		runEffect(); // third "render"

		expect(observedStatuses).toEqual(["idle", "recording", "done"]);
	});

	it("write atom updater pattern (prev => next) never reads stale value", () => {
		const store = createStore();
		const countAtom = atom(0);
		const incrementAtom = atom(null, (get, set) => {
			// Uses get() inside the write fn — always reads current state
			set(countAtom, get(countAtom) + 1);
		});

		store.set(countAtom, 100);
		store.set(incrementAtom);
		store.set(incrementAtom);

		// Each increment sees the result of the previous one
		expect(store.get(countAtom)).toBe(102);
	});

	it("subscription callback always receives the current value, not the value at subscribe time", () => {
		const store = createStore();
		const valueAtom = atom("initial");
		const seenInCallback: string[] = [];

		store.sub(valueAtom, () => {
			seenInCallback.push(store.get(valueAtom));
		});

		store.set(valueAtom, "updated");
		store.set(valueAtom, "final");

		expect(seenInCallback).toEqual(["updated", "final"]);
	});

	it("derived atom always computes from fresh dependency, never from stale snapshot", () => {
		const store = createStore();
		const sourceAtom = atom(10);
		const derivedAtom = atom((get) => get(sourceAtom) * 3);

		// Read derived before update
		const beforeUpdate = store.get(derivedAtom);

		store.set(sourceAtom, 20);

		// Read derived after update
		const afterUpdate = store.get(derivedAtom);

		expect(beforeUpdate).toBe(30); // was fresh at time of read
		expect(afterUpdate).toBe(60); // fresh after update
	});

	it("multiple closures with atom references all see the same current state", () => {
		const store = createStore();
		const sharedAtom = atom(0);

		// Simulate three components/hooks each capturing the atom reference
		const readerA = () => store.get(sharedAtom);
		const readerB = () => store.get(sharedAtom);
		const readerC = () => store.get(sharedAtom);

		store.set(sharedAtom, 7);

		expect(readerA()).toBe(7);
		expect(readerB()).toBe(7);
		expect(readerC()).toBe(7);
	});

	it("simulated useCallback: fresh read via store.get in callback sees latest value", () => {
		const store = createStore();
		const thresholdAtom = atom(100);
		const dataAtom = atom(50);

		// Simulate useCallback that captures atom refs (fresh pattern)
		const handleProcess = () => {
			const threshold = store.get(thresholdAtom);
			const data = store.get(dataAtom);
			return data >= threshold;
		};

		expect(handleProcess()).toBe(false); // 50 < 100

		store.set(thresholdAtom, 40);
		expect(handleProcess()).toBe(true); // 50 >= 40

		store.set(dataAtom, 200);
		expect(handleProcess()).toBe(true); // 200 >= 40
	});

	it("real atom: isCapturingAtom read inside a simulated interval stays fresh", () => {
		const store = createStore();
		const snapshots: boolean[] = [];

		const checkCapture = () => {
			snapshots.push(store.get(isCapturingAtom));
		};

		checkCapture(); // false
		store.set(isCapturingAtom, true);
		checkCapture(); // true
		store.set(isCapturingAtom, false);
		checkCapture(); // false

		expect(snapshots).toEqual([false, true, false]);
	});

	it("real atom: recordingElapsedAtom incremented via updater never skips a count", () => {
		const store = createStore();
		const tickAtom = atom(null, (get, set) => {
			set(recordingElapsedAtom, get(recordingElapsedAtom) + 1);
		});

		for (let i = 0; i < 10; i++) {
			store.set(tickAtom);
		}

		expect(store.get(recordingElapsedAtom)).toBe(10);
	});

	it("subscription callback closure over external var sees its own scope correctly", () => {
		const store = createStore();
		const flagAtom = atom(false);
		let externalCounter = 0;

		store.sub(flagAtom, () => {
			// Closure captures externalCounter by reference — demonstrates standard JS closure
			externalCounter += store.get(flagAtom) ? 1 : -1;
		});

		store.set(flagAtom, true); // +1
		store.set(flagAtom, false); // -1
		store.set(flagAtom, true); // +1

		expect(externalCounter).toBe(1); // net: +1 -1 +1 = 1
	});

	it("chained derived atoms each read fresh from their direct dependency", () => {
		const store = createStore();
		const base = atom(1);
		const step1 = atom((get) => get(base) + 10);
		const step2 = atom((get) => get(step1) * 2);
		const step3 = atom((get) => get(step2) - 3);

		store.set(base, 5);

		// step1: 5+10=15, step2: 15*2=30, step3: 30-3=27
		expect(store.get(step3)).toBe(27);

		store.set(base, 0);

		// step1: 0+10=10, step2: 10*2=20, step3: 20-3=17
		expect(store.get(step3)).toBe(17);
	});

	it("atom value captured before multiple writes is stale; re-reading is always current", () => {
		const store = createStore();
		const configAtom = atom({ timeout: 1000, retries: 3 });

		// Captured snapshot — stale after updates
		const snapshot = store.get(configAtom);

		store.set(configAtom, { timeout: 5000, retries: 5 });
		store.set(configAtom, { timeout: 500, retries: 1 });

		// Snapshot is stuck at initial value
		expect(snapshot).toEqual({ timeout: 1000, retries: 3 });

		// Live read reflects the latest value
		expect(store.get(configAtom)).toEqual({ timeout: 500, retries: 1 });
	});

	it("real atom: audioVolumeAtom read freshly inside simulated playback loop", () => {
		const store = createStore();
		const volumeReadings: number[] = [];

		// Simulate a playback render loop that reads volume each frame
		const renderFrame = () => {
			volumeReadings.push(store.get(audioVolumeAtom));
		};

		renderFrame(); // default 1
		store.set(audioVolumeAtom, 0.5);
		renderFrame(); // 0.5
		store.set(audioVolumeAtom, 0);
		renderFrame(); // 0

		expect(volumeReadings).toEqual([1, 0.5, 0]);
	});
});
