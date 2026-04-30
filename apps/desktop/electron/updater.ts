import { app } from "electron";
import { autoUpdater } from "electron-updater";

export type UpdaterStatus =
	| "idle"
	| "checking"
	| "up-to-date"
	| "available"
	| "downloading"
	| "ready"
	| "error";

export interface UpdaterState {
	supported: boolean;
	dialogOpen: boolean;
	status: UpdaterStatus;
	currentVersion: string;
	version: string | null;
	releaseNotes: string | null;
	downloadProgress: number;
	error: string | null;
}

type UpdateInfoLike = {
	version?: string | null;
	releaseNotes?: string | Array<{ version?: string | null; note?: string | null }> | null;
};

type UpdaterEventName = "updater-state-changed" | "updater-download-progress";

export type UpdaterCheckOptions = {
	showDialog?: boolean;
};

type EmitFn = (channel: UpdaterEventName, payload: unknown) => void;

function normalizeErrorMessage(error: unknown, fallback: string): string {
	if (error instanceof Error && error.message.trim()) {
		return error.message;
	}

	if (typeof error === "string" && error.trim()) {
		return error;
	}

	if (
		typeof error === "object" &&
		error !== null &&
		"message" in error &&
		typeof error.message === "string" &&
		error.message.trim()
	) {
		return error.message;
	}

	return fallback;
}

function normalizeReleaseNotes(releaseNotes: UpdateInfoLike["releaseNotes"]): string | null {
	if (!releaseNotes) {
		return null;
	}

	if (typeof releaseNotes === "string") {
		const trimmed = releaseNotes.trim();
		return trimmed ? trimmed : null;
	}

	const sections = releaseNotes
		.map((entry) => {
			const note = entry.note?.trim();
			if (!note) {
				return null;
			}
			return entry.version?.trim() ? `Version ${entry.version}\n${note}` : note;
		})
		.filter((entry): entry is string => Boolean(entry));

	return sections.length > 0 ? sections.join("\n\n") : null;
}

function createBaseState(): UpdaterState {
	return {
		supported: app.isPackaged,
		dialogOpen: false,
		status: "idle",
		currentVersion: app.getVersion(),
		version: null,
		releaseNotes: null,
		downloadProgress: 0,
		error: null,
	};
}

export class AppUpdaterService {
	private state: UpdaterState = createBaseState();
	private readonly supported = app.isPackaged;
	private checkInFlight: Promise<UpdaterState> | null = null;
	private downloadInFlight: Promise<UpdaterState> | null = null;
	private interactiveCheck = false;

	constructor(private readonly emit: EmitFn) {
		if (!this.supported) {
			return;
		}

		autoUpdater.autoDownload = false;
		autoUpdater.autoInstallOnAppQuit = false;
		autoUpdater.on("checking-for-update", () => {
			this.patchState({
				status: "checking",
				error: null,
				version: null,
				releaseNotes: null,
				downloadProgress: 0,
			});
		});
		autoUpdater.on("update-available", (info) => {
			this.patchState({
				dialogOpen: true,
				status: "available",
				version: info.version ?? null,
				releaseNotes: normalizeReleaseNotes(info.releaseNotes),
				downloadProgress: 0,
				error: null,
			});
		});
		autoUpdater.on("update-not-available", () => {
			if (this.interactiveCheck) {
				this.patchState({
					dialogOpen: true,
					status: "up-to-date",
					version: null,
					releaseNotes: null,
					downloadProgress: 0,
					error: null,
				});
			} else {
				this.resetState();
			}
			this.interactiveCheck = false;
		});
		autoUpdater.on("download-progress", (progress) => {
			const percent = Math.max(0, Math.min(Math.round(progress.percent ?? 0), 100));
			this.patchState({
				dialogOpen: true,
				status: "downloading",
				downloadProgress: percent,
				error: null,
			});
			this.emit("updater-download-progress", { percent });
		});
		autoUpdater.on("update-downloaded", (info) => {
			this.patchState({
				dialogOpen: true,
				status: "ready",
				version: info.version ?? this.state.version,
				releaseNotes: normalizeReleaseNotes(info.releaseNotes) ?? this.state.releaseNotes,
				downloadProgress: 100,
				error: null,
			});
		});
		autoUpdater.on("error", (error) => {
			const message = normalizeErrorMessage(error, "Failed to update Open Recorder.");
			const shouldShowDialog =
				this.state.status === "downloading" || this.state.dialogOpen || this.interactiveCheck;
			if (shouldShowDialog) {
				this.patchState({
					dialogOpen: true,
					status: "error",
					error: message,
				});
			} else {
				this.resetState();
			}
			this.interactiveCheck = false;
		});
	}

	getState(): UpdaterState {
		return { ...this.state };
	}

