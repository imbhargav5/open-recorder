import { describe, expect, it } from "vitest";
import { getSourceGridColumnClass } from "./sourceGridLayout";

describe("getSourceGridColumnClass", () => {
	it("uses a single column for a single screen", () => {
		expect(getSourceGridColumnClass("screen", 1)).toBe("grid-cols-1");
	});

	it("uses two columns for two or four screens", () => {
		expect(getSourceGridColumnClass("screen", 2)).toBe("grid-cols-2");
		expect(getSourceGridColumnClass("screen", 4)).toBe("grid-cols-2");
	});

	it("uses three columns for three or more than four screens", () => {
		expect(getSourceGridColumnClass("screen", 3)).toBe("grid-cols-3");
		expect(getSourceGridColumnClass("screen", 5)).toBe("grid-cols-3");
		expect(getSourceGridColumnClass("screen", 6)).toBe("grid-cols-3");
	});

	it("keeps the window grid at two columns", () => {
		expect(getSourceGridColumnClass("window", 1)).toBe("grid-cols-2");
		expect(getSourceGridColumnClass("window", 8)).toBe("grid-cols-2");
	});
});
