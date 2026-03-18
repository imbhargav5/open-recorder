import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { useAppUpdater } from "@/hooks/useAppUpdater";

export function UpdateNotification() {
  const {
    status,
    version,
    releaseNotes,
    downloadProgress,
    error,
    checkForUpdate,
    downloadAndInstall,
    restartApp,
    dismiss,
  } = useAppUpdater();

  const hasNotifiedAvailable = useRef(false);
  const downloadToastId = useRef<string | number | undefined>(undefined);

  // Show toast when an update is available
  useEffect(() => {
    if (status === "available" && version && !hasNotifiedAvailable.current) {
      hasNotifiedAvailable.current = true;

      toast(`Update available: v${version}`, {
        description: releaseNotes
          ? releaseNotes.length > 120
            ? `${releaseNotes.slice(0, 120)}...`
            : releaseNotes
          : "A new version of Open Recorder is ready to install.",
        duration: Infinity,
        action: {
          label: "Update",
          onClick: () => downloadAndInstall(),
        },
        cancel: {
          label: "Later",
          onClick: () => dismiss(),
        },
      });
    }
  }, [status, version, releaseNotes, downloadAndInstall, dismiss]);

  // Show download progress
  useEffect(() => {
    if (status === "downloading") {
      if (downloadToastId.current === undefined) {
        downloadToastId.current = toast.loading(
          `Downloading update... ${downloadProgress}%`,
          { duration: Infinity }
        );
      } else {
        toast.loading(`Downloading update... ${downloadProgress}%`, {
          id: downloadToastId.current,
          duration: Infinity,
        });
      }
    }
  }, [status, downloadProgress]);

  // Show restart prompt when ready
  useEffect(() => {
    if (status === "ready") {
      if (downloadToastId.current !== undefined) {
        toast.dismiss(downloadToastId.current);
        downloadToastId.current = undefined;
      }

      toast.success("Update installed!", {
        description: "Restart Open Recorder to apply the update.",
        duration: Infinity,
        action: {
          label: "Restart now",
          onClick: () => restartApp(),
        },
        cancel: {
          label: "Later",
          onClick: () => dismiss(),
        },
      });
    }
  }, [status, restartApp, dismiss]);

  // Show error
  useEffect(() => {
    if (status === "error" && error) {
      if (downloadToastId.current !== undefined) {
        toast.dismiss(downloadToastId.current);
        downloadToastId.current = undefined;
      }

      toast.error("Update failed", {
        description: error,
        action: {
          label: "Retry",
          onClick: () => checkForUpdate(),
        },
      });
    }
  }, [status, error, checkForUpdate]);

  // Reset notification state when dismissed
  useEffect(() => {
    if (status === "idle") {
      hasNotifiedAvailable.current = false;
    }
  }, [status]);

  // This component only drives toasts, no visible DOM
  return null;
}
