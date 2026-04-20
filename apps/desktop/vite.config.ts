import path from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import electron from "vite-plugin-electron/simple";
import { defineConfig } from "vite";

const rendererOnly = process.env.OPEN_RECORDER_RENDERER_ONLY === "1";

// https://vitejs.dev/config/
export default defineConfig({
	plugins: [
		react(),
		...(
			rendererOnly
				? []
				: [
						electron({
							main: {
								entry: "electron/main.ts",
								// "type": "module" in package.json is auto-detected by the plugin,
								// so the main process is compiled to ESM (formats: ["es"]) automatically.
								vite: {
									build: {
										sourcemap: process.env.NODE_ENV !== "production",
										minify: process.env.NODE_ENV === "production",
									},
								},
							},
							preload: {
								input: path.join(__dirname, "electron/preload.ts"),
								vite: {
									build: {
										sourcemap: process.env.NODE_ENV !== "production",
										minify: process.env.NODE_ENV === "production",
										rollupOptions: {
											output: {
												// The preload runs with sandbox:false / nodeIntegration:false,
												// so Electron requires ESM (require() is not available).
												// Override the plugin's default "cjs" format.
												format: "esm",
												// Keep .js extension so PRELOAD_PATH = "preload.js" in main.ts resolves correctly.
												entryFileNames: "[name].js",
											},
										},
									},
								},
							},
						}),
					]
		),
		tailwindcss(),
	],
	resolve: {
		alias: {
			"@": path.resolve(__dirname, "src"),
		},
	},
	server: {
		port: 5789,
		strictPort: true,
	},
	envPrefix: ["VITE_", "TAURI_ENV_"],
	optimizeDeps: {
		entries: ["index.html"],
		exclude: [
			"lucide-react",
			"react-icons/bs",
			"react-icons/fa",
			"react-icons/fa6",
			"react-icons/fi",
			"react-icons/md",
			"react-icons/rx",
		],
	},
	build: {
		target: ["es2021", "chrome100", "safari14"],
		minify: "terser",
		terserOptions: {
			compress: {
				drop_console: true,
				drop_debugger: true,
				pure_funcs: ["console.log", "console.debug"],
			},
		},
		rollupOptions: {
			output: {
				manualChunks: {
					pixi: ["pixi.js", "pixi.js/unsafe-eval"],
					"react-vendor": ["react", "react-dom"],
					"video-processing": [
						"mediabunny",
						"mp4box",
						"@fix-webm-duration/fix",
						"@fix-webm-duration/parser",
					],
				},
			},
		},
		chunkSizeWarningLimit: 1000,
	},
});
