export type ExportFileKind = "recording" | "screenshot";

function pad2(value: number) {
	return String(value).padStart(2, "0");
}

export function formatLocalExportTimestamp(date = new Date()): string {
	const year = date.getFullYear();
	const month = pad2(date.getMonth() + 1);
	const day = pad2(date.getDate());
	const hours = date.getHours();
	const minutes = pad2(date.getMinutes());
	const seconds = pad2(date.getSeconds());
	const meridiem = hours >= 12 ? "PM" : "AM";
	const hour12 = hours % 12 || 12;

	return `${year}-${month}-${day} at ${hour12}.${minutes}.${seconds} ${meridiem}`;
}

export function getSuggestedExportFileName(
	kind: ExportFileKind,
	extension: string,
	date = new Date(),
): string {
	const normalizedExtension = extension.replace(/^\./, "");
	return `${kind} ${formatLocalExportTimestamp(date)}.${normalizedExtension}`;
}
