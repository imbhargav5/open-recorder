export function escapeHtml(value) {
	return String(value).replace(/[&<>"']/g, (char) => ({
		"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
	})[char]);
}

function inline(text) {
	// Only explicit HTTP(S) links become markup. Everything else remains text.
	return text.split(/(\[[^\]\n]+\]\([^\s)]+\))/g).map((part) => {
		const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(part);
		if (link) {
			try {
				const url = new URL(link[2]);
				if (["https:", "http:"].includes(url.protocol)) {
					return `<a href="${escapeHtml(url.href)}">${escapeHtml(link[1])}</a>`;
				}
			} catch { /* Render malformed links as text. */ }
		}
		return escapeHtml(part);
	}).join("");
}

function generatedNotes(notes) {
	const groups = { New: [], Improved: [], Fixed: [] };
	for (const line of notes.split(/\r?\n/)) {
		const match = /^\s*-\s+[a-f0-9]{7,40}\s+(.+)$/i.exec(line);
		if (!match) continue;
		let subject = match[1];
		if (/^(Merge\b|Update appcast\b|(?:chore|ci|build|docs|test)(?:\([^)]*\))?!?:|(?:chore:\s*)?release\b|bump version\b)/i.test(subject)) continue;
		const conventional = /^(\w+)(?:\([^)]*\))?!?:\s*(.+)$/.exec(subject);
		const group = conventional?.[1] === "feat" ? "New" : conventional?.[1] === "fix" ? "Fixed" : "Improved";
		subject = (conventional?.[2] ?? subject).replace(/\s+\(#\d+\)$/, "").trim();
		if (subject && !groups[group].includes(subject)) groups[group].push(subject);
	}
	return Object.entries(groups).filter(([, items]) => items.length).map(([title, items]) =>
		`## ${title}\n\n${items.map((item) => `- ${item[0].toUpperCase()}${item.slice(1)}`).join("\n")}`
	).join("\n\n");
}

function blocks(notes) {
	const result = [];
	let paragraph = [];
	let bullets = [];
	let heading = null;
	const flushHeading = () => {
		if (heading !== null) { result.push(`<h2>${inline(heading)}</h2>`); heading = null; }
	};
	const flush = () => {
		if (paragraph.length) { flushHeading(); result.push(`<p>${inline(paragraph.join(" "))}</p>`); paragraph = []; }
		if (bullets.length) { flushHeading(); result.push(`<ul>${bullets.map((item) => `<li>${inline(item)}</li>`).join("")}</ul>`); bullets = []; }
	};
	for (const line of notes.split(/\r?\n/)) {
		const title = /^#{1,6}\s+(.+)$/.exec(line);
		const bullet = /^\s*[-*+]\s+(.+)$/.exec(line);
		if (title) { flush(); heading = title[1]; }
		else if (bullet) { if (paragraph.length) flush(); bullets.push(bullet[1]); }
		else if (!line.trim()) flush();
		else { if (bullets.length) flush(); paragraph.push(line.trim()); }
	}
	flush();
	return result.join("\n");
}

export function renderReleaseNotes({ version, releaseNotes = "" }) {
	const generated = /^## Commits(?: since [^\n]+)?\s*(?:\n|$)/.test(releaseNotes.trim());
	const content = blocks(generated ? generatedNotes(releaseNotes) : releaseNotes);
	const releaseURL = `https://github.com/imbhargav5/open-recorder/releases/tag/v${encodeURIComponent(version)}`;
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>What’s New · ${escapeHtml(version)}</title>
<style>
:root { color-scheme: light dark; --text: #242426; --muted: #66666e; --line: #e1e1e6; --link: #305dc8; --background: #fff; }
@media (prefers-color-scheme: dark) { :root { --text: #ededf0; --muted: #aaaab3; --line: #414146; --link: #9cbaff; --background: #242426; } }
* { box-sizing: border-box; }
body { margin: 0; padding: 24px; background: var(--background); color: var(--text); font: 13px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; overflow-wrap: anywhere; }
header { margin-bottom: 24px; }
.version { margin: 0 0 4px; color: var(--muted); font-size: 11px; }
h1 { margin: 0; font-size: 24px; line-height: 1.25; font-weight: 650; letter-spacing: -.5px; }
h2 { margin: 22px 0 8px; font-size: 14px; line-height: 1.4; font-weight: 600; }
p { margin: 8px 0; }
ul { padding-left: 18px; margin: 8px 0; }
li { padding-left: 3px; margin: 6px 0; }
li::marker { color: var(--muted); }
a:any-link { color: var(--link); text-underline-offset: 3px; }
a:focus-visible { outline: 2px solid var(--link); outline-offset: 3px; }
footer { margin-top: 24px; padding-top: 14px; border-top: 1px solid var(--line); font-size: 12px; }
</style>
</head>
<body>
<header><p class="version">Version ${escapeHtml(version)}</p><h1>What’s New</h1></header>
<main>${content || "<p>See full release details for this update.</p>"}</main>
<footer><a href="${escapeHtml(releaseURL)}">Full release details</a></footer>
</body>
</html>`;
}

export function releaseNotesDescription(options) {
	return `<description><![CDATA[\n${renderReleaseNotes(options).replace(/\]\]>/g, "]]]]><![CDATA[>")}\n]]></description>`;
}
