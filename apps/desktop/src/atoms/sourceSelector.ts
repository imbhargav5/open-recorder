import { atom } from 'jotai'

export interface DesktopSource {
  id: string
  name: string
  thumbnail: string | null
  display_id: string
  appIcon: string | null
  originalName: string
  sourceType: 'screen' | 'window'
  appName?: string
  windowTitle?: string
  windowId?: number
}

export type SourceSelectorTab = 'screens' | 'windows'

function getInitialTab(): SourceSelectorTab {
  try {
    const params = new URLSearchParams(window.location.search)
    return params.get('tab') === 'windows' ? 'windows' : 'screens'
  } catch {
    return 'screens'
  }
}

export const sourcesAtom = atom<DesktopSource[]>([])
export const selectedDesktopSourceAtom = atom<DesktopSource | null>(null)
export const sourceSelectorTabAtom = atom<SourceSelectorTab>(getInitialTab())
export const sourcesLoadingAtom = atom<boolean>(true)
export const windowsLoadingAtom = atom<boolean>(true)
