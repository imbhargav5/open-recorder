import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/electronBridge", () => ({
	invoke: vi.fn(),
	listen: vi.fn(),
}));

vi.mock("@/lib/mediaPlaybackUrl", () => ({
	resolveMediaPlaybackUrl: vi.fn((path: string) => path),
}));

const { invoke, listen } = vi.mocked(await import("@/lib/electronBridge"));
const backend = await import("@/lib/backend");

describe("backend multi-window IPC wrappers", () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it("reports unsaved editor state without renderer-supplied window metadata", async () => {
		invoke.mockResolvedValue(undefined);

		await backend.setHasUnsavedChanges(true);

		expect(invoke).toHaveBeenCalledWith("set_has_unsaved_changes", { hasChanges: true });
		expect(invoke).toHaveBeenCalledTimes(1);

		const [, args] = invoke.mock.calls[0] ?? [];
		expect(args).toEqual({ hasChanges: true });
		expect(args).not.toHaveProperty("windowLabel");
		expect(args).not.toHaveProperty("windowId");
	});

	it("binds menu and tray listeners to distinct targeted IPC channels", async () => {
		const listeners = new Map<string, (payload: unknown) => void>();

		listen.mockImplementation((channel: string, callback: (payload: unknown) => void) => {
			listeners.set(channel, callback);
			return () => {
				listeners.delete(channel);
			};
		});

		const onLoadProject = vi.fn();
		const onSaveProject = vi.fn();
		const onSaveProjectAs = vi.fn();
		const onNewRecording = vi.fn();

		const unlistenLoad = await backend.onMenuLoadProject(onLoadProject);
		const unlistenSave = await backend.onMenuSaveProject(onSaveProject);
		const unlistenSaveAs = await backend.onMenuSaveProjectAs(onSaveProjectAs);
		const unlistenNewRecording = await backend.onNewRecordingFromTray(onNewRecording);

		expect(listen).toHaveBeenNthCalledWith(1, "menu-load-project", onLoadProject);
		expect(listen).toHaveBeenNthCalledWith(2, "menu-save-project", onSaveProject);
		expect(listen).toHaveBeenNthCalledWith(3, "menu-save-project-as", onSaveProjectAs);
		expect(listen).toHaveBeenNthCalledWith(4, "new-recording-from-tray", onNewRecording);

		listeners.get("menu-load-project")?.(undefined);
		expect(onLoadProject).toHaveBeenCalledTimes(1);
		expect(onSaveProject).not.toHaveBeenCalled();
		expect(onSaveProjectAs).not.toHaveBeenCalled();
		expect(onNewRecording).not.toHaveBeenCalled();

		listeners.get("menu-save-project")?.(undefined);
		expect(onSaveProject).toHaveBeenCalledTimes(1);
		expect(onLoadProject).toHaveBeenCalledTimes(1);
		expect(onSaveProjectAs).not.toHaveBeenCalled();
		expect(onNewRecording).not.toHaveBeenCalled();

		listeners.get("menu-save-project-as")?.(undefined);
		expect(onSaveProjectAs).toHaveBeenCalledTimes(1);
		expect(onNewRecording).not.toHaveBeenCalled();

		listeners.get("new-recording-from-tray")?.(undefined);
		expect(onNewRecording).toHaveBeenCalledTimes(1);

		unlistenSave();
		expect(listeners.has("menu-save-project")).toBe(false);

		unlistenLoad();
		unlistenSaveAs();
		unlistenNewRecording();
		expect(listeners.size).toBe(0);
	});
});
