const VIDEO_EDITOR_PERF_PREFIX = "open-recorder.video-editor";

export function markVideoEditorTiming(stage: string) {
	if (!import.meta.env.DEV) {
		return;
	}

	if (typeof performance === "undefined" || typeof performance.mark !== "function") {
		return;
	}

	performance.mark(`${VIDEO_EDITOR_PERF_PREFIX}.${stage}`);
}
