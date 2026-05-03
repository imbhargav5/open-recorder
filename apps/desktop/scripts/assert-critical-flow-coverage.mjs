import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, "..");

const requiredScenarios = [
	{
		flow: "screen recording",
		platform: "macOS",
		file: "e2e/flows/recording-lifecycle.spec.ts",
		title: "macOS native screen recording starts and stops from the HUD UI",
	},
	{
		flow: "screen recording",
		platform: "Windows",
		file: "e2e/flows/recording-lifecycle.spec.ts",
		title: "Windows Chromium screen recording starts and stops from the HUD UI",
	},
	{
		flow: "screenshot",
		platform: "macOS",
		file: "e2e/flows/screenshot-flow.spec.ts",
		title: "macOS screen screenshot capture uses the HUD UI",
	},
	{
		flow: "screenshot",
		platform: "macOS",
		file: "e2e/flows/screenshot-flow.spec.ts",
		title: "macOS window screenshot capture sends the selected window id",
	},
	{
		flow: "screenshot",
		platform: "macOS",
		file: "e2e/flows/screenshot-flow.spec.ts",
		title: "macOS area screenshot capture runs immediately",
	},
	{
		flow: "screenshot",
		platform: "Windows",
		file: "e2e/flows/screenshot-flow.spec.ts",
		title: "Windows screen screenshot capture uses the HUD UI",
	},
	{
		flow: "screenshot",
		platform: "Windows",
		file: "e2e/flows/screenshot-flow.spec.ts",
		title: "Windows window screenshot capture sends the selected window id",
	},
	{
		flow: "screenshot",
		platform: "Windows",
		file: "e2e/flows/screenshot-flow.spec.ts",
		title: "Windows area screenshot capture runs immediately",
	},
];

const minimumCoverage = 90;
const byFile = new Map();

for (const scenario of requiredScenarios) {
	if (!byFile.has(scenario.file)) {
		byFile.set(scenario.file, fs.readFileSync(path.join(appRoot, scenario.file), "utf8"));
	}
}

const results = new Map();
const missing = [];

function scenarioIsCovered(source, scenario) {
	if (source.includes(scenario.title)) {
		return true;
	}

	const platformlessTitle = scenario.title.replace(`${scenario.platform} `, "");
	const loopTitle = `\${label} ${platformlessTitle}`;
	return source.includes(`label: "${scenario.platform}"`) && source.includes(loopTitle);
}

for (const scenario of requiredScenarios) {
	const source = byFile.get(scenario.file);
	const key = `${scenario.flow} on ${scenario.platform}`;
	const current = results.get(key) ?? { covered: 0, total: 0 };
	current.total += 1;

	if (scenarioIsCovered(source, scenario)) {
		current.covered += 1;
	} else {
		missing.push(scenario);
	}

	results.set(key, current);
}

let failed = false;

for (const [key, result] of results.entries()) {
	const percent = Math.round((result.covered / result.total) * 100);
	console.log(`${key}: ${percent}% (${result.covered}/${result.total})`);
	if (percent < minimumCoverage) {
		failed = true;
	}
}

if (missing.length > 0) {
	console.error("\nMissing required critical-flow tests:");
	for (const scenario of missing) {
		console.error(`- ${scenario.platform} ${scenario.flow}: ${scenario.title}`);
	}
}

if (failed) {
	console.error(
		`\nCritical screen recording and screenshot flow coverage must be at least ${minimumCoverage}% for macOS and Windows.`,
	);
	process.exit(1);
}
