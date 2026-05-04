import { useActor } from "@xstate/react";
import { useAtom } from "jotai";
import { AppWindow, BoxSelect, Camera, ChevronLeft, Monitor, Video } from "lucide-react";
import { forwardRef, type ReactNode, useCallback, useEffect, useMemo, useRef } from "react";
import { BsRecordCircle } from "react-icons/bs";
import { FaRegStopCircle } from "react-icons/fa";
import {
	MdMic,
	MdMicOff,
	MdMonitor,
	MdVideocam,
	MdVideocamOff,
	MdVolumeOff,
	MdVolumeUp,
} from "react-icons/md";
import { RxDragHandleDots2 } from "react-icons/rx";
import {
	isCapturingAtom,
	launchViewAtom,
	recordingElapsedAtom,
	recordingStartAtom,
	type ScreenshotMode,
	screenshotModeAtom,
	selectedSourceStatusAtom,
} from "@/atoms/launch";
import { buildEditorWindowQuery } from "@/components/video-editor/editorWindowParams";
import * as backend from "@/lib/backend";
import { cn } from "@/lib/utils";
import { useCameraDevices } from "../../hooks/useCameraDevices";
import { useMicrophoneDevices } from "../../hooks/useMicrophoneDevices";
import { usePermissions } from "../../hooks/usePermissions";
import { useScreenRecorder } from "../../hooks/useScreenRecorder";
import { microphoneMachine } from "../../machines/microphoneMachine";
import { PermissionOnboarding } from "../onboarding/PermissionOnboarding";
import { Button } from "../ui/button";
import { Popover, PopoverAnchor, PopoverContent } from "../ui/popover";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../ui/select";
import { Switch } from "../ui/switch";
import { resolveSelectedSourceState } from "./launchWindowState";

const SYSTEM_DEFAULT_MICROPHONE_ID = "__system_default_microphone__";

// ─── Mode Button ────────────────────────────────────────────────────────────

function ModeButton({
	icon,
	active,
	onClick,
	title,
	label,
	disabled,
}: {
	icon: ReactNode;
	active: boolean;
	onClick: () => void;
	title: string;
	label: string;
	disabled?: boolean;
}) {
	return (
		<Button
			variant="ghost"
			onClick={onClick}
			title={title}
			disabled={disabled}
			className={cn(
				"hud-no-drag h-9 min-w-[66px] gap-1.5 rounded-full px-2 text-[12px] font-semibold transition-all duration-200",
				active
					? "bg-white text-zinc-950 shadow-[0_6px_18px_rgba(0,0,0,0.24)] hover:bg-white"
					: "text-white/55 hover:bg-white/[0.08] hover:text-white",
			)}
		>
			{icon}
			<span>{label}</span>
		</Button>
	);
}

const HudIconButton = forwardRef<
	HTMLButtonElement,
	{
		children: ReactNode;
		title: string;
		onClick?: () => void;
		disabled?: boolean;
		active?: boolean;
		danger?: boolean;
	}
>(function HudIconButton({ children, title, onClick, disabled, active, danger }, ref) {
	return (
		<Button
			ref={ref}
			variant="ghost"
			size="icon"
			onClick={onClick}
			title={title}
			disabled={disabled}
			className={cn(
				"hud-no-drag h-9 w-9 rounded-full border border-white/[0.08] bg-white/[0.055] text-white/55 shadow-inner shadow-white/[0.03] transition-all duration-200 hover:border-white/15 hover:bg-white/[0.1] hover:text-white",
				active &&
					"border-blue-300/35 bg-blue-400/15 text-blue-200 shadow-[0_0_18px_rgba(59,130,246,0.2)]",
				danger && "border-red-300/35 bg-red-500/15 text-red-200",
			)}
		>
			{children}
		</Button>
	);
});

function SourceChip({
	source,
	available,
	disabled,
	onClick,
	title,
}: {
	source: string;
	available: boolean;
	disabled?: boolean;
	onClick: () => void;
	title?: string;
}) {
	return (
		<Button
			variant="ghost"
			size="sm"
			className={cn(
				"hud-no-drag h-9 min-w-0 max-w-[150px] justify-start gap-2 rounded-full border border-white/[0.1] bg-black/20 px-2.5 text-xs font-medium text-white/75 shadow-inner shadow-white/[0.03] transition-all duration-200 hover:border-white/20 hover:bg-white/[0.08] hover:text-white",
				!available && "text-white/38 hover:text-white/55",
			)}
			onClick={onClick}
			disabled={disabled}
			title={title || source}
		>
			<span
				className={cn(
					"h-2 w-2 shrink-0 rounded-full bg-amber-300 shadow-[0_0_10px_rgba(252,211,77,0.55)]",
					available && "bg-emerald-300 shadow-[0_0_10px_rgba(110,231,183,0.55)]",
				)}
			/>
			<MdMonitor size={15} className="shrink-0 text-white/65" />
			<span className="min-w-0 truncate">{source || "Choose source"}</span>
		</Button>
	);
}

