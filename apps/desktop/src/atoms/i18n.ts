import { atomWithStorage } from "jotai/utils";
import { type AppLocale, DEFAULT_LOCALE, SUPPORTED_LOCALES } from "@/i18n/config";

const LOCALE_STORAGE_KEY = "open-recorder.locale";

export function normalizeLocale(locale: string | null | undefined): AppLocale {
	if (!locale) return DEFAULT_LOCALE;
	const normalized = locale.toLowerCase().split("-")[0];
	return SUPPORTED_LOCALES.includes(normalized as AppLocale)
		? (normalized as AppLocale)
		: DEFAULT_LOCALE;
}

export function getInitialLocale(): AppLocale {
	if (typeof window === "undefined") return DEFAULT_LOCALE;
	const stored = window.localStorage.getItem(LOCALE_STORAGE_KEY);
	if (stored && SUPPORTED_LOCALES.includes(stored as AppLocale)) {
		return stored as AppLocale;
	}
	return normalizeLocale(window.navigator.language);
}

export const localeAtom = atomWithStorage<AppLocale>(LOCALE_STORAGE_KEY, getInitialLocale());
