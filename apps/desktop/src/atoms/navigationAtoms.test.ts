// @vitest-environment jsdom

import { afterEach, describe, expect, it, vi } from "vitest";
import { getInitialLaunchView } from "./launch";
import { getInitialTab } from "./sourceSelector";

afterEach(() => {
	window.localStorage.clear();
	window.history.replaceState({}, "", "/");
});

describe("navigation atom initializers", () => {
	it("starts in onboarding until the completion flag is stored", () => {
		expect(getInitialLaunchView()).toBe("onboarding");
		window.localStorage.setItem("open-recorder-onboarding-v1", "true");
		expect(getInitialLaunchView()).toBe("choice");
	});

	it("falls back to choice when storage access fails", () => {
		const spy = vi.spyOn(window, "localStorage", "get").mockImplementation(() => {
			throw new Error("storage unavailable");
		});

		expect(getInitialLaunchView()).toBe("choice");
		spy.mockRestore();
	});

	it("defaults the source selector to screens", () => {
		expect(getInitialTab()).toBe("screens");
	});

	it("respects the windows query parameter", () => {
		window.history.replaceState({}, "", "/?tab=windows");
		expect(getInitialTab()).toBe("windows");
	});
});
