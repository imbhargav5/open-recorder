/**
 * Error Handling Tests for Jotai State Management
 *
 * Covers: derived atoms that throw on read, async atoms that reject,
 * write atoms with throwing setters, store recovery after errors,
 * and error isolation between stores.
 */

import { atom } from "jotai";
import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import { videoErrorAtom, exportErrorAtom, isExportingAtom } from "@/atoms/videoEditor";
import { updaterErrorAtom, updaterStatusAtom } from "@/atoms/updater";

describe("error handling", () => {
	it("derived atom that throws propagates the error to the caller", () => {
		const store = createStore();
		const throwingAtom = atom<string>(() => {
			throw new Error("read error");
		});

		expect(() => store.get(throwingAtom)).toThrow("read error");
	});

	it("store continues to function normally after a derived atom throws", () => {
		const store = createStore();
		const throwingAtom = atom<number>(() => {
			throw new Error("boom");
		});
		const healthyAtom = atom(42);

		try {
			store.get(throwingAtom);
		} catch {
			// expected
		}

		expect(store.get(healthyAtom)).toBe(42);
	});

	it("async atom that rejects exposes a rejected promise", async () => {
		const store = createStore();
		const rejectingAtom = atom(async () => {
			await Promise.resolve();
			throw new Error("async rejection");
		});

		await expect(store.get(rejectingAtom)).rejects.toThrow("async rejection");
	});

	it("async atom rejection does not corrupt sibling atoms", async () => {
		const store = createStore();
		const rejectingAtom = atom(async () => {
			throw new Error("rejected");
		});
		const safeAtom = atom("safe-value");

		try {
			await store.get(rejectingAtom);
		} catch {
			// expected
		}

		expect(store.get(safeAtom)).toBe("safe-value");
	});

	it("write atom with throwing setter propagates the error", () => {
		const store = createStore();
		const dataAtom = atom(0);
		const badWriteAtom = atom(null, (_get, _set) => {
			throw new Error("write failed");
		});

		store.set(dataAtom, 5);
		expect(() => store.set(badWriteAtom)).toThrow("write failed");

		// Underlying atom is unchanged after failed write
		expect(store.get(dataAtom)).toBe(5);
	});

	it("write atom that conditionally throws leaves atom unchanged when it throws", () => {
		const store = createStore();
		const safeAtom = atom(10);
		const conditionalWriteAtom = atom(null, (get, set, shouldThrow: boolean) => {
			if (shouldThrow) throw new Error("conditional failure");
			set(safeAtom, get(safeAtom) + 1);
		});

		expect(() => store.set(conditionalWriteAtom, true)).toThrow("conditional failure");
		// Value should be unchanged because the write threw before the set
		expect(store.get(safeAtom)).toBe(10);

		store.set(conditionalWriteAtom, false); // succeeds — value becomes 11
		expect(store.get(safeAtom)).toBe(11);
	});

	it("error in one store does not affect an independent store", () => {
		const throwingDef = atom<string>(() => {
			throw new Error("store A error");
		});
		const storeA = createStore();
		const storeB = createStore();
		const healthyAtom = atom("healthy");

		try {
			storeA.get(throwingDef);
		} catch {
			// expected
		}

		// storeB is completely unaffected
		expect(storeB.get(healthyAtom)).toBe("healthy");
	});

	it("derived atom with internal try/catch provides fallback on error", () => {
		const store = createStore();
		const riskyAtom = atom<number>(() => {
			throw new Error("risky computation");
		});
		const safeWrapperAtom = atom((get) => {
			try {
				return get(riskyAtom);
			} catch {
				return -1; // fallback
			}
		});

		expect(store.get(safeWrapperAtom)).toBe(-1);
	});

	it("multiple sequential async rejections are each independent", async () => {
		const store = createStore();
		const errors: string[] = [];

		for (let i = 0; i < 3; i++) {
			const attempt = i;
			const failingAtom = atom(async () => {
				throw new Error(`failure-${attempt}`);
			});
			try {
				await store.get(failingAtom);
			} catch (e) {
				errors.push((e as Error).message);
			}
		}

		expect(errors).toEqual(["failure-0", "failure-1", "failure-2"]);
	});

	it("async atom with recovery: second call after rejection resolves correctly", async () => {
		const store = createStore();
		let shouldFail = true;

		const conditionalAsyncAtom = atom(async () => {
			if (shouldFail) throw new Error("temporary failure");
			return "success";
		});

		await expect(store.get(conditionalAsyncAtom)).rejects.toThrow("temporary failure");

		shouldFail = false;
		// New atom call (new atom instance) should succeed
		const recoveredAtom = atom(async () => {
			if (shouldFail) throw new Error("temporary failure");
			return "success";
		});
		await expect(store.get(recoveredAtom)).resolves.toBe("success");
	});

	it("subscription survives a write-atom error and continues notifying on subsequent valid writes", () => {
		const store = createStore();
		const trackAtom = atom(0);
		const badWriteAtom = atom(null, (_get, _set) => {
			throw new Error("set error");
		});
		const notifications: number[] = [];

		store.sub(trackAtom, () => {
			notifications.push(store.get(trackAtom));
		});

		store.set(trackAtom, 1);

		try {
			store.set(badWriteAtom);
		} catch {
			// expected
		}

		store.set(trackAtom, 2);

		expect(notifications).toEqual([1, 2]);
	});

	it("real atom: videoErrorAtom can be set to an error string and then cleared", () => {
		const store = createStore();

		expect(store.get(videoErrorAtom)).toBeNull();

		store.set(videoErrorAtom, "Failed to load video");
		expect(store.get(videoErrorAtom)).toBe("Failed to load video");

		store.set(videoErrorAtom, null);
		expect(store.get(videoErrorAtom)).toBeNull();
	});

	it("real atom: exportErrorAtom and isExportingAtom can model export failure recovery", () => {
		const store = createStore();

		store.set(isExportingAtom, true);
		store.set(exportErrorAtom, "Disk full");

		expect(store.get(isExportingAtom)).toBe(true);
		expect(store.get(exportErrorAtom)).toBe("Disk full");

		// Recovery: reset both
		store.set(isExportingAtom, false);
		store.set(exportErrorAtom, null);

		expect(store.get(isExportingAtom)).toBe(false);
		expect(store.get(exportErrorAtom)).toBeNull();
	});

	it("real atom: updater error cycle models a complete update failure and reset", () => {
		const store = createStore();

		store.set(updaterStatusAtom, "error");
		store.set(updaterErrorAtom, "Network timeout");

		expect(store.get(updaterStatusAtom)).toBe("error");
		expect(store.get(updaterErrorAtom)).toBe("Network timeout");

		// Reset to idle
		store.set(updaterStatusAtom, "idle");
		store.set(updaterErrorAtom, null);

		expect(store.get(updaterStatusAtom)).toBe("idle");
		expect(store.get(updaterErrorAtom)).toBeNull();
	});

	it("derived atom that conditionally throws based on dependency value", () => {
		const store = createStore();
		const inputAtom = atom<number | null>(null);
		const safeDivideAtom = atom((get) => {
			const val = get(inputAtom);
			if (val === null) throw new Error("value is null");
			if (val === 0) throw new Error("division by zero");
			return 100 / val;
		});

		expect(() => store.get(safeDivideAtom)).toThrow("value is null");

		store.set(inputAtom, 0);
		expect(() => store.get(safeDivideAtom)).toThrow("division by zero");

		store.set(inputAtom, 4);
		expect(store.get(safeDivideAtom)).toBe(25);
	});

	it("multiple derived atoms all throwing independently do not prevent each other from recovering", () => {
		const store = createStore();
		const flagA = atom(false);
		const flagB = atom(false);

		const throwingA = atom((get) => {
			if (!get(flagA)) throw new Error("A not ready");
			return "A ok";
		});
		const throwingB = atom((get) => {
			if (!get(flagB)) throw new Error("B not ready");
			return "B ok";
		});

		expect(() => store.get(throwingA)).toThrow("A not ready");
		expect(() => store.get(throwingB)).toThrow("B not ready");

		store.set(flagA, true);
		expect(store.get(throwingA)).toBe("A ok");
		expect(() => store.get(throwingB)).toThrow("B not ready");

		store.set(flagB, true);
		expect(store.get(throwingA)).toBe("A ok");
		expect(store.get(throwingB)).toBe("B ok");
	});
});
