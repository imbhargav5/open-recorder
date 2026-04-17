/**
 * Electron preload script.
 *
 * Exposes a safe bridge (`window.electronAPI`) to the renderer process via
 * contextBridge. All IPC communication goes through this bridge — the renderer
 * never has direct access to Node.js or Electron internals.
 */

import { contextBridge, ipcRenderer } from "electron";

export type UnlistenFn = () => void;

export interface ElectronAPI {
	/** Invoke an IPC command in the main process and await the result. */
	invoke(channel: string, args?: unknown): Promise<unknown>;
	/** Subscribe to events sent from the main process. Returns an unlisten function. */
	on(channel: string, callback: (payload: unknown) => void): UnlistenFn;
	/** Send a one-way message to the main process (fire-and-forget). */
	send(channel: string, args?: unknown): void;
}

const api: ElectronAPI = {
	invoke(channel: string, args?: unknown): Promise<unknown> {
		return ipcRenderer.invoke(channel, args);
	},

	on(channel: string, callback: (payload: unknown) => void): UnlistenFn {
		const listener = (_event: Electron.IpcRendererEvent, payload: unknown) => {
			callback(payload);
		};
		ipcRenderer.on(channel, listener);
		return () => {
			ipcRenderer.removeListener(channel, listener);
		};
	},

	send(channel: string, args?: unknown): void {
		ipcRenderer.send(channel, args);
	},
};

contextBridge.exposeInMainWorld("electronAPI", api);
