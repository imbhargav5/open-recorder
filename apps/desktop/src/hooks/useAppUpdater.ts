import { getIdentifier } from "@tauri-apps/api/app";
import { relaunch } from "@tauri-apps/plugin-process";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { useCallback, useEffect, useRef, useState } from "react";
import * as backend from "@/lib/backend";

const AUTO_CHECK_DELAY_MS = 10_000;

export type UpdateStatus =
	| "idle"
	| "checking"
	| "up-to-date"
	| "available"
	| "downloading"
	| "ready"
	| "error";

type CheckForUpdateOptions = {
	showDialog?: boolean;
};

export type UseAppUpdaterReturn = {
	status: UpdateStatus;
	isDialogOpen: boolean;
	isBlocking: boolean;
	version: string | null;
	releaseNotes: string | null;
	downloadProgress: number;
	error: string | null;
	checkForUpdate: (options?: CheckForUpdateOptions) => Promise<void>;
	downloadAndInstall: () => Promise<void>;
	restartApp: () => Promise<void>;
	dismiss: () => void;
};

type UseAppUpdaterOptions = {
	enableAutoCheck?: boolean;
};

export function useAppUpdater({
	enableAutoCheck = true,
}: UseAppUpdaterOptions = {}): UseAppUpdaterReturn {
	const [updatesEnabled, setUpdatesEnabled] = useState(!import.meta.env.DEV);
	const [status, setStatus] = useState<UpdateStatus>("idle");
	const [isDialogOpen, setIsDialogOpen] = useState(false);
	const [version, setVersion] = useState<string | null>(null);
	const [releaseNotes, setReleaseNotes] = useState<string | null>(null);
	const [downloadProgress, setDownloadProgress] = useState(0);
	const [error, setError] = useState<string | null>(null);
	const updateRef = useRef<Update | null>(null);

	const checkForUpdate = useCallback(
		async ({ showDialog = false }: CheckForUpdateOptions = {}) => {
			if (status === "checking" || status === "downloading") {
				if (showDialog) {
					setIsDialogOpen(true);
				}
				return;
			}

			if (!updatesEnabled) {
				updateRef.current = null;
				setVersion(null);
				setReleaseNotes(null);
				setDownloadProgress(0);
				setError(showDialog ? "Updates are unavailable in development builds." : null);
				setStatus(showDialog ? "error" : "idle");
				setIsDialogOpen(showDialog);
				return;
			}

			try {
				if (showDialog) {
					setIsDialogOpen(true);
				}

				setStatus("checking");
				setVersion(null);
				setReleaseNotes(null);
				setDownloadProgress(0);
				setError(null);

				const update = await check();

				if (update) {
					updateRef.current = update;
					setVersion(update.version);
					setReleaseNotes(update.body ?? null);
					setStatus("available");
					setIsDialogOpen(true);
				} else {
					updateRef.current = null;
					setVersion(null);
					setReleaseNotes(null);
					setStatus(showDialog ? "up-to-date" : "idle");
					setIsDialogOpen(showDialog);
				}
			} catch (err) {
				console.error("Update check failed:", err);
				setError(err instanceof Error ? err.message : "Failed to check for updates");
				setStatus("error");
				setIsDialogOpen(showDialog);
			}
		},
		[status, updatesEnabled],
	);

	const downloadAndInstall = useCallback(async () => {
		const update = updateRef.current;
		if (!update || status === "downloading") return;

		try {
			setIsDialogOpen(true);
			setStatus("downloading");
			setDownloadProgress(0);
			setError(null);

			let totalLength = 0;
			let downloaded = 0;

			await update.downloadAndInstall((event) => {
				switch (event.event) {
					case "Started":
						totalLength = event.data.contentLength ?? 0;
						break;
					case "Progress":
						downloaded += event.data.chunkLength;
						if (totalLength > 0) {
							setDownloadProgress(Math.round((downloaded / totalLength) * 100));
						}
						break;
					case "Finished":
						setDownloadProgress(100);
						break;
				}
			});

			setStatus("ready");
		} catch (err) {
			console.error("Update download failed:", err);
			setError(err instanceof Error ? err.message : "Failed to download update");
			setStatus("error");
		}
	}, [status]);

	const restartApp = useCallback(async () => {
		await relaunch();
	}, []);

	const dismiss = useCallback(() => {
		setIsDialogOpen(false);
		setStatus("idle");
		setVersion(null);
		setReleaseNotes(null);
		setDownloadProgress(0);
		setError(null);
		updateRef.current = null;
	}, []);

	useEffect(() => {
		if (import.meta.env.DEV) {
			setUpdatesEnabled(false);
			return;
		}

		let cancelled = false;

		getIdentifier()
			.then((identifier) => {
				if (!cancelled) {
					setUpdatesEnabled(!identifier.endsWith(".dev"));
				}
			})
			.catch(() => {
				if (!cancelled) {
					setUpdatesEnabled(true);
				}
			});

		return () => {
			cancelled = true;
		};
	}, []);

	// Auto-check for updates on mount (after a delay)
	useEffect(() => {
		if (!updatesEnabled || !enableAutoCheck) {
			return;
		}

		const timer = setTimeout(() => {
			checkForUpdate();
		}, AUTO_CHECK_DELAY_MS);

		return () => clearTimeout(timer);
	}, [checkForUpdate, enableAutoCheck, updatesEnabled]);

	// Listen for manual "Check for Updates" from the menu
	useEffect(() => {
		let unlisten: backend.UnlistenFn | undefined;

		backend
			.onMenuCheckUpdates(() => {
				void checkForUpdate({ showDialog: true });
			})
			.then((fn) => {
				unlisten = fn;
			});

		return () => unlisten?.();
	}, [checkForUpdate]);

	return {
		status,
		isDialogOpen,
		isBlocking: status === "checking" || status === "downloading",
		version,
		releaseNotes,
		downloadProgress,
		error,
		checkForUpdate,
		downloadAndInstall,
		restartApp,
		dismiss,
	};
}
