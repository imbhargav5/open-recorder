/**
 * First-launch permission onboarding overlay.
 *
 * Guides the user through granting all required (and optional) permissions
 * in a step-by-step flow. Designed to fit within the HUD overlay window after
 * a brief resize so the user gets a clear, focused permission-granting experience.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { HiShieldCheck } from "react-icons/hi2";
import { MdCheck, MdClose, MdMic, MdRefresh, MdScreenShare, MdVideocam } from "react-icons/md";
import * as backend from "@/lib/backend";
import { invoke } from "@/lib/electronBridge";
import type {
	PermissionState,
	PermissionStatus,
	UsePermissionsResult,
} from "../../hooks/usePermissions";
import { Button } from "../ui/button";
import { Card } from "../ui/card";

const ONBOARDING_COMPLETE_KEY = "open-recorder-onboarding-v1";

type OnboardingStep = "welcome" | "screen_recording" | "microphone" | "camera" | "done";

interface PermissionOnboardingProps {
	permissionsHook: UsePermissionsResult;
	onComplete: () => void;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function statusIcon(status: PermissionStatus) {
	if (status === "granted") {
		return <MdCheck size={16} className="text-emerald-400" />;
	}
	if (status === "denied" || status === "restricted") {
		return <MdClose size={16} className="text-red-400" />;
	}
	return <div className="h-3 w-3 rounded-full border-2 border-white/20" />;
}

function statusLabel(status: PermissionStatus): string {
	switch (status) {
		case "granted":
			return "Granted";
		case "denied":
			return "Denied";
		case "restricted":
			return "Restricted";
		case "not_determined":
			return "Not set";
		case "checking":
			return "Checking...";
		default:
			return "Unknown";
	}
}

// ─── Step Indicator ──────────────────────────────────────────────────────────

function StepDots({ steps, currentIndex }: { steps: OnboardingStep[]; currentIndex: number }) {
	return (
		<div className="flex items-center gap-1.5">
			{steps.map((_, i) => (
				<div
					key={i}
					className={`h-1.5 rounded-full transition-all duration-300 ${
						i === currentIndex
							? "w-5 bg-blue-400"
							: i < currentIndex
								? "w-1.5 bg-blue-400/50"
								: "w-1.5 bg-white/20"
					}`}
				/>
			))}
		</div>
	);
}

// ─── Main Component ──────────────────────────────────────────────────────────

export function PermissionOnboarding({ permissionsHook, onComplete }: PermissionOnboardingProps) {
	const {
		permissions,
		isMacOS,
		refreshPermissions,
		requestMicrophoneAccess,
		requestCameraAccess,
		requestScreenRecordingAccess,
		openPermissionSettings,
	} = permissionsHook;

	const [step, setStep] = useState<OnboardingStep>("welcome");
	const [isRequesting, setIsRequesting] = useState(false);
	// Screen-recording needs a relaunch before macOS picks up a new grant in
	// the running process (the TCC status is cached per-process).  When the
	// user has gone through "Grant Permission → open Settings" at least once,
	// surface a "Quit & Relaunch" affordance instead of pretending the 500ms
	// refetch will work.
	const [screenRecordingAwaitingRelaunch, setScreenRecordingAwaitingRelaunch] = useState(false);
	const resizedRef = useRef(false);

	// Build the step list — skip macOS-only steps on other platforms
	const steps: OnboardingStep[] = isMacOS
		? ["welcome", "screen_recording", "microphone", "camera", "done"]
		: ["welcome", "microphone", "camera", "done"];
	const currentIndex = steps.indexOf(step);

	// Resize the HUD window when onboarding appears
	useEffect(() => {
		if (resizedRef.current) return;
		resizedRef.current = true;

		invoke("resize_hud_to_onboarding").catch((err) => {
			console.error(
				"[PermissionOnboarding] window resize failed, continuing with current size:",
				err,
			);
		});
	}, []);

	// Restore the HUD window to its normal size and re-position to bottom-center
	const restoreWindowSize = useCallback(async () => {
		await invoke("restore_hud_size");
	}, []);

	const handleComplete = useCallback(async () => {
		try {
			localStorage.setItem(ONBOARDING_COMPLETE_KEY, "true");
		} catch {
			// localStorage may be unavailable in some contexts
		}
		await restoreWindowSize();
		onComplete();
	}, [onComplete, restoreWindowSize]);

	const advanceStep = useCallback(() => {
		const nextIndex = currentIndex + 1;
		if (nextIndex < steps.length) {
			setStep(steps[nextIndex]);
		}
	}, [currentIndex, steps]);

	const handleGrantPermission = useCallback(async () => {
		setIsRequesting(true);
		try {
			switch (step) {
				case "screen_recording": {
					const granted = await requestScreenRecordingAccess();
					if (!granted) {
						await openPermissionSettings("screenRecording");
					}
					// Regardless of the immediate result: macOS caches the TCC
					// answer per-process on the screen-recording pathway, so
					// the `granted` return above is only reliable if the user
					// had already flipped the toggle before clicking.  Flag the
					// UI so it can offer an explicit "Quit & Relaunch" button
					// instead of silently waiting for a refresh that macOS
					// refuses to serve.
					setScreenRecordingAwaitingRelaunch(true);
					break;
				}
				case "microphone": {
					const granted = await requestMicrophoneAccess();
					if (!granted) {
						await openPermissionSettings("microphone");
					}
					break;
				}
				case "camera": {
					const granted = await requestCameraAccess();
					if (!granted) {
						await openPermissionSettings("camera");
					}
					break;
				}
			}
			await refreshPermissions();
		} finally {
			setIsRequesting(false);
		}
	}, [
		step,
		requestScreenRecordingAccess,
		requestMicrophoneAccess,
		requestCameraAccess,
		openPermissionSettings,
		refreshPermissions,
	]);

	const handleRelaunchApp = useCallback(async () => {
		setIsRequesting(true);
		try {
			await backend.relaunchApp();
		} catch (err) {
			console.error("[PermissionOnboarding] relaunchApp failed:", err);
			setIsRequesting(false);
		}
		// Normal path: the app restarts before we get here — no need to reset
		// isRequesting on success.
	}, []);

	// Once the OS reports screen recording is actually granted, drop the
	// "awaiting relaunch" banner automatically so the user can keep moving
	// without restarting.  This triggers when the focus-refresh picks up a
	// granted status via the desktopCapturer probe.
	useEffect(() => {
		if (permissions.screenRecording === "granted" && screenRecordingAwaitingRelaunch) {
			setScreenRecordingAwaitingRelaunch(false);
		}
	}, [permissions.screenRecording, screenRecordingAwaitingRelaunch]);

	// ─── Step Content ────────────────────────────────────────────────────────

	const renderStepContent = () => {
		switch (step) {
			case "welcome":
				return (
					<div className="flex flex-col items-center gap-4 text-center">
						<div className="flex h-14 w-14 items-center justify-center rounded-2xl border border-blue-400/20 bg-blue-500/15">
							<HiShieldCheck size={28} className="text-blue-400" />
						</div>
						<div>
							<h2 className="text-base font-semibold text-white">Welcome to Open Recorder</h2>
							<p className="mt-1.5 max-w-[320px] text-xs leading-relaxed text-white/55">
								We need a few permissions to capture your screen, microphone, and camera.
								{isMacOS
									? " macOS will ask you to approve each one."
									: " Your system may prompt you when using these features."}
							</p>
						</div>
						<Button
							onClick={advanceStep}
							className="mt-1 rounded-full bg-blue-500 px-6 text-sm font-medium text-white hover:bg-blue-400"
						>
							Get Started
						</Button>
					</div>
				);

			case "screen_recording":
				return renderPermissionStep(
					<MdScreenShare size={24} className="text-blue-400" />,
					"Screen Recording",
					"Required to capture your screen during recordings.",
					permissions.screenRecording,
					"screenRecording",
					true,
					screenRecordingAwaitingRelaunch && permissions.screenRecording !== "granted",
				);

			case "microphone":
				return renderPermissionStep(
					<MdMic size={24} className="text-blue-400" />,
					"Microphone",
					"Record audio commentary during screen recordings.",
					permissions.microphone,
					"microphone",
					false,
				);

			case "camera":
				return renderPermissionStep(
					<MdVideocam size={24} className="text-blue-400" />,
					"Camera",
					"Show your facecam overlay during recordings.",
					permissions.camera,
					"camera",
					false,
				);

			case "done":
				return (
					<div className="flex flex-col items-center gap-4 text-center">
						<div className="flex h-14 w-14 items-center justify-center rounded-2xl border border-emerald-400/20 bg-emerald-500/15">
							<MdCheck size={28} className="text-emerald-400" />
						</div>
						<div>
							<h2 className="text-base font-semibold text-white">You're All Set!</h2>
							<p className="mt-1.5 max-w-[320px] text-xs leading-relaxed text-white/55">
								Open Recorder is ready to go. You can change permissions anytime in System Settings.
							</p>
						</div>
						<PermissionSummary permissions={permissions} />
						<Button
							onClick={() => void handleComplete()}
							className="mt-1 rounded-full bg-blue-500 px-6 text-sm font-medium text-white hover:bg-blue-400"
						>
							Start Recording
						</Button>
					</div>
				);
		}
	};

	const renderPermissionStep = (
		icon: React.ReactNode,
		title: string,
		description: string,
		status: PermissionStatus,
		_permKey: keyof PermissionState,
		required: boolean,
		showRelaunchHint = false,
	) => {
		const isGranted = status === "granted";
		const isDenied = status === "denied" || status === "restricted";

		return (
			<div className="flex flex-col items-center gap-4 text-center">
				<div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/5 border border-white/10">
					{icon}
				</div>
				<div>
					<div className="flex items-center justify-center gap-2">
						<h2 className="text-base font-semibold text-white">{title}</h2>
						{required && (
							<span className="text-[9px] uppercase tracking-wider font-semibold text-amber-400/80 bg-amber-400/10 px-1.5 py-0.5 rounded">
								Required
							</span>
						)}
					</div>
					<p className="mt-1.5 text-xs text-white/55 leading-relaxed max-w-[320px]">
						{description}
					</p>
				</div>

				<div className="flex items-center gap-2 text-xs">
					{statusIcon(status)}
					<span
						className={isGranted ? "text-emerald-400" : isDenied ? "text-red-400" : "text-white/50"}
					>
						{statusLabel(status)}
					</span>
				</div>

				{showRelaunchHint && (
					<p className="text-[11px] leading-relaxed text-amber-300/80 bg-amber-400/10 border border-amber-400/20 rounded-lg px-3 py-2 max-w-[320px]">
						After enabling Screen Recording in System Settings, macOS needs Open Recorder to restart
						before it picks up the new permission. Click{" "}
						<span className="font-semibold">Quit & Relaunch</span> once you&rsquo;ve toggled the
						switch.
					</p>
				)}

				<div className="flex items-center gap-3">
					{isGranted ? (
						<Button
							onClick={advanceStep}
							className="rounded-full bg-blue-500 px-5 text-sm font-medium text-white hover:bg-blue-400"
						>
							Continue
						</Button>
					) : (
						<>
							<Button
								onClick={() => void handleGrantPermission()}
								disabled={isRequesting}
								className="rounded-full bg-blue-500 px-5 text-sm font-medium text-white hover:bg-blue-400"
							>
								{isRequesting ? (
									<span className="flex items-center gap-2">
										<div className="h-3 w-3 animate-spin rounded-full border-2 border-white/30 border-t-white" />
										Requesting...
									</span>
								) : isDenied || showRelaunchHint ? (
									"Open Settings"
								) : (
									"Grant Permission"
								)}
							</Button>
							{showRelaunchHint && (
								<Button
									onClick={() => void handleRelaunchApp()}
									disabled={isRequesting}
									className="gap-1.5 rounded-full bg-emerald-500 px-4 text-sm font-medium text-white hover:bg-emerald-400"
								>
									<MdRefresh size={16} />
									Quit & Relaunch
								</Button>
							)}
							{!required && !showRelaunchHint && (
								<Button
									variant="ghost"
									onClick={advanceStep}
									className="rounded-full px-4 text-sm text-white/50 hover:bg-transparent hover:text-white/80"
								>
									Skip
								</Button>
							)}
						</>
					)}
				</div>
			</div>
		);
	};

	return (
		<div className="flex h-full w-full items-center justify-center">
			<Card className="hud-surface flex w-full max-w-[440px] flex-col items-center gap-5 rounded-[22px] px-6 py-6">
				{renderStepContent()}
				<StepDots steps={steps} currentIndex={currentIndex} />
			</Card>
		</div>
	);
}

// ─── Permission Summary (shown on final step) ───────────────────────────────

function PermissionSummary({ permissions }: { permissions: PermissionState }) {
	const items: { label: string; status: PermissionStatus }[] = [
		{ label: "Screen", status: permissions.screenRecording },
		{ label: "Mic", status: permissions.microphone },
		{ label: "Camera", status: permissions.camera },
		{ label: "Accessibility", status: permissions.accessibility },
	];

	return (
		<div className="flex items-center gap-3 text-[10px]">
			{items.map((item) => (
				<div key={item.label} className="flex items-center gap-1">
					{statusIcon(item.status)}
					<span className="text-white/50">{item.label}</span>
				</div>
			))}
		</div>
	);
}

// ─── Utilities ───────────────────────────────────────────────────────────────

export function isOnboardingComplete(): boolean {
	try {
		return localStorage.getItem(ONBOARDING_COMPLETE_KEY) === "true";
	} catch {
		return false;
	}
}

export function resetOnboarding(): void {
	try {
		localStorage.removeItem(ONBOARDING_COMPLETE_KEY);
	} catch {
		// ignore
	}
}
