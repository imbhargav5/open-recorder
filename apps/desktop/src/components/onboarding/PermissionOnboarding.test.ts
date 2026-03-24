// @vitest-environment jsdom

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { isOnboardingComplete, resetOnboarding } from "./PermissionOnboarding";

const STORAGE_KEY = "open-recorder-onboarding-v1";

describe("onboarding utilities", () => {
	beforeEach(() => {
		localStorage.clear();
	});

	afterEach(() => {
		localStorage.clear();
	});

	// ==================== isOnboardingComplete ====================

	describe("isOnboardingComplete", () => {
		it("returns false when no value is stored", () => {
			expect(isOnboardingComplete()).toBe(false);
		});

		it("returns false when the stored value is not 'true'", () => {
			localStorage.setItem(STORAGE_KEY, "false");
			expect(isOnboardingComplete()).toBe(false);
		});

		it("returns true when the stored value is 'true'", () => {
			localStorage.setItem(STORAGE_KEY, "true");
			expect(isOnboardingComplete()).toBe(true);
		});

		it("returns false for any other stored value", () => {
			localStorage.setItem(STORAGE_KEY, "yes");
			expect(isOnboardingComplete()).toBe(false);

			localStorage.setItem(STORAGE_KEY, "1");
			expect(isOnboardingComplete()).toBe(false);

			localStorage.setItem(STORAGE_KEY, "");
			expect(isOnboardingComplete()).toBe(false);
		});
	});

	// ==================== resetOnboarding ====================

	describe("resetOnboarding", () => {
		it("removes the onboarding flag so isOnboardingComplete returns false", () => {
			localStorage.setItem(STORAGE_KEY, "true");
			expect(isOnboardingComplete()).toBe(true);

			resetOnboarding();
			expect(isOnboardingComplete()).toBe(false);
		});

		it("is a no-op when no value is stored", () => {
			expect(() => resetOnboarding()).not.toThrow();
			expect(isOnboardingComplete()).toBe(false);
		});
	});

	// ==================== Roundtrip ====================

	describe("onboarding lifecycle", () => {
		it("follows the expected lifecycle: not complete → complete → reset → not complete", () => {
			// Initial state
			expect(isOnboardingComplete()).toBe(false);

			// User completes onboarding
			localStorage.setItem(STORAGE_KEY, "true");
			expect(isOnboardingComplete()).toBe(true);

			// Developer resets for testing
			resetOnboarding();
			expect(isOnboardingComplete()).toBe(false);
		});
	});
});
