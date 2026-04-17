/**
 * Global type declaration for the Electron preload bridge.
 * This is exposed to the renderer via contextBridge in electron/preload.ts.
 */

interface ElectronAPI {
	invoke(channel: string, args?: unknown): Promise<unknown>;
	on(channel: string, callback: (payload: unknown) => void): () => void;
	send(channel: string, args?: unknown): void;
}

interface Window {
	electronAPI?: ElectronAPI;
}
