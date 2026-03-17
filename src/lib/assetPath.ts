import { getAssetBasePath, convertFileToSrc } from '@/lib/backend'

function encodeRelativeAssetPath(relativePath: string): string {
  return relativePath
    .replace(/^\/+/, '')
    .split('/')
    .filter(Boolean)
    .map((part) => encodeURIComponent(part))
    .join('/')
}

export async function getAssetPath(relativePath: string): Promise<string> {
  const encodedRelativePath = encodeRelativeAssetPath(relativePath)

  try {
    if (typeof window !== 'undefined') {
      // If running in a dev server (http/https), prefer the web-served path
      if (window.location?.protocol?.startsWith('http')) {
        return `/${encodedRelativePath}`
      }

      // Use Tauri's convertFileSrc for asset protocol
      const base = await getAssetBasePath()
      if (base) {
        const fullPath = `${base}/${relativePath}`
        return convertFileToSrc(fullPath)
      }
    }
  } catch {
    // ignore and use fallback
  }

  return `/${encodedRelativePath}`
}

function toLocalFilePath(resourceUrl: string) {
  if (!resourceUrl.startsWith('file://')) {
    return null
  }

  const decodedPath = decodeURIComponent(resourceUrl.replace(/^file:\/\//, ''))
  if (/^\/[A-Za-z]:/.test(decodedPath)) {
    return decodedPath.slice(1)
  }

  return decodedPath
}

export async function getRenderableAssetUrl(asset: string): Promise<string> {
  if (!asset || asset.startsWith('data:') || asset.startsWith('http') || asset.startsWith('#') || asset.startsWith('linear-gradient') || asset.startsWith('radial-gradient')) {
    return asset
  }

  const resolvedAsset = asset.startsWith('/') && !asset.startsWith('//')
    ? await getAssetPath(asset.replace(/^\//, ''))
    : asset

  const localFilePath = toLocalFilePath(resolvedAsset)
  if (localFilePath) {
    return convertFileToSrc(localFilePath)
  }

  return resolvedAsset
}

export default getAssetPath;
