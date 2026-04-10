import { atom } from 'jotai'

export type SettingsSidebarTab = 'appearance' | 'cursor' | 'camera' | 'background' | 'audio'
export type BackgroundTab = 'image' | 'color' | 'gradient'

const DEFAULT_GRADIENT =
  'linear-gradient( 111.6deg,  rgba(114,167,232,1) 9.4%, rgba(253,129,82,1) 43.9%, rgba(253,129,82,1) 54.8%, rgba(249,202,86,1) 86.3% )'

export const settingsActiveTabAtom = atom<SettingsSidebarTab>('appearance')
export const settingsBackgroundTabAtom = atom<BackgroundTab>('image')
export const settingsCustomImagesAtom = atom<string[]>([])
export const settingsSelectedColorAtom = atom<string>('#ADADAD')
export const settingsGradientAtom = atom<string>(DEFAULT_GRADIENT)
export const settingsShowCropModalAtom = atom<boolean>(false)
