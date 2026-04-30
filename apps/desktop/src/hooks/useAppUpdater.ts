import { useAtom } from "jotai";
import { useCallback, useEffect, useState } from "react";
import {
	type UpdateStatus,
	updaterDialogOpenAtom,
	updaterDownloadProgressAtom,
	updaterErrorAtom,
	updaterReleaseNotesAtom,
	updaterStatusAtom,
	updaterVersionAtom,
} from "@/atoms/updater";
import * as backend from "@/lib/backend";
import type { UpdaterState } from "@/lib/backend";

export type { UpdateStatus } from "@/atoms/updater";

const AUTO_CHECK_DELAY_MS = 10_000;

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
	dismiss: () => Promise<void>;
};

type UseAppUpdaterOptions = {
	enableAutoCheck?: boolean;
};

function applyUpdaterState(
	state: UpdaterState,
	setStatus: (value: UpdateStatus) => void,
	setDialogOpen: (value: boolean) => void,
	setVersion: (value: string | null) => void,
	setReleaseNotes: (value: string | null) => void,
	setDownloadProgress: (value: number) => void,
	setError: (value: string | null) => void,
	setUpdatesEnabled: (value: boolean) => void,
): void {
	setUpdatesEnabled(state.supported);
	setStatus(state.status);
	setDialogOpen(state.dialogOpen);
	setVersion(state.version);
	setReleaseNotes(state.releaseNotes);
	setDownloadProgress(state.downloadProgress);
	setError(state.error);
}

export function useAppUpdater({
	enableAutoCheck = true,
}: UseAppUpdaterOptions = {}): UseAppUpdaterReturn {
	const [updatesEnabled, setUpdatesEnabled] = useState(false);
	const [status, setStatus] = useAtom(updaterStatusAtom);
	const [isDialogOpen, setIsDialogOpen] = useAtom(updaterDialogOpenAtom);
	const [version, setVersion] = useAtom(updaterVersionAtom);
	const [releaseNotes, setReleaseNotes] = useAtom(updaterReleaseNotesAtom);
	const [downloadProgress, setDownloadProgress] = useAtom(updaterDownloadProgressAtom);
	const [error, setError] = useAtom(updaterErrorAtom);

	const syncState = useCallback(
		(state: UpdaterState) => {
			applyUpdaterState(
				state,
				setStatus,
				setIsDialogOpen,
				setVersion,
				setReleaseNotes,
				setDownloadProgress,
				setError,
				setUpdatesEnabled,
			);
		},
		[
			setDownloadProgress,
			setError,
			setIsDialogOpen,
			setReleaseNotes,
			setStatus,
			setVersion,
		],
	);

	useEffect(() => {
		let cancelled = false;
		let unlistenState: backend.UnlistenFn | undefined;
		let unlistenProgress: backend.UnlistenFn | undefined;

		void backend.getUpdaterState().then((state) => {
			if (!cancelled) {
				syncState(state);
			}
		});

		void backend.onUpdaterStateChanged((state) => {
			if (!cancelled) {
				syncState(state);
			}
		}).then((fn) => {
			unlistenState = fn;
		});

		void backend.onUpdaterDownloadProgress(({ percent }) => {
			if (!cancelled) {
				setDownloadProgress(percent);
			}
		}).then((fn) => {
			unlistenProgress = fn;
		});

		return () => {
			cancelled = true;
			unlistenState?.();
			unlistenProgress?.();
		};
	}, [setDownloadProgress, syncState]);

	const checkForUpdate = useCallback(
		async (options: CheckForUpdateOptions = {}) => {
			const nextState = await backend.checkForUpdates(options);
			syncState(nextState);
		},
		[syncState],
	);

	const downloadAndInstall = useCallback(async () => {
		const nextState = await backend.downloadUpdate();
		syncState(nextState);
	}, [syncState]);

	const restartApp = useCallback(async () => {
		await backend.installUpdateAndRestart();
	}, []);

	const dismiss = useCallback(async () => {
		const nextState = await backend.dismissUpdaterDialog();
		syncState(nextState);
	}, [syncState]);

	useEffect(() => {
		if (!updatesEnabled || !enableAutoCheck) {
			return;
		}

		const timer = setTimeout(() => {
			void checkForUpdate();
		}, AUTO_CHECK_DELAY_MS);

		return () => clearTimeout(timer);
	}, [checkForUpdate, enableAutoCheck, updatesEnabled]);

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