	async checkForUpdates(
		{ showDialog = false }: UpdaterCheckOptions = {},
	): Promise<UpdaterState> {
		if (!this.supported) {
			if (showDialog) {
				this.patchState({
					dialogOpen: true,
					status: "error",
					error: "Updates are unavailable in development builds.",
				});
			}
			return this.getState();
		}

		if (this.state.status === "downloading" || this.state.status === "checking") {
			if (showDialog && !this.state.dialogOpen) {
				this.patchState({ dialogOpen: true });
			}
			return this.checkInFlight ?? this.downloadInFlight ?? Promise.resolve(this.getState());
		}

		if ((this.state.status === "available" || this.state.status === "ready") && showDialog) {
			this.patchState({ dialogOpen: true });
			return this.getState();
		}

		this.interactiveCheck = showDialog;
		this.patchState({
			dialogOpen: showDialog,
			status: "checking",
			version: null,
			releaseNotes: null,
			downloadProgress: 0,
			error: null,
		});

		const run = autoUpdater
			.checkForUpdates()
			.then((result) => {
				if (!result?.updateInfo) {
					return this.getState();
				}

				return this.handleImmediateUpdateInfo(result.updateInfo);
			})
			.catch((error) => {
				const message = normalizeErrorMessage(error, "Failed to check for updates.");
				this.patchState({
					dialogOpen: showDialog,
					status: "error",
					error: message,
				});
				this.interactiveCheck = false;
				return this.getState();
			})
			.finally(() => {
				this.checkInFlight = null;
			});

		this.checkInFlight = run;
		return run;
	}

	async downloadUpdate(): Promise<UpdaterState> {
		if (!this.supported) {
			this.patchState({
				dialogOpen: true,
				status: "error",
				error: "Updates are unavailable in development builds.",
			});
			return this.getState();
		}

		if (this.state.status === "ready") {
			this.patchState({ dialogOpen: true });
			return this.getState();
		}

		if (this.state.status !== "available") {
			this.patchState({
				dialogOpen: true,
				status: "error",
				error: "No update is ready to download.",
			});
			return this.getState();
		}

		if (this.downloadInFlight) {
			return this.downloadInFlight;
		}

		this.patchState({
			dialogOpen: true,
			status: "downloading",
			downloadProgress: 0,
			error: null,
		});

		const run = autoUpdater
			.downloadUpdate()
			.then(() => this.getState())
			.catch((error) => {
				const message = normalizeErrorMessage(error, "Failed to download the update.");
				this.patchState({
					dialogOpen: true,
					status: "error",
					error: message,
				});
				return this.getState();
			})
			.finally(() => {
				this.downloadInFlight = null;
			});

		this.downloadInFlight = run;
		return run;
	}

	dismissDialog(): UpdaterState {
		if (this.state.status === "checking" || this.state.status === "downloading") {
			return this.getState();
		}

		if (this.state.status === "available" || this.state.status === "ready") {
			this.patchState({
				dialogOpen: false,
				error: null,
			});
			return this.getState();
		}

		this.resetState();
		return this.getState();
	}

	installUpdateAndRestart(): void {
		if (!this.supported) {
			this.patchState({
				dialogOpen: true,
				status: "error",
				error: "Updates are unavailable in development builds.",
			});
			return;
		}

		if (this.state.status !== "ready") {
			this.patchState({
				dialogOpen: true,
				status: "error",
				error: "The downloaded update is not ready to install yet.",
			});
			return;
		}

		setImmediate(() => {
			autoUpdater.quitAndInstall(false, true);
		});
	}

	private handleImmediateUpdateInfo(updateInfo: UpdateInfoLike): UpdaterState {
		if (updateInfo.version && updateInfo.version !== this.state.currentVersion) {
			this.patchState({
				dialogOpen: true,
				status: "available",
				version: updateInfo.version,
				releaseNotes: normalizeReleaseNotes(updateInfo.releaseNotes),
				downloadProgress: 0,
				error: null,
			});
			this.interactiveCheck = false;
			return this.getState();
		}

		if (this.interactiveCheck) {
			this.patchState({
				dialogOpen: true,
				status: "up-to-date",
				version: null,
				releaseNotes: null,
				downloadProgress: 0,
				error: null,
			});
		} else {
			this.resetState();
		}
		this.interactiveCheck = false;
		return this.getState();
	}

	private patchState(patch: Partial<UpdaterState>): void {
		this.state = {
			...this.state,
			...patch,
			supported: this.supported,
			currentVersion: app.getVersion(),
		};
		this.emit("updater-state-changed", this.getState());
	}

	private resetState(): void {
		this.state = createBaseState();
		this.emit("updater-state-changed", this.getState());
	}
}
