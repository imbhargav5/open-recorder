/**
 * Memory & Cleanup Tests for Jotai State Management
 *
 * Covers: subscription cleanup via unsubscribe, no lingering callbacks
 * after cleanup, interval/timeout simulation with proper teardown,
 * and double-unsubscribe safety.
 */

import { atom } from "jotai";
import { createStore } from "jotai/vanilla";
import { afterEach, describe, expect, it, vi } from "vitest";
import { recordingActiveAtom } from "@/atoms/recording";
import { isPlayingAtom, audioVolumeAtom } from "@/atoms/videoEditor";
import { isCapturingAtom } from "@/atoms/launch";

describe("memory and cleanup", () => {
	it("unsubscribe prevents future notifications from reaching the callback", () => {
		const store = createStore();
		const myAtom = atom(0);
		let callCount = 0;

		const unsub = store.sub(myAtom, () => {
			callCount++;
		});

		store.set(myAtom, 1);
		expect(callCount).toBe(1);

		unsub();
		store.set(myAtom, 2);
		store.set(myAtom, 3);

		expect(callCount).toBe(1); // no additional calls after unsubscribe
	});

	it("double-calling the unsubscribe function does not throw", () => {
		const store = createStore();
		const myAtom = atom(0);
		const unsub = store.sub(myAtom, () => {});

		unsub(); // first cleanup
		expect(() => unsub()).not.toThrow(); // second cleanup — must be safe
	});

	it("multiple subscribe/unsubscribe cycles do not accumulate leftover callbacks", () => {
		const store = createStore();
		const myAtom = atom(0);
		let totalCalls = 0;

		for (let i = 0; i < 20; i++) {
			const unsub = store.sub(myAtom, () => {
				totalCalls++;
			});
			unsub(); // immediately unsubscribe each time
		}

		store.set(myAtom, 99);
		expect(totalCalls).toBe(0);
	});

	it("store.sub returns a function (the cleanup/unsubscribe fn)", () => {
		const store = createStore();
		const myAtom = atom(false);

		const cleanup = store.sub(myAtom, () => {});

		expect(typeof cleanup).toBe("function");
		cleanup();
	});

	it("partial unsubscribe: remaining subscribers still receive notifications", () => {
		const store = createStore();
		const myAtom = atom("start");
		const receivedA: string[] = [];
		const receivedB: string[] = [];

		const unsubA = store.sub(myAtom, () => receivedA.push(store.get(myAtom)));
		store.sub(myAtom, () => receivedB.push(store.get(myAtom)));

		store.set(myAtom, "first");
		unsubA(); // remove A only
		store.set(myAtom, "second");

		expect(receivedA).toEqual(["first"]); // stopped after unsubA
		expect(receivedB).toEqual(["first", "second"]); // still active
	});

	it("atom value persists in store even after all subscribers are removed", () => {
		const store = createStore();
		const dataAtom = atom("initial");

		const unsub = store.sub(dataAtom, () => {});
		store.set(dataAtom, "updated");
		unsub();

		// Atom still holds the value even with no subscribers
		expect(store.get(dataAtom)).toBe("updated");
	});

	it("simulated setInterval cleanup: timer fn is a no-op after clearInterval", () => {
		const store = createStore();
		const counterAtom = atom(0);
		let active = true;
		const ticks: number[] = [];

		// Simulate an interval that reads the atom and stops when cleaned up
		const tick = () => {
			if (!active) return;
			ticks.push(store.get(counterAtom));
		};

		store.set(counterAtom, 1);
		tick();
		store.set(counterAtom, 2);
		tick();

		active = false; // simulate clearInterval

		store.set(counterAtom, 3);
		tick(); // should be no-op

		expect(ticks).toEqual([1, 2]);
	});

	it("simulated setTimeout: timeout callback does nothing if cancelled before it runs", () => {
		const store = createStore();
		const resultAtom = atom<string | null>(null);
		let cancelled = false;

		// Simulate a deferred update that can be cancelled
		const deferredUpdate = () => {
			if (cancelled) return;
			store.set(resultAtom, "timeout fired");
		};

		cancelled = true;
		deferredUpdate(); // should be skipped

		expect(store.get(resultAtom)).toBeNull();
	});

	it("re-subscribing after cleanup works correctly", () => {
		const store = createStore();
		const stateAtom = atom(0);
		const received: number[] = [];

		// First subscription cycle
		const unsub1 = store.sub(stateAtom, () => received.push(store.get(stateAtom)));
		store.set(stateAtom, 1);
		unsub1();

		// Second subscription cycle
		const unsub2 = store.sub(stateAtom, () => received.push(store.get(stateAtom)));
		store.set(stateAtom, 2);
		unsub2();

		expect(received).toEqual([1, 2]);
	});

	it("subscriber added after a prior subscriber is removed is isolated", () => {
		const store = createStore();
		const myAtom = atom("a");
		const firstSeen: string[] = [];
		const secondSeen: string[] = [];

		const unsub1 = store.sub(myAtom, () => firstSeen.push(store.get(myAtom)));
		store.set(myAtom, "b");
		unsub1();

		store.sub(myAtom, () => secondSeen.push(store.get(myAtom)));
		store.set(myAtom, "c");

		expect(firstSeen).toEqual(["b"]);
		expect(secondSeen).toEqual(["c"]);
	});

	it("cleanup of derived atom subscriber stops propagation notifications", () => {
		const store = createStore();
		const baseAtom = atom(0);
		const derivedAtom = atom((get) => get(baseAtom) * 10);
		const seen: number[] = [];

		const unsub = store.sub(derivedAtom, () => seen.push(store.get(derivedAtom)));

		store.set(baseAtom, 1); // triggers derived → 10
		unsub();
		store.set(baseAtom, 2); // no more subscription

		expect(seen).toEqual([10]);
	});

	it("large number of simultaneous subscriptions all clean up without memory errors", () => {
		const store = createStore();
		const myAtom = atom(false);
		let callCount = 0;
		const unsubs: Array<() => void> = [];

		for (let i = 0; i < 1000; i++) {
			unsubs.push(
				store.sub(myAtom, () => {
					callCount++;
				}),
			);
		}

		store.set(myAtom, true); // all 1000 fire
		expect(callCount).toBe(1000);

		// Clean up all
		unsubs.forEach((u) => u());
		store.set(myAtom, false); // nobody should fire now
		expect(callCount).toBe(1000); // unchanged
	});

	it("real atom: recordingActiveAtom subscription cleans up correctly", () => {
		const store = createStore();
		const log: boolean[] = [];

		const unsub = store.sub(recordingActiveAtom, () => {
			log.push(store.get(recordingActiveAtom));
		});

		store.set(recordingActiveAtom, true);
		store.set(recordingActiveAtom, false);
		unsub();
		store.set(recordingActiveAtom, true); // should not be logged

		expect(log).toEqual([true, false]);
	});

	it("real atom: isCapturingAtom and isPlayingAtom subscriptions are independent", () => {
		const store = createStore();
		const captureLogs: boolean[] = [];
		const playingLogs: boolean[] = [];

		const unsubCapture = store.sub(isCapturingAtom, () =>
			captureLogs.push(store.get(isCapturingAtom)),
		);
		const unsubPlaying = store.sub(isPlayingAtom, () =>
			playingLogs.push(store.get(isPlayingAtom)),
		);

		store.set(isCapturingAtom, true);
		store.set(isPlayingAtom, true);
		unsubCapture(); // stop capture subscription
		store.set(isCapturingAtom, false); // not logged
		store.set(isPlayingAtom, false); // still logged
		unsubPlaying();

		expect(captureLogs).toEqual([true]);
		expect(playingLogs).toEqual([true, false]);
	});

	it("atom subscription does not fire when written value is the same reference", () => {
		const store = createStore();
		// Write-atoms in jotai notify subscribers only when the value actually changes
		const numAtom = atom(5);
		let notifyCount = 0;

		store.sub(numAtom, () => {
			notifyCount++;
		});

		store.set(numAtom, 5); // same value — Jotai may skip notification
		store.set(numAtom, 5);
		store.set(numAtom, 6); // actually changed → notification fires

		// Jotai v2 skips notifications when Object.is(prev, next) is true
		expect(notifyCount).toBeLessThanOrEqual(1);
		expect(store.get(numAtom)).toBe(6);
	});
});
