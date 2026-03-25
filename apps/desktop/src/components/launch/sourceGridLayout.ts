export function getSourceGridColumnClass(type: "screen" | "window", sourceCount: number) {
	if (type === "window") {
		return "grid-cols-2";
	}

	if (sourceCount <= 1) {
		return "grid-cols-1";
	}

	if (sourceCount === 2 || sourceCount === 4) {
		return "grid-cols-2";
	}

	return "grid-cols-3";
}
