/**
 * Race Condition Tests for Jotai State Management
 *
 * Covers: rapid sequential writes, concurrent async atom resolution,
 * subscriber notification ordering, and re-entrant writes.
 */

import { atom } from "jotai";
import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import { microphoneEnabledAtom, recordingActiveAtom } from "@/atoms/recording";
import { audioVolumeAtom, durationAtom, zoomRegionsAtom } from "@/atoms/videoEditor";

describe("race conditions", () => {
	it("rapid sequential writes maintain the correct final value", () => {
		const store = createStore();
		const countAtom = atom(0);

		for (let i = 0; i < 1000; i++) {
			store.set(countAtom, i);
		}

		expect(store.get(countAtom)).toBe(999);
	});

	it("subscriber receives notifications in write order", () => {
		const store = createStore();
		const countAtom = atom(0);
		const received: number[] = [];

		store.sub(countAtom, () => {
			received.push(store.get(countAtom));
		});

		store.set(countAtom, 1);
		store.set(countAtom, 2);
		store.set(countAtom, 3);

		expect(received).toEqual([1, 2, 3]);
	});

	it("all subscribers are notified on rapid writes", () => {
		const store = createStore();
		const valueAtom = atom("initial");
		const notifyCount = [0, 0, 0];

		const unsubs = notifyCount.map((_, i) =>
			store.sub(valueAtom, () => {
				notifyCount[i]++;
			}),
		);

		for (let w = 0; w < 50; w++) {
			store.set(valueAtom, `value-${w}`);
		}

		unsubs.forEach((u) => u());
		expect(notifyCount).toEqual([50, 50, 50]);
	});

	it("derived atom reflects the latest dependency value after rapid changes", () => {
		const store = createStore();
		const baseAtom = atom(0);
		const derivedAtom = atom((get) => get(baseAtom) * 2);

		for (let i = 0; i < 500; i++) {
			store.set(baseAtom, i);
		}

		expect(store.get(derivedAtom)).toBe(998); // 499 * 2
	});

	it("derived atom subscriber always reads the current value, not a stale one", () => {
		const store = createStore();
		const srcAtom = atom(0);
		const doubleAtom = atom((get) => get(srcAtom) * 2);
		const seen: number[] = [];

		store.sub(doubleAtom, () => {
			seen.push(store.get(doubleAtom));
		});

		store.set(srcAtom, 1);
		store.set(srcAtom, 2);
		store.set(srcAtom, 3);

		expect(seen).toEqual([2, 4, 6]);
	});

	it("async atom resolves to its computed value", async () => {
		const store = createStore();
		const asyncAtom = atom(async () => {
			await Promise.resolve();
			return 42;
		});

		const result = await store.get(asyncAtom);
		expect(result).toBe(42);
	});

	it("multiple independent async atoms resolve correctly in any order", async () => {
		const store = createStore();

		const slowAtom = atom(async () => {
			await new Promise<void>((r) => setTimeout(r, 10));
			return "slow";
		});
		const fastAtom = atom(async () => {
			await Promise.resolve();
			return "fast";
		});

		const [slow, fast] = await Promise.all([store.get(slowAtom), store.get(fastAtom)]);

		expect(fast).toBe("fast");
		expect(slow).toBe("slow");
	});

	it("async atom with dependency reads the correct value at execution time", async () => {
		const store = createStore();
		const baseAtom = atom(1);
		const asyncDerived = atom(async (get) => {
			const val = get(baseAtom);
			await Promise.resolve();
			return val * 10;
		});

		expect(await store.get(asyncDerived)).toBe(10);

		store.set(baseAtom, 5);
		expect(await store.get(asyncDerived)).toBe(50);
	});

	it("write atom with updater handles 100 rapid increments correctly", () => {
		const store = createStore();
		const counterAtom = atom(0);
		const incrementAtom = atom(null, (get, set) => {
			set(counterAtom, get(counterAtom) + 1);
		});

		for (let i = 0; i < 100; i++) {
			store.set(incrementAtom);
		}

		expect(store.get(counterAtom)).toBe(100);
	});

	it("atom write inside a subscription callback takes effect immediately", () => {
		const store = createStore();
		const triggerAtom = atom(false);
		const sideEffectAtom = atom(0);
		let fired = false;

		store.sub(triggerAtom, () => {
			if (!fired) {
				fired = true;
				store.set(sideEffectAtom, 99);
			}
		});

		store.set(triggerAtom, true);

		expect(store.get(sideEffectAtom)).toBe(99);
	});

	it("two independent stores do not interfere under concurrent writes", () => {
		const sharedDef = atom(0);
		const storeA = createStore();
		const storeB = createStore();

		for (let i = 0; i < 100; i++) {
			storeA.set(sharedDef, i);
			storeB.set(sharedDef, i * 2);
		}

		expect(storeA.get(sharedDef)).toBe(99);
		expect(storeB.get(sharedDef)).toBe(198);
	});

	it("unsubscribed listener stops receiving notifications during rapid writes", () => {
		const store = createStore();
		const valueAtom = atom(0);
		const received: number[] = [];

		const unsub = store.sub(valueAtom, () => {
			received.push(store.get(valueAtom));
		});

		store.set(valueAtom, 1);
		store.set(valueAtom, 2);
		unsub();
		store.set(valueAtom, 3);
		store.set(valueAtom, 4);

		expect(received).toEqual([1, 2]);
		expect(store.get(valueAtom)).toBe(4); // store still updated correctly
	});

	it("three-level derived chain propagates rapid changes end-to-end", () => {
		const store = createStore();
		const aAtom = atom(0);
		const bAtom = atom((get) => get(aAtom) + 1);
		const cAtom = atom((get) => get(bAtom) * 2);

		store.set(aAtom, 10);

		expect(store.get(bAtom)).toBe(11);
		expect(store.get(cAtom)).toBe(22);
	});

	it("rapid boolean toggling settles to the final written state", () => {
		const store = createStore();
		const toggleAtom = atom(false);

		// i=0..1000, last i=1000: 1000%2===0 → write false
		for (let i = 0; i <= 1000; i++) {
			store.set(toggleAtom, i % 2 !== 0);
		}

		expect(store.get(toggleAtom)).toBe(false);
	});

	it("rapid subscribe/unsubscribe cycles do not accumulate phantom callbacks", () => {
		const store = createStore();
		const trackAtom = atom(0);
		let callCount = 0;

		for (let i = 0; i < 50; i++) {
			const unsub = store.sub(trackAtom, () => {
				callCount++;
			});
			unsub();
		}

		store.set(trackAtom, 999);
		expect(callCount).toBe(0);
	});

	it("interleaved reads and writes always return the latest written value", () => {
		const store = createStore();
		const dataAtom = atom<string>("start");
		const readValues: string[] = [];

		for (let i = 0; i < 10; i++) {
			store.set(dataAtom, `value-${i}`);
			readValues.push(store.get(dataAtom));
		}

		expect(readValues).toEqual(Array.from({ length: 10 }, (_, i) => `value-${i}`));
	});

	it("real recording atoms maintain correct final value under rapid writes", () => {
		const store = createStore();

		for (let i = 0; i < 200; i++) {
			store.set(recordingActiveAtom, i % 2 === 0);
			store.set(microphoneEnabledAtom, i % 3 === 0);
		}

		// i=199: 199%2=1 → false; 199%3≠0 → false
		expect(store.get(recordingActiveAtom)).toBe(false);
		expect(store.get(microphoneEnabledAtom)).toBe(false);
	});

	it("video editor atoms survive a rapid write storm", () => {
		const store = createStore();

		for (let i = 0; i < 500; i++) {
			store.set(audioVolumeAtom, i / 500);
			store.set(durationAtom, i * 1000);
		}

		expect(store.get(audioVolumeAtom)).toBeCloseTo(499 / 500);
		expect(store.get(durationAtom)).toBe(499000);
	});

	it("two async atoms with controlled out-of-order promises both resolve correctly", async () => {
		const store = createStore();
		let resolveA!: (v: string) => void;
		let resolveB!: (v: string) => void;

		const promiseA = new Promise<string>((r) => {
			resolveA = r;
		});
		const promiseB = new Promise<string>((r) => {
			resolveB = r;
		});

		const atomA = atom(() => promiseA);
		const atomB = atom(() => promiseB);

		const pendingA = store.get(atomA);
		const pendingB = store.get(atomB);

		// Resolve B before A (deliberate out-of-order)
		resolveB("result-B");
		resolveA("result-A");

		expect(await pendingA).toBe("result-A");
		expect(await pendingB).toBe("result-B");
	});

	it("notification count exactly matches write count", () => {
		const store = createStore();
		const atom1 = atom(0);
		let notificationCount = 0;

		store.sub(atom1, () => {
			notificationCount++;
		});

		const writesCount = 47;
		for (let i = 0; i < writesCount; i++) {
			store.set(atom1, i + 1);
		}

		expect(notificationCount).toBe(writesCount);
	});

	it("zoom regions atom handles rapid array replacements without corruption", () => {
		const store = createStore();
		const iterations = 200;

		for (let i = 0; i < iterations; i++) {
			store.set(
				zoomRegionsAtom,
				Array.from({ length: i % 5 }, (_, j) => ({
					id: `z-${j}`,
					startTime: j * 100,
					endTime: j * 100 + 50,
					x: 0,
					y: 0,
					width: 1,
					height: 1,
					scale: 1.5,
				})),
			);
		}

		// Last iteration: 199 % 5 = 4 regions
		expect(store.get(zoomRegionsAtom)).toHaveLength(4);
	});

	it("concurrent async atoms sharing a dependency do not corrupt each other", async () => {
		const store = createStore();
		const sharedAtom = atom(10);

		const asyncA = atom(async (get) => get(sharedAtom) + 1);
		const asyncB = atom(async (get) => get(sharedAtom) * 2);

		const [a, b] = await Promise.all([store.get(asyncA), store.get(asyncB)]);

		expect(a).toBe(11);
		expect(b).toBe(20);
	});
});
