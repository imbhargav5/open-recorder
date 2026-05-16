#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");
const appcastPath = resolve(repoRoot, "docs", "appcast.xml");

function die(message) {
	console.error(`Error: ${message}`);
	process.exit(1);
}

function parseArgs(argv) {
	const args = {};
	for (let index = 0; index < argv.length; index += 1) {
		const arg = argv[index];
		if (!arg.startsWith("--")) {
			die(`Unexpected positional argument: ${arg}`);
		}
		const key = arg.slice(2);
		const value = argv[++index];
		if (value === undefined) {
			die(`--${key} requires a value`);
		}
		args[key] = value;
	}
	return args;
}

function escapeXml(value) {
	return value
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;");
}

function buildItem({ version, url, signature, length, minSystemVersion, releaseNotes }) {
	const pubDate = new Date().toUTCString();
	const notesBlock = releaseNotes
		? `            <description><![CDATA[\n${releaseNotes}\n]]></description>\n`
		: "";
	return `        <item>
            <title>Version ${escapeXml(version)}</title>
            <pubDate>${pubDate}</pubDate>
            <sparkle:version>${escapeXml(version)}</sparkle:version>
            <sparkle:shortVersionString>${escapeXml(version)}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${escapeXml(minSystemVersion)}</sparkle:minimumSystemVersion>
${notesBlock}            <enclosure url="${escapeXml(url)}" sparkle:edSignature="${escapeXml(signature)}" length="${escapeXml(length)}" type="application/octet-stream"/>
        </item>`;
}

function skeleton(item) {
	return `<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>Open Recorder Changelog</title>
        <link>https://raw.githubusercontent.com/imbhargav5/open-recorder/main/docs/appcast.xml</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
${item}
    </channel>
</rss>
`;
}

const args = parseArgs(process.argv.slice(2));
const required = ["version", "url", "signature", "length", "min-system-version"];
for (const key of required) {
	if (!args[key]) {
		die(`--${key} is required`);
	}
}

const item = buildItem({
	version: args.version,
	url: args.url,
	signature: args.signature,
	length: args.length,
	minSystemVersion: args["min-system-version"],
	releaseNotes: args["release-notes"] || "",
});

mkdirSync(dirname(appcastPath), { recursive: true });

if (!existsSync(appcastPath)) {
	writeFileSync(appcastPath, skeleton(item));
	console.log(`Created ${appcastPath} with entry for ${args.version}`);
	process.exit(0);
}

let content = readFileSync(appcastPath, "utf8");

const versionPattern = new RegExp(
	`\\s*<item>[\\s\\S]*?<sparkle:version>${args.version.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&")}<\\/sparkle:version>[\\s\\S]*?<\\/item>`,
	"g",
);
content = content.replace(versionPattern, "");

if (!content.includes("</channel>")) {
	die("appcast.xml is malformed: missing </channel>");
}

content = content.replace(/(\s*)<\/channel>/, `\n${item}$1</channel>`);
writeFileSync(appcastPath, content);
console.log(`Updated ${appcastPath} with entry for ${args.version}`);
