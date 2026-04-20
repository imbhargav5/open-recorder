import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Provider, createStore } from "jotai";
import App from "./App.tsx";
import { I18nProvider } from "./contexts/I18nContext.tsx";
import { ensurePixiRuntime } from "./lib/pixiRuntime.ts";
import "./index.css";

async function bootstrap() {
	document.documentElement.dataset.platform = /mac/i.test(navigator.platform) ? "macos" : "other";

	await ensurePixiRuntime();

	const store = createStore();

	createRoot(document.getElementById("root")!).render(
		<StrictMode>
			<Provider store={store}>
				<I18nProvider>
					<App />
				</I18nProvider>
			</Provider>
		</StrictMode>,
	);
}

void bootstrap();
