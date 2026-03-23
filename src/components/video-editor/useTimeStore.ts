import { useMemo, useSyncExternalStore } from "react";

export interface TimeStore {
	getTime: () => number;
	setTime: (t: number) => void;
	subscribe: (listener: () => void) => () => void;
}

export function createTimeStore(): TimeStore {
	let currentTime = 0;
	const listeners = new Set<() => void>();
	return {
		getTime: () => currentTime,
		setTime: (t: number) => {
			currentTime = t;
			for (const fn of listeners) fn();
		},
		subscribe: (listener: () => void) => {
			listeners.add(listener);
			return () => {
				listeners.delete(listener);
			};
		},
	};
}

export function useTimeStore(): TimeStore {
	return useMemo(() => createTimeStore(), []);
}

export function useTimeValue(store: TimeStore): number {
	return useSyncExternalStore(store.subscribe, store.getTime);
}
