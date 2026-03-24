import * as React from "react";

import { cn } from "@/lib/utils";

const Empty = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
	({ className, ...props }, ref) => (
		<div
			ref={ref}
			className={cn(
				"mx-auto flex w-full max-w-md flex-col items-center justify-center gap-6 rounded-2xl border border-white/10 bg-white/[0.03] px-8 py-10 text-center shadow-2xl shadow-black/20 backdrop-blur-xl",
				className,
			)}
			{...props}
		/>
	),
);
Empty.displayName = "Empty";

const EmptyHeader = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
	({ className, ...props }, ref) => (
		<div
			ref={ref}
			className={cn("flex w-full flex-col items-center gap-3", className)}
			{...props}
		/>
	),
);
EmptyHeader.displayName = "EmptyHeader";

const EmptyMedia = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
	({ className, ...props }, ref) => (
		<div
			ref={ref}
			className={cn(
				"flex size-14 items-center justify-center rounded-full border border-white/10 bg-white/5 text-white/80",
				className,
			)}
			{...props}
		/>
	),
);
EmptyMedia.displayName = "EmptyMedia";

const EmptyTitle = React.forwardRef<HTMLHeadingElement, React.HTMLAttributes<HTMLHeadingElement>>(
	({ className, ...props }, ref) => (
		<h2
			ref={ref}
			className={cn("text-lg font-semibold tracking-tight text-white", className)}
			{...props}
		/>
	),
);
EmptyTitle.displayName = "EmptyTitle";

const EmptyDescription = React.forwardRef<
	HTMLParagraphElement,
	React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
	<p ref={ref} className={cn("max-w-sm text-sm leading-6 text-white/60", className)} {...props} />
));
EmptyDescription.displayName = "EmptyDescription";

const EmptyContent = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
	({ className, ...props }, ref) => (
		<div
			ref={ref}
			className={cn("flex w-full items-center justify-center", className)}
			{...props}
		/>
	),
);
EmptyContent.displayName = "EmptyContent";

export { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle };
