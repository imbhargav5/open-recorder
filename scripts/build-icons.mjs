import { spawnSync } from 'node:child_process';
import { access, copyFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const sourceIconPath = path.join(repoRoot, 'branding', 'source-assets', 'open-recorder-brand-image.png');
const tauriIconsDir = path.join(repoRoot, 'src-tauri', 'icons');

const publicIconSizes = [16, 32, 64, 128, 256, 512, 1024];
const brandAssetSizes = [16, 32, 64, 128, 256, 512, 1024];

async function ensureFileExists(filePath) {
  await access(filePath);
}

async function copyWithParents(from, to) {
  await mkdir(path.dirname(to), { recursive: true });
  await copyFile(from, to);
}

function runTauriIconBuilder() {
  // Use Tauri's built-in icon generator
  const result = spawnSync(
    'npx',
    ['@tauri-apps/cli', 'icon', sourceIconPath, '--output', tauriIconsDir],
    {
      cwd: repoRoot,
      stdio: 'inherit',
      shell: true,
    },
  );

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`cargo tauri icon failed with exit code ${result.status ?? 'unknown'}`);
  }
}

async function syncGeneratedAssets() {
  const copyJobs = [];

  // Tauri icon generator creates icons at known sizes in src-tauri/icons/
  // Map available generated sizes to public assets
  const tauriSizeMap = {
    32: '32x32.png',
    128: '128x128.png',
    256: '128x128@2x.png',
  };

  for (const size of publicIconSizes) {
    // Use the closest Tauri-generated PNG or the source image for larger sizes
    const tauriFile = tauriSizeMap[size];
    if (tauriFile) {
      copyJobs.push(
        copyWithParents(
          path.join(tauriIconsDir, tauriFile),
          path.join(repoRoot, 'public', 'app-icons', `open-recorder-${size}.png`),
        ),
      );
    }
  }

  for (const size of brandAssetSizes) {
    const tauriFile = tauriSizeMap[size];
    if (tauriFile) {
      copyJobs.push(
        copyWithParents(
          path.join(tauriIconsDir, tauriFile),
          path.join(repoRoot, 'branding', 'source-assets', `${size}-mac.png`),
        ),
      );
    }
  }

  // Copy specific assets
  if (tauriSizeMap[128]) {
    copyJobs.push(
      copyWithParents(
        path.join(tauriIconsDir, tauriSizeMap[128]),
        path.join(repoRoot, 'public', 'rec-button.png'),
      ),
    );
  }

  // Use the source image for full-size
  copyJobs.push(
    copyWithParents(
      sourceIconPath,
      path.join(repoRoot, 'public', 'openscreen.png'),
    ),
  );

  await Promise.all(copyJobs);
}

async function main() {
  await ensureFileExists(sourceIconPath);
  runTauriIconBuilder();
  await syncGeneratedAssets();
  console.log('Brand icons regenerated from branding/source-assets/open-recorder-brand-image.png');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
