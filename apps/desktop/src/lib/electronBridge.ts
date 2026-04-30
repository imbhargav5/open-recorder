/**
 * Electron IPC bridge for the renderer process.
 *
 * Wraps `window.electronAPI` (exposed by the preload script via contextBridge)
 * so the rest of the frontend code doesn't reference `window` directly.
 * This also makes the IPC easy to mock in unit tests.
 */

export type UnlistenFn = () => void;

interface ElectronAPIShape {
	invoke(channel: string, args?: unknown): Promise<unknown>;
	on(channel: string, callback: (payload: unknown) => void): UnlistenFn;
	send(channel: string, args?: unknown): void;
}

function getAPI(): ElectronAPIShape {
	const w = window as Window & { electronAPI?: ElectronAPIShape };
	if (!w.electronAPI) {
		throw new Error(
			"[electronBridge] window.electronAPI is not defined. " +
				"Make sure the Electron preload script is loaded.",
		);
	}
	return w.electronAPI;
}

export function invoke<T>(channel: string, args?: unknown): Promise<T> {
	return getAPI().invoke(channel, args) as Promise<T>;
}

export function listen<T>(
	channel: string,
	callback: (payload: T) => void,
): UnlistenFn {
	return getAPI().on(channel, (payload) => callback(payload as T));
}

export function send(channel: string, args?: unknown): void {
	getAPI().send(channel, args);
}
