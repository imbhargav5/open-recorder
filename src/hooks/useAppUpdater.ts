import { useState, useCallback, useRef, useEffect } from "react";
import { getIdentifier } from "@tauri-apps/api/app";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
import * as backend from "@/lib/backend";

const AUTO_CHECK_DELAY_MS = 10_000;

export type UpdateStatus =
  | "idle"
  | "checking"
  | "available"
  | "downloading"
  | "ready"
  | "error";

export type UseAppUpdaterReturn = {
  status: UpdateStatus;
  version: string | null;
  releaseNotes: string | null;
  downloadProgress: number;
  error: string | null;
  checkForUpdate: () => Promise<void>;
  downloadAndInstall: () => Promise<void>;
  restartApp: () => Promise<void>;
  dismiss: () => void;
};

export function useAppUpdater(): UseAppUpdaterReturn {
  const [updatesEnabled, setUpdatesEnabled] = useState(!import.meta.env.DEV);
  const [status, setStatus] = useState<UpdateStatus>("idle");
  const [version, setVersion] = useState<string | null>(null);
  const [releaseNotes, setReleaseNotes] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const updateRef = useRef<Update | null>(null);

  const checkForUpdate = useCallback(async () => {
    if (!updatesEnabled) {
      updateRef.current = null;
      setStatus("idle");
      setError(null);
      return;
    }

    try {
      setStatus("checking");
      setError(null);

      const update = await check();

      if (update) {
        updateRef.current = update;
        setVersion(update.version);
        setReleaseNotes(update.body ?? null);
        setStatus("available");
      } else {
        updateRef.current = null;
        setStatus("idle");
      }
    } catch (err) {
      console.error("Update check failed:", err);
      setError(err instanceof Error ? err.message : "Failed to check for updates");
      setStatus("error");
    }
  }, [updatesEnabled]);

  const downloadAndInstall = useCallback(async () => {
    const update = updateRef.current;
    if (!update) return;

    try {
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
  }, []);

  const restartApp = useCallback(async () => {
    await relaunch();
  }, []);

  const dismiss = useCallback(() => {
    setStatus("idle");
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
    if (!updatesEnabled) {
      return;
    }

    const timer = setTimeout(() => {
      checkForUpdate();
    }, AUTO_CHECK_DELAY_MS);

    return () => clearTimeout(timer);
  }, [checkForUpdate, updatesEnabled]);

  // Listen for manual "Check for Updates" from the menu
  useEffect(() => {
    let unlisten: backend.UnlistenFn | undefined;

    backend.onMenuCheckUpdates(() => {
      checkForUpdate();
    }).then((fn) => {
      unlisten = fn;
    });

    return () => unlisten?.();
  }, [checkForUpdate]);

  return {
    status,
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
