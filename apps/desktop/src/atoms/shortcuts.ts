import { atom } from 'jotai'
import { DEFAULT_SHORTCUTS, type ShortcutsConfig } from '@/lib/shortcuts'

export const shortcutsAtom = atom<ShortcutsConfig>(DEFAULT_SHORTCUTS)
export const isMacAtom = atom<boolean>(false)
export const isShortcutsConfigOpenAtom = atom<boolean>(false)
