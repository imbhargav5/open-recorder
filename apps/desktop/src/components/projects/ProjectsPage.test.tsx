// @vitest-environment jsdom

import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ProjectListItem } from "@/lib/backend";

vi.mock("@/lib/backend", () => ({
	listProjects: vi.fn(),
	openRecordingsFolder: vi.fn(),
}));

vi.mock("sonner", () => ({
	toast: {
		error: vi.fn(),
	},
}));

const backend = vi.mocked(await import("@/lib/backend"));
const { ProjectsPage } = await import("./ProjectsPage");

function project(overrides: Partial<ProjectListItem> = {}): ProjectListItem {
	return {
		path: "/recordings/Projects/Demo.openrecorder",
		title: "Demo",
		recordingPath: "/recordings/Demo.webm",
		sourceName: "Display 1",
		createdAt: "2026-01-01T00:00:00.000Z",
		updatedAt: "2026-01-01T00:00:00.000Z",
		lastOpenedAt: "2026-01-01T00:00:00.000Z",
		missing: false,
		...overrides,
	};
}

beforeEach(() => {
	vi.clearAllMocks();
	backend.listProjects.mockResolvedValue([]);
	backend.openRecordingsFolder.mockResolvedValue(undefined);
});

afterEach(() => {
	cleanup();
});

describe("ProjectsPage", () => {
	it("renders indexed projects and opens a selected project", async () => {
		const onOpenProject = vi.fn();
		const onOpenProjectPath = vi.fn().mockResolvedValue(undefined);
		backend.listProjects.mockResolvedValue([project()]);

		render(<ProjectsPage onOpenProject={onOpenProject} onOpenProjectPath={onOpenProjectPath} />);

		expect(await screen.findByText("Demo")).toBeInTheDocument();
		expect(screen.getByText("Display 1")).toBeInTheDocument();

		await userEvent.click(screen.getByRole("button", { name: /demo/i }));

		expect(onOpenProjectPath).toHaveBeenCalledWith("/recordings/Projects/Demo.openrecorder");
	});

	it("shows missing projects without opening them", async () => {
		const onOpenProjectPath = vi.fn();
		backend.listProjects.mockResolvedValue([project({ missing: true })]);

		render(<ProjectsPage onOpenProject={vi.fn()} onOpenProjectPath={onOpenProjectPath} />);

		expect(await screen.findByText("Missing")).toBeInTheDocument();
		await waitFor(() => {
			expect(screen.getByRole("button", { name: /demo/i })).toBeDisabled();
		});
		expect(onOpenProjectPath).not.toHaveBeenCalled();
	});
});
