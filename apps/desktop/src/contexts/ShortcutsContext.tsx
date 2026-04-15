import { useAtom } from 'jotai'
import { createContext, useCallback, useContext, useEffect, useMemo, type ReactNode } from 'react'
import { mergeWithDefaults, type ShortcutsConfig } from '@/lib/shortcuts'
import { isMac as getIsMac } from '@/utils/platformUtils'
import { getShortcuts as backendGetShortcuts, saveShortcuts as backendSaveShortcuts } from '@/lib/backend'
import { isMacOSAtom } from '@/atoms/app'
import { isShortcutsConfigOpenAtom, shortcutsAtom } from '@/atoms/shortcuts'

interface ShortcutsContextValue {
  shortcuts: ShortcutsConfig
  isMac: boolean
  setShortcuts: (config: ShortcutsConfig) => void
  persistShortcuts: (config?: ShortcutsConfig) => Promise<void>
  isConfigOpen: boolean
  openConfig: () => void
  closeConfig: () => void
}

const ShortcutsContext = createContext<ShortcutsContextValue | null>(null)

export function useShortcuts(): ShortcutsContextValue {
  const ctx = useContext(ShortcutsContext)
  if (!ctx) throw new Error('useShortcuts must be used within <ShortcutsProvider>')
  return ctx
}

export function ShortcutsProvider({ children }: { children: ReactNode }) {
  const [shortcuts, setShortcuts] = useAtom(shortcutsAtom)
  const [isMac, setIsMac] = useAtom(isMacOSAtom)
  const [isConfigOpen, setIsConfigOpen] = useAtom(isShortcutsConfigOpenAtom)

  useEffect(() => {
    getIsMac().then(setIsMac).catch(() => {})

    backendGetShortcuts()
      .then((saved) => {
        if (saved) {
          setShortcuts(mergeWithDefaults(saved as Partial<ShortcutsConfig>))
        }
      })
      .catch(() => {})
  }, [setIsMac, setShortcuts])

  const persistShortcuts = useCallback(
    async (config?: ShortcutsConfig) => {
      await backendSaveShortcuts(config ?? shortcuts)
    },
    [shortcuts],
  )

  const openConfig = useCallback(() => setIsConfigOpen(true), [setIsConfigOpen])
  const closeConfig = useCallback(() => setIsConfigOpen(false), [setIsConfigOpen])

  const value = useMemo<ShortcutsContextValue>(
    () => ({ shortcuts, isMac, setShortcuts, persistShortcuts, isConfigOpen, openConfig, closeConfig }),
    [shortcuts, isMac, setShortcuts, persistShortcuts, isConfigOpen, openConfig, closeConfig],
  )

  return <ShortcutsContext.Provider value={value}>{children}</ShortcutsContext.Provider>
}
