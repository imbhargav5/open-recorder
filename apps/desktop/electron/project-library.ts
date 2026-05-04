import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const PROJECTS_DIR_NAME = "Projects";
const PROJECT_EXTENSION = ".openrecorder";

export interface ProjectMetadata {
	title: string;
	recordingPath: string | null;
	sourceName: string | null;
}

export interface ProjectListItem extends ProjectMetadata {
	path: string;
	createdAt: string;
	updatedAt: string;
	lastOpenedAt: string;
	missing: boolean;
}

interface ProjectRow {
	path: string;
	title: string;
	recording_path: string | null;
	source_name: string | null;
	created_at: string;
	updated_at: string;
	last_opened_at: string;
	missing: 0 | 1;
}

export function getProjectsDir(recordingsDir: string): string {
	return path.join(recordingsDir, PROJECTS_DIR_NAME);
}

export function sanitizeProjectFileBaseName(name: string | undefined | null): string {
	const sanitized = (name?.trim() || "Untitled")
		.replace(/[<>:"/\\|?*]/g, " ")
		.split("")
		.map((char) => (char.charCodeAt(0) < 32 ? " " : char))
		.join("")
		.replace(/\s+/g, " ")
		.trim()
		.replace(/[. ]+$/g, "");

	return sanitized || "Untitled";
}

export async function resolveAutomaticProjectPath(
	recordingsDir: string,
	suggestedName?: string,
): Promise<string> {
	const projectsDir = getProjectsDir(recordingsDir);
	await fs.promises.mkdir(projectsDir, { recursive: true });

	const parsed = path.parse(suggestedName ?? "Untitled");
	const baseName = sanitizeProjectFileBaseName(parsed.name || suggestedName);
	const firstPath = path.join(projectsDir, `${baseName}${PROJECT_EXTENSION}`);
	if (!fs.existsSync(firstPath)) return firstPath;

	for (let index = 2; index < Number.MAX_SAFE_INTEGER; index += 1) {
		const candidate = path.join(projectsDir, `${baseName} ${index}${PROJECT_EXTENSION}`);
		if (!fs.existsSync(candidate)) return candidate;
	}

	throw new Error("Unable to resolve a unique project file path");
}

export function deriveProjectMetadata(data: unknown, filePath: string): ProjectMetadata {
	const record = data && typeof data === "object" ? (data as Record<string, unknown>) : {};
	const title = sanitizeProjectFileBaseName(path.parse(filePath).name);
	const recordingPath =
		typeof record.videoPath === "string" && record.videoPath ? record.videoPath : null;
	const sourceName =
		typeof record.sourceName === "string" && record.sourceName.trim() ? record.sourceName : null;

	return {
		title,
		recordingPath,
		sourceName,
	};
}

export class ProjectLibrary {
	private db: DatabaseSync;

	constructor(configDir: string) {
		fs.mkdirSync(configDir, { recursive: true });
		this.db = new DatabaseSync(path.join(configDir, "projects.sqlite"));
		this.db.exec(`
			CREATE TABLE IF NOT EXISTS projects (
				path TEXT PRIMARY KEY,
				title TEXT NOT NULL,
				recording_path TEXT,
				source_name TEXT,
				created_at TEXT NOT NULL,
				updated_at TEXT NOT NULL,
				last_opened_at TEXT NOT NULL,
				missing INTEGER NOT NULL DEFAULT 0
			)
		`);
	}

	upsertProject(filePath: string, metadata: ProjectMetadata, now = new Date()): ProjectListItem {
		const timestamp = now.toISOString();
		this.db
			.prepare(`
				INSERT INTO projects (
					path,
					title,
					recording_path,
					source_name,
					created_at,
					updated_at,
					last_opened_at,
					missing
				)
				VALUES (?, ?, ?, ?, ?, ?, ?, 0)
				ON CONFLICT(path) DO UPDATE SET
					title = excluded.title,
					recording_path = excluded.recording_path,
					source_name = excluded.source_name,
					updated_at = excluded.updated_at,
					last_opened_at = excluded.last_opened_at,
					missing = 0
			`)
			.run(
				filePath,
				metadata.title,
				metadata.recordingPath,
				metadata.sourceName,
				timestamp,
				timestamp,
				timestamp,
			);

		const row = this.getProjectRow(filePath);
		if (!row) throw new Error("Failed to read indexed project after upsert");
		return mapProjectRow(row);
	}

	markOpened(filePath: string, metadata: ProjectMetadata, now = new Date()): ProjectListItem {
		const timestamp = now.toISOString();
		this.db
			.prepare(`
				INSERT INTO projects (
					path,
					title,
					recording_path,
					source_name,
					created_at,
					updated_at,
					last_opened_at,
					missing
				)
				VALUES (?, ?, ?, ?, ?, ?, ?, 0)
				ON CONFLICT(path) DO UPDATE SET
					title = excluded.title,
					recording_path = excluded.recording_path,
					source_name = excluded.source_name,
					last_opened_at = excluded.last_opened_at,
					missing = 0
			`)
			.run(
				filePath,
				metadata.title,
				metadata.recordingPath,
				metadata.sourceName,
				timestamp,
				timestamp,
				timestamp,
			);

		const row = this.getProjectRow(filePath);
		if (!row) throw new Error("Failed to read indexed project after open");
		return mapProjectRow(row);
	}

	listProjects(): ProjectListItem[] {
		const rows = this.db
			.prepare(`
				SELECT path, title, recording_path, source_name, created_at, updated_at, last_opened_at, missing
				FROM projects
				ORDER BY last_opened_at DESC, updated_at DESC
			`)
			.all() as ProjectRow[];

		for (const row of rows) {
			if (!fs.existsSync(row.path) && row.missing === 0) {
				this.db.prepare("UPDATE projects SET missing = 1 WHERE path = ?").run(row.path);
				row.missing = 1;
			}
		}

		return rows.map(mapProjectRow);
	}

	removeProject(filePath: string): void {
		this.db.prepare("DELETE FROM projects WHERE path = ?").run(filePath);
	}

	close(): void {
		this.db.close();
	}

	private getProjectRow(filePath: string): ProjectRow | null {
		return (
			(this.db
				.prepare(`
					SELECT path, title, recording_path, source_name, created_at, updated_at, last_opened_at, missing
					FROM projects
					WHERE path = ?
				`)
				.get(filePath) as ProjectRow | undefined) ?? null
		);
	}
}

function mapProjectRow(row: ProjectRow): ProjectListItem {
	return {
		path: row.path,
		title: row.title,
		recordingPath: row.recording_path,
		sourceName: row.source_name,
		createdAt: row.created_at,
		updatedAt: row.updated_at,
		lastOpenedAt: row.last_opened_at,
		missing: row.missing === 1,
	};
}
