import { useAtom } from "jotai";
import { FolderGit2, Video } from "lucide-react";
import { type InternalView, internalViewAtom, sidebarExpandedAtom } from "@/atoms/navigation";
import { cn } from "@/lib/utils";

type NavItem = {
	view: InternalView;
	label: string;
	icon: typeof Video;
};

const NAV_ITEMS: readonly NavItem[] = [
	{ view: "editor", label: "Editor", icon: Video },
	{ view: "projects", label: "Projects", icon: FolderGit2 },
];

export function AppSidebar() {
	const [expanded] = useAtom(sidebarExpandedAtom);
	const [activeView, setActiveView] = useAtom(internalViewAtom);

	return (
		<aside
			data-testid="app-sidebar"
			aria-label="Primary navigation"
			className={cn(
				"flex-shrink-0 h-full bg-[#09090b] border-r border-white/5 flex flex-col py-3 transition-[width] duration-200 ease-out overflow-hidden",
				expanded ? "w-52" : "w-12",
			)}
		>
			<nav className="flex flex-col gap-1 px-2 mt-2">
				{NAV_ITEMS.map(({ view, label, icon: Icon }) => {
					const isActive = activeView === view;
					return (
						<button
							key={view}
							type="button"
							onClick={() => setActiveView(view)}
							title={expanded ? undefined : label}
							aria-label={label}
							aria-current={isActive ? "page" : undefined}
							className={cn(
								"group flex items-center gap-3 rounded-md h-8 px-2 text-xs font-medium transition-colors cursor-pointer",
								isActive
									? "bg-white/10 text-white"
									: "text-white/60 hover:bg-white/5 hover:text-white",
							)}
						>
							<Icon className="h-4 w-4 flex-shrink-0" />
							<span
								className={cn(
									"truncate transition-opacity duration-150",
									expanded ? "opacity-100" : "opacity-0 pointer-events-none",
								)}
							>
								{label}
							</span>
						</button>
					);
				})}
			</nav>
		</aside>
	);
}