function FlowLabel({
	tone,
	label,
	value,
}: {
	tone: "blue" | "red" | "amber";
	label: string;
	value: string;
}) {
	return (
		<div className="flex min-w-[84px] items-center gap-2 rounded-full border border-white/[0.08] bg-white/[0.055] px-2.5 py-1.5">
			<span
				className={cn(
					"h-2 w-2 rounded-full",
					tone === "blue" && "bg-blue-300 shadow-[0_0_12px_rgba(147,197,253,0.65)]",
					tone === "red" && "hud-recording-dot bg-red-400 shadow-[0_0_12px_rgba(248,113,113,0.7)]",
					tone === "amber" && "bg-amber-300 shadow-[0_0_12px_rgba(252,211,77,0.65)]",
				)}
			/>
			<div className="leading-none">
				<div className="text-[9px] font-semibold uppercase text-white/38">{label}</div>
				<div className="mt-1 text-[12px] font-semibold text-white/82">{value}</div>
			</div>
		</div>
	);
}

// ─── Shared classes ─────────────────────────────────────────────────────────

const HUD_BAR_CLASS = "hud-surface hud-drag min-h-[58px] rounded-[28px]";
const HUD_DIALOG_CLASS = "hud-surface hud-drag min-h-[62px] rounded-[28px]";

// ─── LaunchWindow ───────────────────────────────────────────────────────────

export function LaunchWindow() {
	const [view, setView] = useAtom(launchViewAtom);
	const [screenshotMode, setScreenshotMode] = useAtom(screenshotModeAtom);
	const [isCapturing, setIsCapturing] = useAtom(isCapturingAtom);

	useEffect(() => {
		try {
			if (localStorage.getItem("open-recorder-onboarding-v1") !== "true") {
				setView("onboarding");
			}
		} catch {
			// ignore
		}
	}, [setView]);

	const permissionsHook = usePermissions();

	const {
		recording,
		toggleRecording,
		preparePermissions,
		setMicrophoneEnabled,
		microphoneDeviceId,
		setMicrophoneDeviceId,
		systemAudioEnabled,
		setSystemAudioEnabled,
		cameraEnabled,
		setCameraEnabled,
		cameraDeviceId,
		setCameraDeviceId,
	} = useScreenRecorder();

	const [recordingStart, setRecordingStart] = useAtom(recordingStartAtom);
	const [elapsed, setElapsed] = useAtom(recordingElapsedAtom);
	const showCameraPreview = cameraEnabled && !recording && view === "recording";

	const setMicEnabledRef = useRef(setMicrophoneEnabled);
	setMicEnabledRef.current = setMicrophoneEnabled;

	const providedMachine = useMemo(
		() =>
			microphoneMachine.provide({
				actions: {
					enableMic: () => setMicEnabledRef.current(true),
					disableMic: () => setMicEnabledRef.current(false),
				},
			}),
		[],
	);

	const [micState, micSend] = useActor(providedMachine);

	const isMicEnabled =
		micState.matches("on") || micState.matches("selecting") || micState.matches("lockedOn");
	const isPopoverOpen = micState.matches("selecting");

	// Only enumerate microphone devices when popover is open AND permission is granted
	const micPermissionGranted = permissionsHook.permissions.microphone === "granted";
	const {
		devices,
		selectedDeviceId,
		setSelectedDeviceId,
		isLoading: isLoadingMicrophoneDevices,
		isRequestingAccess: isRequestingMicrophoneAccess,
		permissionDenied: microphonePermissionDenied,
		error: microphoneDevicesError,
	} = useMicrophoneDevices(isPopoverOpen && micPermissionGranted);
	const camPermissionGranted = permissionsHook.permissions.camera === "granted";
	const {
		devices: cameraDevices,
		selectedDeviceId: selectedCameraDeviceId,
		setSelectedDeviceId: setSelectedCameraDeviceId,
		isLoading: isLoadingCameraDevices,
		isRequestingAccess: isRequestingCameraAccess,
		permissionDenied: cameraPermissionDenied,
		error: cameraDevicesError,
	} = useCameraDevices(cameraEnabled && camPermissionGranted);
	const micButtonRef = useRef<HTMLButtonElement | null>(null);
	const cameraPreviewRef = useRef<HTMLVideoElement | null>(null);

	useEffect(() => {
		setMicrophoneDeviceId(selectedDeviceId !== "default" ? selectedDeviceId : undefined);
	}, [selectedDeviceId, setMicrophoneDeviceId]);

	useEffect(() => {
		setCameraDeviceId(selectedCameraDeviceId !== "default" ? selectedCameraDeviceId : undefined);
	}, [selectedCameraDeviceId, setCameraDeviceId]);

	// Sync recording state into the microphone machine
	const prevRecording = useRef(recording);
	useEffect(() => {
		if (recording && !prevRecording.current) {
			micSend({ type: "RECORDING_START" });
		} else if (!recording && prevRecording.current) {
			micSend({ type: "RECORDING_STOP" });
			// When recording stops, return to choice view
			setView("choice");
			setScreenshotMode(null);
		}
		prevRecording.current = recording;
	}, [recording, micSend, setView, setScreenshotMode]);

	// Facecam preview
	useEffect(() => {
		if (!showCameraPreview) {
			if (cameraPreviewRef.current) {
				cameraPreviewRef.current.srcObject = null;
			}
			return;
		}

		let mounted = true;
		let previewStream: MediaStream | null = null;
		const mediaDevices = navigator.mediaDevices;

		const loadPreview = async () => {
			if (!mediaDevices?.getUserMedia) return;
			try {
				previewStream = await mediaDevices.getUserMedia({
					video: cameraDeviceId
						? {
								deviceId: { exact: cameraDeviceId },
								width: { ideal: 640, max: 640 },
								height: { ideal: 360, max: 360 },
								frameRate: { ideal: 30, max: 30 },
							}
						: {
								width: { ideal: 640, max: 640 },
								height: { ideal: 360, max: 360 },
								frameRate: { ideal: 30, max: 30 },
							},
					audio: false,
				});

				if (!mounted || !cameraPreviewRef.current) {
					previewStream?.getTracks().forEach((track) => track.stop());
					return;
				}

				cameraPreviewRef.current.srcObject = previewStream;
				if (cameraPreviewRef.current) {
					await cameraPreviewRef.current.play().catch((err) => {
						console.warn("Camera preview play() failed:", err);
					});
				}
			} catch (error) {
				console.error("Failed to load facecam preview:", error);
			}
		};

		void loadPreview();

		return () => {
			mounted = false;
			if (cameraPreviewRef.current) {
				cameraPreviewRef.current.srcObject = null;
			}
			previewStream?.getTracks().forEach((track) => track.stop());
		};
	}, [cameraDeviceId, showCameraPreview]);

	// Elapsed timer
	useEffect(() => {
		let timer: ReturnType<typeof setTimeout> | null = null;
		if (recording) {
			if (!recordingStart) setRecordingStart(Date.now());
			const startTime = recordingStart || Date.now();
			timer = setInterval(() => {
				setElapsed(Math.floor((Date.now() - startTime) / 1000));
			}, 1000);
		} else {
			setRecordingStart(null);
			setElapsed(0);
			if (timer) clearInterval(timer);
		}
		return () => {
			if (timer) clearInterval(timer);
		};
	}, [recording, recordingStart, setElapsed, setRecordingStart]);

	// Reset recording state atoms on unmount so the HUD never inherits stale
	// elapsed time or a stale start timestamp when the window is reopened.
	useEffect(() => {
		return () => {
			setRecordingStart(null);
			setElapsed(0);
		};
	}, [setRecordingStart, setElapsed]);

	const formatTime = (seconds: number) => {
		const m = Math.floor(seconds / 60)
			.toString()
			.padStart(2, "0");
		const s = (seconds % 60).toString().padStart(2, "0");
		return `${m}:${s}`;
	};

	// Source tracking
	const [selectedSourceStatus, setSelectedSourceStatus] = useAtom(selectedSourceStatusAtom);
	const selectedSource = selectedSourceStatus.name ?? "";
	const hasSelectedSource = selectedSourceStatus.available;
	useEffect(() => {
		const checkSelectedSource = async () => {
			try {
				const source = await backend.getSelectedSource();
				const nextState = resolveSelectedSourceState(source);
				setSelectedSourceStatus({
					name: nextState.selectedSource,
					available: nextState.hasSelectedSource,
					error: null,
				});
			} catch (err) {
				const error = err instanceof Error ? err : new Error(String(err));
				console.warn("[LaunchWindow] source check failed:", error);
				setSelectedSourceStatus((current) => ({
					...current,
					error,
				}));
			}
		};

		void checkSelectedSource();
		const interval = setInterval(checkSelectedSource, 500);
		return () => clearInterval(interval);
	}, [setSelectedSourceStatus]);

	const openSourceSelector = useCallback(
		async (
			tab?: "screens" | "windows" | "area",
			context: "recording" | "screenshot" = "recording",
		) => {
			const permissionsReady = await preparePermissions();
			if (!permissionsReady) return;

			backend.openSourceSelector(tab, context).catch(() => {
				// Ignore selector launch failures because the permissions flow already handled the user-facing error.
			});
		},
		[preparePermissions],
	);

	const openVideoFile = useCallback(async () => {
		const path = await backend.openVideoFilePicker();
		if (!path) return;
		await backend.setCurrentVideoPath(path);
		await backend.switchToEditor(
			buildEditorWindowQuery({
				mode: "video",
				videoPath: path,
			}),
		);
	}, []);

	const openProjectFile = useCallback(async () => {
		const result = await backend.loadProjectFile();
		if (!result?.filePath) return;
		await backend.switchToEditor(
			buildEditorWindowQuery({
				mode: "project",
				projectPath: result.filePath,
			}),
		);
	}, []);

	useEffect(() => {
		let mounted = true;
		const cleanups: Array<() => void> = [];

		void (async () => {
			const [unlistenVideo, unlistenProject, unlistenNewRecording] = await Promise.all([
				backend.onMenuOpenVideoFile(() => {
					void openVideoFile();
				}),
				backend.onMenuLoadProject(() => {
					void openProjectFile();
				}),
				backend.onNewRecordingFromTray(() => {
					void openSourceSelector();
				}),
			]);
			if (!mounted) {
				unlistenVideo();
				unlistenProject();
				unlistenNewRecording();
				return;
			}
			cleanups.push(unlistenVideo, unlistenProject, unlistenNewRecording);
		})();

		return () => {
			mounted = false;
			cleanups.forEach((fn) => fn());
		};
	}, [openProjectFile, openSourceSelector, openVideoFile]);

	const dividerClass = "mx-0.5 h-7 w-px shrink-0 bg-white/[0.1]";

	const toggleCamera = () => {
		if (!recording) {
			setCameraEnabled(!cameraEnabled);
		}
	};

	const microphoneSelectValue = devices.some(
		(device) => device.deviceId === (microphoneDeviceId || selectedDeviceId),
	)
		? microphoneDeviceId || selectedDeviceId
		: SYSTEM_DEFAULT_MICROPHONE_ID;
	const cameraSelectValue = cameraDevices.some(
		(device) => device.deviceId === (cameraDeviceId || selectedCameraDeviceId),
	)
		? cameraDeviceId || selectedCameraDeviceId
		: undefined;
	const micPermissionDeniedOrRestricted =
		permissionsHook.permissions.microphone === "denied" ||
		permissionsHook.permissions.microphone === "restricted";
	const micPermissionNotDetermined = permissionsHook.permissions.microphone === "not_determined";

	const microphoneHelperText = micPermissionDeniedOrRestricted
		? "Microphone access was denied. Open System Settings to grant permission."
		: micPermissionNotDetermined
			? "Microphone permission is required. Click 'Grant Access' below."
			: isRequestingMicrophoneAccess
				? "Requesting microphone access to show all inputs..."
				: microphonePermissionDenied
					? "Microphone access was denied. Using the system default microphone."
					: microphoneDevicesError
						? "Using the system default microphone in this window."
						: isLoadingMicrophoneDevices
							? "Loading microphone devices..."
							: "Choose which microphone to record.";

	const camPermissionDeniedOrRestricted =
		permissionsHook.permissions.camera === "denied" ||
		permissionsHook.permissions.camera === "restricted";

	const cameraHelperText = camPermissionDeniedOrRestricted
		? "Camera access was denied. Open System Settings to grant permission."
		: isRequestingCameraAccess
			? "Requesting camera access to show all cameras..."
			: cameraPermissionDenied
				? "Camera access was denied. Using the default camera when available."
				: cameraDevicesError
					? "Camera device listing is unavailable in this window."
					: isLoadingCameraDevices
						? "Loading camera devices..."
						: "Choose which facecam to preview and record.";

	// ─── Screenshot capture ───────────────────────────────────────────────────

	const handleScreenshotModeSelect = async (mode: ScreenshotMode) => {
		setScreenshotMode(mode);
		if (mode === "area") {
			backend.closeSourceSelector().catch(() => undefined);
			await handleAreaCapture();
		} else {
			await openSourceSelector(mode === "window" ? "windows" : "screens", "screenshot");
		}
	};

	const handleScreenshotCapture = async () => {
		if (isCapturing || !screenshotMode) return;
		setIsCapturing(true);

		try {
			if (screenshotMode === "screen") {
				// Hide HUD so it doesn't appear in the screenshot
				await backend.hudOverlayHide();
				await new Promise((resolve) => setTimeout(resolve, 350));

				const path = await backend.takeScreenshot("screen", undefined);
				if (path) {
					await backend.switchToImageEditor();
				} else {
					await backend.hudOverlayShow();
				}
			} else if (screenshotMode === "window") {
				const source = await backend.getSelectedSource();
				const windowId = source?.windowId;

				if (!windowId) {
					await openSourceSelector("windows", "screenshot");
					setIsCapturing(false);
					return;
				}

				const path = await backend.takeScreenshot("window", windowId);
				if (path) {
					await backend.switchToImageEditor();
				}
			}
		} catch (error) {
			console.error("Screenshot capture failed:", error);
			await backend.hudOverlayShow().catch(() => {
				// Ignore show-window races after a failed capture attempt.
			});
		} finally {
			setIsCapturing(false);
		}
	};

	const handleAreaCapture = async () => {
		if (isCapturing) return;
		setIsCapturing(true);

		try {
			await backend.hudOverlayHide();
			await new Promise((resolve) => setTimeout(resolve, 350));

			const path = await backend.takeScreenshot("area", undefined);
			if (path) {
				await backend.switchToImageEditor();
			} else {
				// User cancelled area selection
				await backend.hudOverlayShow();
			}
		} catch (error) {
			console.error("Area capture failed:", error);
			await backend.hudOverlayShow().catch(() => {
				// Ignore show-window races after a failed area capture attempt.
			});
		} finally {
			setIsCapturing(false);
		}
	};

	// ─── Render helpers ───────────────────────────────────────────────────────

	const dragHandle = (
		<div
			className="hud-drag flex h-9 w-7 cursor-grab touch-none select-none items-center justify-center rounded-full text-white/35 transition-colors hover:bg-white/[0.06] hover:text-white/65 active:cursor-grabbing"
			title="Drag HUD"
		>
			<RxDragHandleDots2 size={16} className="pointer-events-none text-white/35" />
		</div>
	);

	// ─── Render ───────────────────────────────────────────────────────────────

	// Show the onboarding overlay on first launch
	if (view === "onboarding") {
		return (
			<PermissionOnboarding
				permissionsHook={permissionsHook}
				onComplete={() => setView("choice")}
			/>
		);
	}

	return (
		<div className="flex h-full w-full items-end justify-center overflow-hidden bg-transparent p-2">
			<div className="hud-drag mx-auto flex flex-col items-center gap-2">
				{/* ── Facecam preview (only in recording view, before recording starts) ── */}
				{showCameraPreview && (
					<div className="hud-surface hud-no-drag flex items-center gap-3 rounded-[24px] px-3 py-2.5 shadow-xl">
						<div className="h-14 w-24 overflow-hidden rounded-[18px] border border-white/10 bg-black/35 shadow-inner">
							<video
								ref={cameraPreviewRef}
								className="h-full w-full object-cover"
								muted
								playsInline
							/>
						</div>
						<div className="flex flex-col gap-1.5">
							<div className="text-[10px] font-semibold uppercase text-white/50">Facecam</div>
							<div className="max-w-[230px] text-[11px] text-white/55">{cameraHelperText}</div>
							<Select
								value={cameraSelectValue}
								onValueChange={(value) => {
									setSelectedCameraDeviceId(value);
									setCameraDeviceId(value);
								}}
								disabled={
									cameraDevices.length === 0 || isLoadingCameraDevices || isRequestingCameraAccess
								}
							>
								<SelectTrigger className="hud-no-drag h-8 max-w-[230px] rounded-full border-white/15 bg-zinc-900 px-3 py-1 text-xs text-slate-100 outline-none ring-0 ring-offset-0 focus:ring-0 focus:ring-offset-0">
									<SelectValue
										placeholder={
											isRequestingCameraAccess
												? "Unlocking cameras..."
												: isLoadingCameraDevices
													? "Loading cameras..."
													: "Select camera"
										}
									/>
								</SelectTrigger>
								<SelectContent
									className="z-[100] border-white/15 bg-zinc-900 text-slate-100"
									position="popper"
								>
									{cameraDevices.map((device) => (
										<SelectItem
											key={device.deviceId}
											value={device.deviceId}
											className="text-xs focus:bg-white/10 focus:text-white"
										>
											{device.label}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
					</div>
				)}

				{/* ================================================================
            VIEW 1 — Choice Dialog
            [drag]  [ Screenshot ]  [ Record Video ]
           ================================================================ */}
				{view === "choice" && !recording && (
					<div className={cn(HUD_DIALOG_CLASS, "flex items-center gap-3 px-4 py-3")}>
						{dragHandle}

						<Button
							variant="outline"
							onClick={() => {
								setView("screenshot");
								setScreenshotMode(null);
							}}
							className="hud-no-drag h-11 gap-3 rounded-full border-white/[0.1] bg-white/[0.07] px-5 text-[13px] font-semibold text-white/82 shadow-inner shadow-white/[0.04] transition-all duration-200 hover:border-blue-200/35 hover:bg-blue-400/15 hover:text-white"
						>
							<span className="flex h-7 w-7 items-center justify-center rounded-full bg-blue-400/15 text-blue-200">
								<Camera size={16} />
							</span>
							Screenshot
						</Button>

						<Button
							variant="outline"
							onClick={() => setView("recording")}
							className="hud-no-drag h-11 gap-3 rounded-full border-white/[0.1] bg-white/[0.07] px-5 text-[13px] font-semibold text-white/82 shadow-inner shadow-white/[0.04] transition-all duration-200 hover:border-red-200/35 hover:bg-red-400/15 hover:text-white"
						>
							<span className="flex h-7 w-7 items-center justify-center rounded-full bg-red-400/15 text-red-200">
								<Video size={16} />
							</span>
							Record Video
						</Button>
					</div>
				)}

				{/* ================================================================
            VIEW 2 — Screenshot Bar
            [drag] [← back] [Screen] [Window] [Area] | [source] | [Take Screenshot]
           ================================================================ */}
				{view === "screenshot" && !recording && (
					<div className={cn(HUD_BAR_CLASS, "mx-auto flex w-full items-center gap-1.5 px-2 py-2")}>
						{dragHandle}

						{/* Back button */}
						<HudIconButton
							onClick={() => {
								setView("choice");
								setScreenshotMode(null);
							}}
							title="Back"
						>
							<ChevronLeft size={16} />
						</HudIconButton>

						<div className={dividerClass} />

						<FlowLabel
							tone={isCapturing ? "amber" : "blue"}
							label="Screenshot"
							value={isCapturing ? "Capturing" : screenshotMode ? "Ready" : "Mode"}
						/>

						{/* Screenshot mode buttons */}
						<div className="hud-no-drag flex items-center gap-1 rounded-full border border-white/[0.08] bg-black/20 p-1 shadow-inner shadow-black/20">
							<ModeButton
								icon={<Monitor size={15} />}
								active={screenshotMode === "screen"}
								onClick={() => handleScreenshotModeSelect("screen")}
								title="Capture Entire Screen"
								label="Screen"
							/>
							<ModeButton
								icon={<AppWindow size={15} />}
								active={screenshotMode === "window"}
								onClick={() => handleScreenshotModeSelect("window")}
								title="Capture Window"
								label="Window"
							/>
							<ModeButton
								icon={<BoxSelect size={15} />}
								active={screenshotMode === "area"}
								onClick={() => handleScreenshotModeSelect("area")}
								title="Capture Area"
								label="Area"
							/>
						</div>

						{/* Source display + Take Screenshot CTA — shown after source is selected */}
						{screenshotMode && screenshotMode !== "area" && hasSelectedSource && (
							<>
								<div className={dividerClass} />

								{/* Selected source indicator (clickable to re-open source selector) */}
								<SourceChip
									onClick={() =>
										openSourceSelector(
											screenshotMode === "window" ? "windows" : "screens",
											"screenshot",
										)
									}
									title={selectedSource}
									source={selectedSource}
									available={hasSelectedSource}
								/>

								<div className={dividerClass} />

								{/* Take Screenshot CTA */}
								<Button
									variant="ghost"
									size="sm"
									onClick={handleScreenshotCapture}
									disabled={isCapturing}
									className="hud-no-drag h-10 gap-2 rounded-full border border-blue-200/25 bg-blue-400/15 px-3 text-xs font-semibold text-blue-100 shadow-[0_0_24px_rgba(37,99,235,0.22)] transition-all duration-200 hover:border-blue-100/40 hover:bg-blue-400/25 hover:text-white"
								>
									{isCapturing ? (
										<>
											<div className="h-3 w-3 rounded-full border-2 border-white/30 border-t-white animate-spin" />
											<span className="text-white/70">Capturing...</span>
										</>
									) : (
										<>
											<Camera size={15} className="text-blue-100" />
											<span>Capture</span>
										</>
									)}
								</Button>
							</>
						)}
					</div>
				)}

				{/* ================================================================
            VIEW 3 — Recording Controls
            [drag] [← back] [source] | [volume] [mic] [camera] | [record/stop]
           ================================================================ */}
				{(view === "recording" || recording) && (
					<div
						className={cn(
							HUD_BAR_CLASS,
							"mx-auto flex w-full items-center gap-1.5 px-2 py-2",
							recording && "hud-surface-recording",
						)}
					>
						{dragHandle}

						{/* Back button — return to choice (only when not recording) */}
						{!recording && (
							<>
								<HudIconButton onClick={() => setView("choice")} title="Back">
									<ChevronLeft size={16} />
								</HudIconButton>
								<div className={dividerClass} />
							</>
						)}

						<FlowLabel
							tone={recording ? "red" : "blue"}
							label={recording ? "Recording" : "Ready"}
							value={recording ? formatTime(elapsed) : "Video"}
						/>

						{/* Source selector */}
						<SourceChip
							onClick={() => openSourceSelector()}
							disabled={recording}
							title={selectedSource}
							source={selectedSource}
							available={hasSelectedSource}
						/>

						<div className={dividerClass} />

						{/* Audio / Mic / Camera */}
						<div className="hud-no-drag flex items-center gap-1 rounded-full border border-white/[0.08] bg-black/20 p-1 shadow-inner shadow-black/20">
							<HudIconButton
								onClick={() => !recording && setSystemAudioEnabled(!systemAudioEnabled)}
								disabled={recording}
								title={systemAudioEnabled ? "Disable system audio" : "Enable system audio"}
								active={systemAudioEnabled}
							>
								{systemAudioEnabled ? <MdVolumeUp size={16} /> : <MdVolumeOff size={16} />}
							</HudIconButton>

							<Popover open={isPopoverOpen}>
								<PopoverAnchor asChild>
									<HudIconButton
										ref={micButtonRef}
										onClick={() => micSend({ type: "CLICK" })}
										disabled={recording}
										title={isMicEnabled ? "Microphone settings" : "Enable microphone"}
										active={isMicEnabled}
									>
										{isMicEnabled ? <MdMic size={16} /> : <MdMicOff size={16} />}
									</HudIconButton>
								</PopoverAnchor>
								<PopoverContent
									align="center"
									side="top"
									sideOffset={10}
									className="hud-surface hud-no-drag w-[292px] rounded-[24px] p-4 shadow-xl"
									onPointerDownOutside={(e) => {
										if (micButtonRef.current?.contains(e.target as Node)) {
											e.preventDefault();
										} else {
											micSend({ type: "CLOSE_POPOVER" });
										}
									}}
									onEscapeKeyDown={() => micSend({ type: "CLOSE_POPOVER" })}
									onFocusOutside={(e) => e.preventDefault()}
								>
									<div className="mb-2 flex items-center justify-between">
										<span className="text-[10px] font-semibold uppercase text-white/50">
											Microphone
										</span>
										<Switch
											checked={isMicEnabled}
											onCheckedChange={(checked) => {
												if (!checked) micSend({ type: "DISABLE" });
											}}
										/>
									</div>
									<div className="mb-3 text-xs text-white/65">
										<div className="flex items-center gap-2">
											{(isLoadingMicrophoneDevices || isRequestingMicrophoneAccess) && (
												<div className="h-3 w-3 rounded-full border-2 border-white/25 border-t-white animate-spin" />
											)}
											<span>{microphoneHelperText}</span>
										</div>
									</div>

									{/* Show Grant/Settings button when mic permission is not granted on macOS */}
									{!micPermissionGranted && permissionsHook.isMacOS ? (
										<Button
											variant="outline"
											size="sm"
											onClick={() => {
												if (micPermissionDeniedOrRestricted) {
													void permissionsHook.openPermissionSettings("microphone");
												} else {
													void permissionsHook.requestMicrophoneAccess();
												}
											}}
											className="hud-no-drag h-8 w-full rounded-full border-white/15 bg-blue-500/20 px-3 py-1 text-xs font-medium text-blue-300 hover:bg-blue-500/30 hover:text-blue-300"
										>
											{micPermissionDeniedOrRestricted
												? "Open System Settings"
												: "Grant Microphone Access"}
										</Button>
									) : (
										<Select
											value={microphoneSelectValue}
											onValueChange={(value) => {
												if (value === SYSTEM_DEFAULT_MICROPHONE_ID) {
													setSelectedDeviceId("default");
													setMicrophoneDeviceId(undefined);
												} else {
													setSelectedDeviceId(value);
													setMicrophoneDeviceId(value);
												}
											}}
											disabled={isLoadingMicrophoneDevices || isRequestingMicrophoneAccess}
										>
											<SelectTrigger className="hud-no-drag h-8 w-full rounded-full border-white/15 bg-zinc-900 px-3 py-1 text-xs text-slate-100 outline-none ring-0 ring-offset-0 focus:ring-0 focus:ring-offset-0">
												<SelectValue
													placeholder={
														isRequestingMicrophoneAccess
															? "Unlocking microphones..."
															: isLoadingMicrophoneDevices
																? "Loading microphones..."
																: "Select microphone"
													}
												/>
											</SelectTrigger>
											<SelectContent
												className="z-[100] border-white/15 bg-zinc-900 text-slate-100"
												position="popper"
											>
												<SelectItem
													value={SYSTEM_DEFAULT_MICROPHONE_ID}
													className="text-xs focus:bg-white/10 focus:text-white"
												>
													{microphonePermissionDenied || microphoneDevicesError
														? "System Default Microphone"
														: "Default Microphone"}
												</SelectItem>
												{devices.map((device) => (
													<SelectItem
														key={device.deviceId}
														value={device.deviceId}
														className="text-xs focus:bg-white/10 focus:text-white"
													>
														{device.label}
													</SelectItem>
												))}
											</SelectContent>
										</Select>
									)}
								</PopoverContent>
							</Popover>

							<HudIconButton
								onClick={toggleCamera}
								disabled={recording}
								title={cameraEnabled ? "Disable facecam" : "Enable facecam"}
								active={cameraEnabled}
							>
								{cameraEnabled ? <MdVideocam size={16} /> : <MdVideocamOff size={16} />}
							</HudIconButton>
						</div>

						<div className={dividerClass} />

						{/* Record / Stop */}
						<Button
							variant="ghost"
							size="sm"
							onClick={hasSelectedSource ? toggleRecording : () => openSourceSelector()}
							disabled={!hasSelectedSource && !recording}
							className={cn(
								"hud-no-drag h-10 min-w-[118px] gap-2 rounded-full border px-4 text-xs font-semibold transition-all duration-200",
								recording
									? "border-red-200/35 bg-red-500/20 text-red-100 shadow-[0_0_28px_rgba(248,113,113,0.26)] hover:border-red-100/45 hover:bg-red-500/30 hover:text-white"
									: "border-white/15 bg-white text-zinc-950 shadow-[0_8px_24px_rgba(0,0,0,0.25)] hover:bg-blue-50 hover:text-zinc-950",
								!hasSelectedSource && !recording && "bg-white/10 text-white/35 hover:bg-white/10",
							)}
						>
							{recording ? (
								<>
									<FaRegStopCircle size={15} />
									<span className="font-semibold tabular-nums">{formatTime(elapsed)}</span>
								</>
							) : (
								<>
									<BsRecordCircle
										size={15}
										className={hasSelectedSource ? "text-red-500" : "text-white/35"}
									/>
									<span className={hasSelectedSource ? "text-zinc-950" : "text-white/35"}>
										Record
									</span>
								</>
							)}
						</Button>
					</div>
				)}
			</div>
		</div>
	);
}
