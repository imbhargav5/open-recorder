import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, copyFileSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { renderReleaseNotes, releaseNotesDescription } from "./render-release-notes.mjs";

test("generated commits become grouped notes without release noise", () => {
	const html = renderReleaseNotes({ version: "1.2.3", releaseNotes: `## Commits since v1.2.2
- abc1234 Merge pull request #12
- abc1235 feat(macos): record shortcuts (#12)
- abc1236 fix: preserve selection
- abc1237 perf: reduce export allocations
- abc1238 docs: update instructions
- abc1239 Update appcast for v1.2.2
- abc1240 feat(macos): record shortcuts (#12)` });
	assert.match(html, /<h2>New<\/h2>/);
	assert.match(html, /<h2>Improved<\/h2>/);
	assert.match(html, /<h2>Fixed<\/h2>/);
	assert.equal(html.split("Record shortcuts").length, 2);
	assert.doesNotMatch(html, /abc123|Merge pull|appcast|feat\(macos\)|update instructions/);
});

test("supplied copy, links and paragraphs are escaped and empty sections omitted", () => {
	const html = renderReleaseNotes({ version: '1<&"', releaseNotes: '## New\n\nYour wording stays.\n\n- <script>alert(1)</script> & ]]>\n- [Guide](https://example.com/?a=1&b=2)\n- [Bad](javascript:alert)\n\n## Fixed' });
	assert.match(html, /Your wording stays\./);
	assert.match(html, /&lt;script&gt;/);
	assert.match(html, /href="https:\/\/example.com\/\?a=1&amp;b=2"/);
	assert.doesNotMatch(html, /<script>|href="javascript:|<h2>Fixed/);
	assert.match(html, /\]\]&gt;/);
	assert.match(releaseNotesDescription({ version: "1", releaseNotes: "]]>" }), /^<description><!\[CDATA\[/);
});

test("empty and long notes remain useful", () => {
	for (const releaseNotes of ["", "## Commits\n\n- abc1234 ci: update workflow", "## New"]) {
		const html = renderReleaseNotes({ version: "1", releaseNotes });
		assert.match(html, /See full release details for this update/);
		assert.doesNotMatch(html, /<h2>/);
	}
	const html = renderReleaseNotes({ version: "1", releaseNotes: Array.from({ length: 100 }, (_, i) => `- Change ${i}`).join("\n") });
	assert.equal((html.match(/<li>/g) || []).length, 100);
	assert.match(html, /prefers-color-scheme: dark/);
});

test("CLI replacement preserves every unrelated release and enclosure metadata", () => {
	const root = mkdtempSync(join(tmpdir(), "release-notes-test-"));
	try {
		mkdirSync(join(root, "scripts")); mkdirSync(join(root, "docs"));
		for (const name of ["update-production-appcast.mjs", "render-release-notes.mjs"]) copyFileSync(new URL(name, import.meta.url), join(root, "scripts", name));
		const original = readFileSync(new URL("../docs/appcast.xml", import.meta.url), "utf8");
		const items = original.match(/<item>[\s\S]*?<\/item>/g);
		const target = items.at(-1);
		const version = /<sparkle:version>(.*?)<\/sparkle:version>/.exec(target)[1];
		const enclosure = /<enclosure[^>]+\/>/.exec(target)[0];
		const attr = (name) => new RegExp(`${name}="([^"]+)"`).exec(enclosure)[1];
		writeFileSync(join(root, "docs/appcast.xml"), original);
		const args = [join(root, "scripts/update-production-appcast.mjs"), "--version", version, "--url", attr("url"), "--signature", attr("sparkle:edSignature"), "--length", attr("length"), "--min-system-version", "15.0", "--release-notes", "## Fixed\n\n- A & B"];
		for (let run = 0; run < 2; run++) {
			execFileSync(process.execPath, args);
			const output = readFileSync(join(root, "docs/appcast.xml"), "utf8");
			const updated = output.match(/<item>[\s\S]*?<\/item>/g);
			assert.equal(updated.length, items.length);
			assert.deepEqual(updated.slice(0, -1), items.slice(0, -1));
			assert.ok(updated.at(-1).includes(enclosure));
			assert.match(updated.at(-1), /A &amp; B/);
		}
	} finally { rmSync(root, { recursive: true, force: true }); }
});
