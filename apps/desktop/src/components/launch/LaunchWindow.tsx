import { useActor } from "@xstate/react";
import { useAtom } from "jotai";
import { AppWindow, BoxSelect, Camera, ChevronLeft, Monitor, Video } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef } from "react";
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
	hasSelectedSourceAtom,
	isCapturingAtom,
	launchViewAtom,
	recordingElapsedAtom,
	recordingStartAtom,
	type ScreenshotMode,
	screenshotModeAtom,
	selectedSourceAtom,
	sourceCheckErrorAtom,
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
import { ContentClamp } from "../ui/content-clamp";
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
	disabled,
}: {
	icon: React.ReactNode;
	active: boolean;
	onClick: () => void;
	title: string;
	disabled?: boolean;
}) {
	return (
		<Button
			variant="ghost"
			size="icon"
			onClick={onClick}
			title={title}
			disabled={disabled}
			className={cn(
				"hud-no-drag h-[30px] w-[30px] rounded-md transition-all",
				active
					? "bg-white/15 text-white shadow-sm hover:bg-white/15"
					: "text-white/40 hover:bg-white/5 hover:text-white/70",
			)}
		>
			{icon}
		</Button>
	);
}

// ─── Shared classes ─────────────────────────────────────────────────────────

const HUD_BAR_CLASS = "hud-surface hud-drag min-h-12 rounded-full";
const HUD_DIALOG_CLASS = "hud-surface hud-drag min-h-12 rounded-[18px]";

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
	const [selectedSource, setSelectedSource] = useAtom(selectedSourceAtom);
	const [hasSelectedSource, setHasSelectedSource] = useAtom(hasSelectedSourceAtom);
	const [, setSourceCheckError] = useAtom(sourceCheckErrorAtom);
	useEffect(() => {
		const checkSelectedSource = async () => {
			try {
				const source = await backend.getSelectedSource();
				const nextState = resolveSelectedSourceState(source);
				setSelectedSource(nextState.selectedSource);
				setHasSelectedSource(nextState.hasSelectedSource);
				setSourceCheckError(null);
			} catch (err) {
				const error = err instanceof Error ? err : new Error(String(err));
				console.warn("[LaunchWindow] source check failed:", error);
				setSourceCheckError(error);
			}
		};

		void checkSelectedSource();
		const interval = setInterval(checkSelectedSource, 500);
		return () => clearInterval(interval);
	}, [setHasSelectedSource, setSelectedSource, setSourceCheckError]);

	const openSourceSelector = useCallback(
		async (tab?: "screens" | "windows") => {
			const permissionsReady = await preparePermissions();
			if (!permissionsReady) return;

			backend.openSourceSelector(tab).catch(() => {
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

	const dividerClass = "mx-1 h-5 w-px shrink-0 bg-white/20";

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
			await openSourceSelector(mode === "window" ? "windows" : "screens");
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
					await openSourceSelector();
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

	const handleDragHandlePointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
		event.preventDefault();
		event.stopPropagation();

		void backend.startHudOverlayDrag().catch((error) => {
			console.error("Failed to start HUD overlay drag:", error);
		});
	}, []);

	const dragHandle = (
		<div
			className="hud-no-drag flex cursor-grab touch-none select-none items-center px-1 active:cursor-grabbing"
			onPointerDown={handleDragHandlePointerDown}
		>
			<RxDragHandleDots2 size={16} className="text-white/35" />
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
		<div className="flex h-full w-full items-end justify-center overflow-hidden bg-transparent">
			<div className="hud-drag mx-auto flex flex-col items-center gap-2">
				{/* ── Facecam preview (only in recording view, before recording starts) ── */}
				{showCameraPreview && (
					<div className="hud-surface hud-no-drag flex items-center gap-3 rounded-[22px] px-3 py-2 shadow-xl">
						<div className="h-14 w-24 overflow-hidden rounded-2xl border border-white/10 bg-black/30">
							<video
								ref={cameraPreviewRef}
								className="h-full w-full object-cover"
								muted
								playsInline
							/>
						</div>
						<div className="flex flex-col gap-1.5">
							<div className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">
								Facecam
							</div>
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
							className="hud-no-drag h-auto gap-2.5 rounded-xl border-white/[0.08] bg-white/[0.06] px-5 py-2.5 text-[13px] font-medium text-white/80 hover:border-white/[0.15] hover:bg-white/[0.12] hover:text-white"
						>
							<Camera size={16} className="text-white/70" />
							Screenshot
						</Button>

						<Button
							variant="outline"
							onClick={() => setView("recording")}
							className="hud-no-drag h-auto gap-2.5 rounded-xl border-white/[0.08] bg-white/[0.06] px-5 py-2.5 text-[13px] font-medium text-white/80 hover:border-white/[0.15] hover:bg-white/[0.12] hover:text-white"
						>
							<Video size={16} className="text-white/70" />
							Record Video
						</Button>
					</div>
				)}

				{/* ================================================================
            VIEW 2 — Screenshot Bar
            [drag] [← back] [Screen] [Window] [Area] | [source] | [Take Screenshot]
           ================================================================ */}
				{view === "screenshot" && !recording && (
					<div className={cn(HUD_BAR_CLASS, "mx-auto flex w-full items-center gap-1.5 px-3 py-2")}>
						{dragHandle}

						{/* Back button */}
						<Button
							variant="link"
							size="icon"
							onClick={() => {
								setView("choice");
								setScreenshotMode(null);
							}}
							title="Back"
							className="hud-no-drag text-white/60 hover:bg-transparent hover:text-white"
						>
							<ChevronLeft size={16} />
						</Button>

						<div className={dividerClass} />

						{/* Screenshot mode buttons */}
						<div className="flex items-center gap-0.5 bg-white/[0.06] rounded-lg p-[3px]">
							<ModeButton
								icon={<Monitor size={15} />}
								active={screenshotMode === "screen"}
								onClick={() => handleScreenshotModeSelect("screen")}
								title="Capture Entire Screen"
							/>
							<ModeButton
								icon={<AppWindow size={15} />}
								active={screenshotMode === "window"}
								onClick={() => handleScreenshotModeSelect("window")}
								title="Capture Window"
							/>
							<ModeButton
								icon={<BoxSelect size={15} />}
								active={screenshotMode === "area"}
								onClick={() => handleScreenshotModeSelect("area")}
								title="Capture Area"
							/>
						</div>

						{/* Source display + Take Screenshot CTA — shown after source is selected */}
						{screenshotMode && screenshotMode !== "area" && hasSelectedSource && (
							<>
								<div className={dividerClass} />

								{/* Selected source indicator (clickable to re-open source selector) */}
								<Button
									variant="link"
									size="sm"
									className="hud-no-drag gap-1 bg-transparent px-0 text-xs text-white/60 hover:bg-transparent"
									onClick={() => openSourceSelector()}
									title={selectedSource}
								>
									<MdMonitor size={14} className="text-white/60" />
									<ContentClamp truncateLength={10}>{selectedSource}</ContentClamp>
								</Button>

								<div className={dividerClass} />

								{/* Take Screenshot CTA */}
								<Button
									variant="link"
									size="sm"
									onClick={handleScreenshotCapture}
									disabled={isCapturing}
									className="hud-no-drag gap-1.5 bg-transparent px-1 text-xs font-medium text-white hover:bg-transparent"
								>
									{isCapturing ? (
										<>
											<div className="h-3 w-3 rounded-full border-2 border-white/30 border-t-white animate-spin" />
											<span className="text-white/70">Capturing...</span>
										</>
									) : (
										<>
											<Camera size={14} className="text-white/85" />
											<span className="text-white/80">Take Screenshot</span>
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
					<div className={cn(HUD_BAR_CLASS, "mx-auto flex w-full items-center gap-1.5 px-3 py-2")}>
						{dragHandle}

						{/* Back button — return to choice (only when not recording) */}
						{!recording && (
							<>
								<Button
									variant="link"
									size="icon"
									onClick={() => setView("choice")}
									title="Back"
									className="hud-no-drag text-white/60 hover:bg-transparent hover:text-white"
								>
									<ChevronLeft size={16} />
								</Button>
								<div className={dividerClass} />
							</>
						)}

						{/* Source selector */}
						<Button
							variant="link"
							size="sm"
							className="hud-no-drag gap-1 bg-transparent px-0 text-xs text-white/80 hover:bg-transparent"
							onClick={() => openSourceSelector()}
							disabled={recording}
							title={selectedSource}
						>
							<MdMonitor size={14} className="text-white/80" />
							<ContentClamp truncateLength={6}>{selectedSource}</ContentClamp>
						</Button>

						<div className={dividerClass} />

						{/* Audio / Mic / Camera */}
						<div className="hud-no-drag flex items-center gap-1">
							<Button
								variant="link"
								size="icon"
								onClick={() => !recording && setSystemAudioEnabled(!systemAudioEnabled)}
								disabled={recording}
								title={systemAudioEnabled ? "Disable system audio" : "Enable system audio"}
								className="hud-no-drag text-white/80 hover:bg-transparent"
							>
								{systemAudioEnabled ? (
									<MdVolumeUp size={16} className="text-[#2563EB]" />
								) : (
									<MdVolumeOff size={16} className="text-white/35" />
								)}
							</Button>

							<Popover open={isPopoverOpen}>
								<PopoverAnchor asChild>
									<Button
										ref={micButtonRef}
										variant="link"
										size="icon"
										onClick={() => micSend({ type: "CLICK" })}
										disabled={recording}
										title={isMicEnabled ? "Microphone settings" : "Enable microphone"}
										className="hud-no-drag text-white/80 hover:bg-transparent"
									>
										{isMicEnabled ? (
											<MdMic size={16} className="text-[#2563EB]" />
										) : (
											<MdMicOff size={16} className="text-white/35" />
										)}
									</Button>
								</PopoverAnchor>
								<PopoverContent
									align="center"
									side="top"
									sideOffset={10}
									className="hud-surface hud-no-drag w-[280px] rounded-2xl p-3 shadow-xl"
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
										<span className="text-[10px] font-medium tracking-[0.18em] uppercase text-white/50">
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

							<Button
								variant="link"
								size="icon"
								onClick={toggleCamera}
								disabled={recording}
								title={cameraEnabled ? "Disable facecam" : "Enable facecam"}
								className="hud-no-drag text-white/80 hover:bg-transparent"
							>
								{cameraEnabled ? (
									<MdVideocam size={16} className="text-[#2563EB]" />
								) : (
									<MdVideocamOff size={16} className="text-white/35" />
								)}
							</Button>
						</div>

						<div className={dividerClass} />

						{/* Record / Stop */}
						<Button
							variant="link"
							size="sm"
							onClick={hasSelectedSource ? toggleRecording : () => openSourceSelector()}
							disabled={!hasSelectedSource && !recording}
							className="hud-no-drag gap-1 bg-transparent px-0 text-xs text-white hover:bg-transparent"
						>
							{recording ? (
								<>
									<FaRegStopCircle size={14} className="text-red-400" />
									<span className="text-red-400 font-medium tabular-nums">
										{formatTime(elapsed)}
									</span>
								</>
							) : (
								<>
									<BsRecordCircle
										size={14}
										className={hasSelectedSource ? "text-white/85" : "text-white/35"}
									/>
									<span className={hasSelectedSource ? "text-white/80" : "text-white/35"}>
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
