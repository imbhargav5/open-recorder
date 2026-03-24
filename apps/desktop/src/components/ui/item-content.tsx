import type { PropsWithChildren } from "react";

interface ItemContentProps extends PropsWithChildren {
	classes: string;
}

function ItemContent({ children, classes }: ItemContentProps) {
	return (
		<div
			className={`bg-white/5 border border-white/10 rounded-md shadow-sm w-full flex flex-row items-center px-3 py-1 gap-2 transition-all duration-150 hover:bg-[#2563EB]/10 hover:shadow-lg ${classes}`}
			style={{ minHeight: 40 }}
		>
			{children}
		</div>
	);
}

export default ItemContent;
