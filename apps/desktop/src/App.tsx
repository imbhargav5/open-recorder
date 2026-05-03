import { useAtom } from "jotai";
import { type ReactElement, useEffect } from "react";
import { invoke } from "@/lib/electronBridge";
import { appNameAtom, windowTypeAtom } from "./atoms/app";
import { AppUpdaterDialog } from "./components/AppUpdaterDialog";
import ImageEditor from "./components/image-editor/ImageEditor";
import { LaunchWindow } from "./components/launch/LaunchWindow";
import { SourceSelector } from "./components/launch/SourceSelector";
import { TooltipProvider } from "./components/ui/tooltip";
import { ShortcutsConfigDialog } from "./components/video-editor/ShortcutsConfigDialog";
import VideoEditor from "./components/video-editor/VideoEditor";
import { useI18n } from "./contexts/I18nContext";
import { ShortcutsProvider } from "./contexts/ShortcutsContext";
import { loadAllCustomFonts } from "./lib/customFonts";

export default function App() {
	const [windowType, setWindowType] = useAtom(windowTypeAtom);
	const [appName, setAppName] = useAtom(appNameAtom);
	const { t } = useI18n();

	useEffect(() => {
		const params = new URLSearchParams(window.location.search);
		const type = params.get("windowType") || "";
		setWindowType(type);

		if (type === "hud-overlay" || type === "source-selector") {
			document.body.style.background = "transparent";
			document.documentElement.style.background = "transparent";
			document.getElementById("root")?.style.setProperty("background", "transparent");
		}
		document.documentElement.classList.toggle(
			"dark",
			type === "hud-overlay" ||
				type === "source-selector" ||
				type === "editor" ||
				type === "image-editor",
		);

		// Load custom fonts on app initialization
		loadAllCustomFonts().catch((error) => {
			console.warn(
				"Some custom fonts failed to load — text appearance may differ from expected.",
				error,
			);
		});

		invoke<string>("get_app_name")
			.then(setAppName)
			.catch(() => {
				setAppName("Open Recorder");
			});
	}, [setWindowType, setAppName]);

	useEffect(() => {
		document.title = windowType === "editor" ? `${appName} Editor` : appName;
	}, [appName, windowType]);

	let content: ReactElement;

	switch (windowType) {
		case "hud-overlay":
			content = <LaunchWindow />;
			break;
		case "source-selector":
			content = <SourceSelector />;
			break;
		case "editor":
			content = (
				<ShortcutsProvider>
					<VideoEditor />
					<ShortcutsConfigDialog />
				</ShortcutsProvider>
			);
			break;
		case "image-editor":
			content = <ImageEditor />;
			break;
		default:
			content = (
				<div className="flex h-full w-full items-center justify-center bg-slate-950 text-white">
					<div className="flex items-center gap-4 rounded-2xl border border-white/10 bg-white/5 px-6 py-5 shadow-2xl shadow-black/30 backdrop-blur-xl">
						<img
							src="/app-icons/open-recorder-128.png"
							alt={appName}
							className="h-12 w-12 rounded-xl"
						/>
						<div>
							<h1 className="text-xl font-semibold tracking-tight">{appName}</h1>
							<p className="text-sm text-white/65">
								{t("app.subtitle", "Screen recording and editing")}
							</p>
						</div>
					</div>
				</div>
			);
			break;
	}

	const shouldRenderUpdater =
		windowType === "editor" || windowType === "image-editor" || windowType === "";

	return (
		<TooltipProvider delayDuration={350}>
			{content}
			{shouldRenderUpdater ? (
				<AppUpdaterDialog enableAutoCheck={windowType !== "image-editor"} />
			) : null}
		</TooltipProvider>
	);
}
