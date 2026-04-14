import { describe, expect, it } from "vitest";
import {
	type DesktopSource,
	mapSources,
	mergeSources,
	parseSourceMetadata,
} from "./sourceSelectorState";

describe("sourceSelector helpers", () => {
	it.each([
		[
			"keeps screen names unchanged",
			{
				id: "screen:1",
				name: "Display 1",
				thumbnail: null,
				display_id: "1",
				appIcon: null,
				originalName: "Display 1",
				sourceType: "screen",
			} as ProcessedDesktopSource,
			{
				sourceType: "screen",
				displayName: "Display 1",
			},
		],
		[
			"uses explicit window metadata when present",
			{
				id: "window:1",
				name: "Fallback title",
				thumbnail: null,
				display_id: "1",
				appIcon: null,
				originalName: "Fallback title",
				sourceType: "window",
				appName: "Preview",
				windowTitle: "Preview - Settings",
			} as ProcessedDesktopSource,
			{
				sourceType: "window",
				appName: "Preview",
				windowTitle: "Preview - Settings",
				displayName: "Preview - Settings",
			},
		],
		[
			"parses window names when metadata is missing",
			{
				id: "window:2",
				name: "Safari — Docs",
				thumbnail: null,
				display_id: "2",
				appIcon: null,
				originalName: "Safari — Docs",
				sourceType: "window",
			} as ProcessedDesktopSource,
			{
				sourceType: "window",
				appName: "Safari",
				windowTitle: "Docs",
				displayName: "Docs",
			},
		],
	])("%s", (_label, source, expected) => {
		expect(parseSourceMetadata(source)).toMatchObject(expected);
	});

	it("maps raw sources into the desktop source shape", () => {
		const sources = mapSources([
			{
				id: "screen:1",
				name: "Display 1",
				thumbnail: "thumb://screen",
				display_id: "1",
				appIcon: null,
				originalName: "Display 1",
				sourceType: "screen",
			},
			{
				id: "window:1",
				name: "Preview — Settings",
				thumbnail: null,
				display_id: "2",
				appIcon: "icon://app",
				originalName: "Preview — Settings",
				sourceType: "window",
			},
		]);

		expect(sources).toEqual<DesktopSource[]>([
			{
				id: "screen:1",
				name: "Display 1",
				thumbnail: "thumb://screen",
				display_id: "1",
				appIcon: null,
				originalName: "Display 1",
				sourceType: "screen",
				appName: undefined,
				windowTitle: undefined,
				windowId: undefined,
			},
			{
				id: "window:1",
				name: "Settings",
				thumbnail: null,
				display_id: "2",
				appIcon: "icon://app",
				originalName: "Preview — Settings",
				sourceType: "window",
				appName: "Preview",
				windowTitle: "Settings",
				windowId: undefined,
			},
		]);
	});

	it("merges refreshed previews without dropping existing thumbnail or icon values", () => {
		const existing: DesktopSource[] = [
			{
				id: "window:1",
				name: "Settings",
				thumbnail: "thumb://existing",
				display_id: "2",
				appIcon: "icon://existing",
				originalName: "Preview — Settings",
				sourceType: "window",
				appName: "Preview",
				windowTitle: "Settings",
			},
		];
		const incoming: DesktopSource[] = [
			{
				id: "window:1",
				name: "Settings",
				thumbnail: null,
				display_id: "2",
				appIcon: null,
				originalName: "Preview — Settings",
				sourceType: "window",
				appName: "Preview",
				windowTitle: "Settings",
				windowId: 44,
			},
			{
				id: "screen:2",
				name: "Display 2",
				thumbnail: null,
				display_id: "3",
				appIcon: null,
				originalName: "Display 2",
				sourceType: "screen",
			},
		];

		expect(mergeSources(existing, incoming)).toEqual([
			{
				id: "window:1",
				name: "Settings",
				thumbnail: "thumb://existing",
				display_id: "2",
				appIcon: "icon://existing",
				originalName: "Preview — Settings",
				sourceType: "window",
				appName: "Preview",
				windowTitle: "Settings",
				windowId: 44,
			},
			{
				id: "screen:2",
				name: "Display 2",
				thumbnail: null,
				display_id: "3",
				appIcon: null,
				originalName: "Display 2",
				sourceType: "screen",
			},
		]);
	});
});
