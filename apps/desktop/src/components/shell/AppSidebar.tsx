import { useAtom, useSetAtom } from "jotai";
import { FolderGit2, HelpCircle, Video } from "lucide-react";
import { type InternalView, internalViewAtom, sidebarExpandedAtom } from "@/atoms/navigation";
import { showShortcutsDialogAtom } from "@/atoms/videoEditor";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
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
	const setShowShortcutsDialog = useSetAtom(showShortcutsDialogAtom);

	const renderNavButton = ({
		label,
		icon: Icon,
		isActive,
		onClick,
	}: {
		label: string;
		icon: typeof Video;
		isActive?: boolean;
		onClick: () => void;
	}) => {
		const button = (
			<Button
				type="button"
				variant={isActive ? "secondary" : "ghost"}
				size={expanded ? "sm" : "icon"}
				onClick={onClick}
				aria-label={label}
				aria-current={isActive ? "page" : undefined}
				className={cn(
					"h-9 justify-start rounded-lg text-xs",
					expanded ? "w-full px-2.5" : "size-9 px-0",
					isActive
						? "bg-primary/15 text-primary hover:bg-primary/20"
						: "text-muted-foreground hover:bg-muted/70 hover:text-foreground",
				)}
			>
				<Icon data-icon="inline-start" />
				<span className={cn("truncate", !expanded && "sr-only")}>{label}</span>
			</Button>
		);

		if (expanded) {
			return button;
		}

		return (
			<Tooltip>
				<TooltipTrigger asChild>{button}</TooltipTrigger>
				<TooltipContent side="right">{label}</TooltipContent>
			</Tooltip>
		);
	};

	return (
		<aside
			data-testid="app-sidebar"
			aria-label="Primary navigation"
			className={cn(
				"flex h-full flex-shrink-0 flex-col overflow-hidden border-r border-border/60 bg-card/95 py-3 shadow-xl shadow-black/20 transition-[width] duration-200 ease-out",
				expanded ? "w-56" : "w-14",
			)}
		>
			<div className="flex items-center gap-2 px-2.5">
				<div className="flex size-9 flex-shrink-0 items-center justify-center rounded-lg border border-primary/20 bg-primary/10 text-primary">
					<Video className="size-4" />
				</div>
				<div
					className={cn(
						"min-w-0 transition-opacity duration-150",
						expanded ? "opacity-100" : "pointer-events-none opacity-0",
					)}
				>
					<div className="truncate text-sm font-semibold text-foreground">Open Recorder</div>
					<Badge variant="secondary" className="mt-1 text-[10px]">
						Studio
					</Badge>
				</div>
			</div>

			<Separator className="my-3 bg-border/70" />

			<nav className="flex flex-col gap-1 px-2">
				{NAV_ITEMS.map(({ view, label, icon: Icon }) => {
					const isActive = activeView === view;
					return (
						<div key={view}>
							{renderNavButton({
								label,
								icon: Icon,
								isActive,
								onClick: () => setActiveView(view),
							})}
						</div>
					);
				})}
			</nav>

			<div className="mt-auto px-2">
				<Separator className="mb-3 bg-border/70" />
				{renderNavButton({
					label: "Help",
					icon: HelpCircle,
					onClick: () => setShowShortcutsDialog(true),
				})}
			</div>
		</aside>
	);
}
