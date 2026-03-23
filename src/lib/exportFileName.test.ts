import { describe, expect, it } from "vitest";

import { formatLocalExportTimestamp, getSuggestedExportFileName } from "@/lib/exportFileName";

describe("formatLocalExportTimestamp", () => {
	it("formats local time using the requested filename shape", () => {
		const date = new Date(2026, 0, 25, 20, 54, 34);

		expect(formatLocalExportTimestamp(date)).toBe("2026-01-25 at 8.54.34 PM");
	});

	it("handles midnight in 12-hour time", () => {
		const date = new Date(2026, 0, 25, 0, 5, 9);

		expect(getSuggestedExportFileName("screenshot", "png", date)).toBe(
			"screenshot 2026-01-25 at 12.05.09 AM.png",
		);
	});
});
