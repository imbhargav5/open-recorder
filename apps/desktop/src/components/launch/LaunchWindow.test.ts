import { describe, expect, it } from "vitest";
import { resolveSelectedSourceState } from "./launchWindowState";

describe("LaunchWindow selection invariants", () => {
	it.each([
		["falls back to the default source name", null, "Main Display"],
		["uses the source name when present", { name: "Display 2" }, "Display 2"],
		["uses the windowTitle fallback when name is missing", { windowTitle: "Docs" }, "Docs"],
		["uses the snake_case window_title fallback when needed", { window_title: "Chat" }, "Chat"],
	])("%s", (_label, source, expectedName) => {
		expect(resolveSelectedSourceState(source)).toEqual({
			selectedSource: expectedName,
			hasSelectedSource: true,
		});
	});
});
