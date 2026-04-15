/**
 * Boundary Value Tests for Jotai State Management
 *
 * Covers: extremely large/small numbers, NaN/Infinity, empty and huge
 * strings, null/undefined transitions, empty/large arrays, deeply
 * nested objects, rapid value toggling, and special JS edge cases.
 */

import { atom } from "jotai";
import { createStore } from "jotai/vanilla";
import { describe, expect, it } from "vitest";
import {
	audioVolumeAtom,
	borderRadiusAtom,
	durationAtom,
	shadowIntensityAtom,
	trimRegionsAtom,
	zoomRegionsAtom,
} from "@/atoms/videoEditor";
import { recordingElapsedAtom } from "@/atoms/launch";
import { imagePaddingAtom } from "@/atoms/imageEditor";

describe("boundary values", () => {
	it("stores Number.MAX_SAFE_INTEGER without precision loss", () => {
		const store = createStore();
		const bigAtom = atom(0);

		store.set(bigAtom, Number.MAX_SAFE_INTEGER);

		expect(store.get(bigAtom)).toBe(Number.MAX_SAFE_INTEGER);
	});

	it("stores Number.MIN_SAFE_INTEGER without precision loss", () => {
		const store = createStore();
		const negAtom = atom(0);

		store.set(negAtom, Number.MIN_SAFE_INTEGER);

		expect(store.get(negAtom)).toBe(Number.MIN_SAFE_INTEGER);
	});

	it("stores NaN and retrieves it correctly", () => {
		const store = createStore();
		const nanAtom = atom<number>(0);

		store.set(nanAtom, Number.NaN);

		expect(Number.isNaN(store.get(nanAtom))).toBe(true);
	});

	it("stores Infinity correctly", () => {
		const store = createStore();
		const infAtom = atom(0);

		store.set(infAtom, Number.POSITIVE_INFINITY);

		expect(store.get(infAtom)).toBe(Number.POSITIVE_INFINITY);
	});

	it("stores negative Infinity correctly", () => {
		const store = createStore();
		const negInfAtom = atom(0);

		store.set(negInfAtom, Number.NEGATIVE_INFINITY);

		expect(store.get(negInfAtom)).toBe(Number.NEGATIVE_INFINITY);
	});

	it("stores negative zero and distinguishes it from positive zero via Object.is", () => {
		const store = createStore();
		const zeroAtom = atom(0);

		store.set(zeroAtom, -0);

		expect(Object.is(store.get(zeroAtom), -0)).toBe(true);
		expect(Object.is(store.get(zeroAtom), 0)).toBe(false);
	});

	it("stores an empty string without coercion", () => {
		const store = createStore();
		const strAtom = atom("non-empty");

		store.set(strAtom, "");

		expect(store.get(strAtom)).toBe("");
	});

	it("stores a 100 000-character string without truncation", () => {
		const store = createStore();
		const longStrAtom = atom("");
		const longString = "a".repeat(100_000);

		store.set(longStrAtom, longString);

		const stored = store.get(longStrAtom);
		expect(stored.length).toBe(100_000);
		expect(stored[0]).toBe("a");
		expect(stored[99_999]).toBe("a");
	});

	it("stores a string containing only whitespace", () => {
		const store = createStore();
		const wsAtom = atom("default");

		store.set(wsAtom, "   \t\n   ");

		expect(store.get(wsAtom)).toBe("   \t\n   ");
	});

	it("stores emoji and multi-byte unicode characters correctly", () => {
		const store = createStore();
		const emojiAtom = atom("");

		const emoji = "🎬🎤🎥📽️🎞️";
		store.set(emojiAtom, emoji);

		expect(store.get(emojiAtom)).toBe(emoji);
	});

	it("transitions from null to a value and back to null", () => {
		const store = createStore();
		const nullableAtom = atom<string | null>(null);

		expect(store.get(nullableAtom)).toBeNull();

		store.set(nullableAtom, "some value");
		expect(store.get(nullableAtom)).toBe("some value");

		store.set(nullableAtom, null);
		expect(store.get(nullableAtom)).toBeNull();
	});

	it("transitions from undefined to a defined value and back to undefined", () => {
		const store = createStore();
		const undefinedAtom = atom<string | undefined>(undefined);

		expect(store.get(undefinedAtom)).toBeUndefined();

		store.set(undefinedAtom, "defined");
		expect(store.get(undefinedAtom)).toBe("defined");

		store.set(undefinedAtom, undefined);
		expect(store.get(undefinedAtom)).toBeUndefined();
	});

	it("stores an empty array without modification", () => {
		const store = createStore();
		const arrAtom = atom<number[]>([1, 2, 3]);

		store.set(arrAtom, []);

		expect(store.get(arrAtom)).toEqual([]);
	});

	it("stores a 10 000-element array correctly", () => {
		const store = createStore();
		const bigArrAtom = atom<number[]>([]);
		const bigArray = Array.from({ length: 10_000 }, (_, i) => i);

		store.set(bigArrAtom, bigArray);

		const stored = store.get(bigArrAtom);
		expect(stored.length).toBe(10_000);
		expect(stored[0]).toBe(0);
		expect(stored[9_999]).toBe(9_999);
	});

	it("stores an empty object without adding extra keys", () => {
		const store = createStore();
		const objAtom = atom<Record<string, unknown>>({ initial: true });

		store.set(objAtom, {});

		expect(store.get(objAtom)).toEqual({});
	});

	it("stores a deeply-nested object (10 levels) correctly", () => {
		const store = createStore();
		type Nested = { child?: Nested; value: number };
		const deepAtom = atom<Nested>({ value: 0 });

		let deep: Nested = { value: 10 };
		for (let i = 0; i < 9; i++) {
			deep = { child: deep, value: i };
		}

		store.set(deepAtom, deep);
		let current: Nested | undefined = store.get(deepAtom);
		let depth = 0;
		while (current?.child) {
			current = current.child;
			depth++;
		}

		expect(depth).toBe(9);
		expect(current?.value).toBe(10);
	});

	it("rapid null/value toggling settles to the final state", () => {
		const store = createStore();
		const nullableAtom = atom<string | null>(null);

		for (let i = 0; i < 500; i++) {
			store.set(nullableAtom, i % 2 === 0 ? null : "active");
		}

		// Last i=499: 499%2=1 → "active"
		expect(store.get(nullableAtom)).toBe("active");
	});

	it("real atom: durationAtom handles a zero-length video (0ms)", () => {
		const store = createStore();

		store.set(durationAtom, 0);

		expect(store.get(durationAtom)).toBe(0);
	});

	it("real atom: durationAtom handles an extremely long video (24-hour duration in ms)", () => {
		const store = createStore();
		const twentyFourHoursMs = 24 * 60 * 60 * 1000;

		store.set(durationAtom, twentyFourHoursMs);

		expect(store.get(durationAtom)).toBe(twentyFourHoursMs);
	});

	it("real atom: audioVolumeAtom handles boundary values 0 and 1 cleanly", () => {
		const store = createStore();

		store.set(audioVolumeAtom, 0);
		expect(store.get(audioVolumeAtom)).toBe(0);

		store.set(audioVolumeAtom, 1);
		expect(store.get(audioVolumeAtom)).toBe(1);
	});

	it("real atom: borderRadiusAtom handles 0 (no rounding) and 9999 (extreme)", () => {
		const store = createStore();

		store.set(borderRadiusAtom, 0);
		expect(store.get(borderRadiusAtom)).toBe(0);

		store.set(borderRadiusAtom, 9999);
		expect(store.get(borderRadiusAtom)).toBe(9999);
	});

	it("real atom: shadowIntensityAtom handles the full 0.0–1.0 boundary", () => {
		const store = createStore();

		store.set(shadowIntensityAtom, 0.0);
		expect(store.get(shadowIntensityAtom)).toBe(0.0);

		store.set(shadowIntensityAtom, 1.0);
		expect(store.get(shadowIntensityAtom)).toBe(1.0);
	});

	it("real atom: zoomRegionsAtom handles an empty array and then a large array", () => {
		const store = createStore();

		store.set(zoomRegionsAtom, []);
		expect(store.get(zoomRegionsAtom)).toHaveLength(0);

		const manyRegions = Array.from({ length: 500 }, (_, i) => ({
			id: `z-${i}`,
			startTime: i * 10,
			endTime: i * 10 + 5,
			x: 0,
			y: 0,
			width: 1,
			height: 1,
			scale: 2,
		}));
		store.set(zoomRegionsAtom, manyRegions);
		expect(store.get(zoomRegionsAtom)).toHaveLength(500);
	});

	it("real atom: trimRegionsAtom is empty by default and handles boundary region count", () => {
		const store = createStore();

		expect(store.get(trimRegionsAtom)).toHaveLength(0);

		const oneRegion = [{ id: "t-0", startTime: 0, endTime: 1000 }];
		store.set(trimRegionsAtom, oneRegion);
		expect(store.get(trimRegionsAtom)).toHaveLength(1);
	});

	it("real atom: recordingElapsedAtom handles a very large elapsed time", () => {
		const store = createStore();
		const tenHoursSeconds = 10 * 60 * 60;

		store.set(recordingElapsedAtom, tenHoursSeconds);

		expect(store.get(recordingElapsedAtom)).toBe(tenHoursSeconds);
	});

	it("real atom: imagePaddingAtom at minimum 0 and very large 9999", () => {
		const store = createStore();

		store.set(imagePaddingAtom, 0);
		expect(store.get(imagePaddingAtom)).toBe(0);

		store.set(imagePaddingAtom, 9999);
		expect(store.get(imagePaddingAtom)).toBe(9999);
	});
});
