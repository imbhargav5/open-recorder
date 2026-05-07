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
			"keeps area names unchanged",
			{
				id: "area:1:10:20:1280:720",
				name: "Area 1280x720",
				thumbnail: null,
				display_id: "1",
				appIcon: null,
				originalName: "Area 1280x720",
				sourceType: "area",
				captureSourceId: "screen:1:0",
				areaSelection: {
					x: 10,
					y: 20,
					width: 1280,
					height: 720,
					displayId: 1,
					displayBounds: { x: 0, y: 0, width: 1920, height: 1080 },
				},
			} as ProcessedDesktopSource,
			{
				sourceType: "area",
				displayName: "Area 1280x720",
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
				id: "area:1:10:20:1280:720",
				name: "Area 1280x720",
				thumbnail: null,
				display_id: "1",
				appIcon: null,
				originalName: "Area 1280x720",
				sourceType: "area",
				captureSourceId: "screen:1:0",
				areaSelection: {
					x: 10,
					y: 20,
					width: 1280,
					height: 720,
					displayId: 1,
					displayBounds: { x: 0, y: 0, width: 1920, height: 1080 },
				},
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
				id: "area:1:10:20:1280:720",
				name: "Area 1280x720",
				thumbnail: null,
				display_id: "1",
				appIcon: null,
				originalName: "Area 1280x720",
				sourceType: "area",
				appName: undefined,
				windowTitle: undefined,
				windowId: undefined,
				captureSourceId: "screen:1:0",
				areaSelection: {
					x: 10,
					y: 20,
					width: 1280,
					height: 720,
					displayId: 1,
					displayBounds: { x: 0, y: 0, width: 1920, height: 1080 },
				},
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
