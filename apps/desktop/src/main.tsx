import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.tsx";
import { I18nProvider } from "./contexts/I18nContext.tsx";
import { ensurePixiRuntime } from "./lib/pixiRuntime.ts";
import "./index.css";

async function bootstrap() {
	document.documentElement.dataset.platform = /mac/i.test(navigator.platform) ? "macos" : "other";

	await ensurePixiRuntime();

	ReactDOM.createRoot(document.getElementById("root")!).render(
		<React.StrictMode>
			<I18nProvider>
				<App />
			</I18nProvider>
		</React.StrictMode>,
	);
}

void bootstrap();
