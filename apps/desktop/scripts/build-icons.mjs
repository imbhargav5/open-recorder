import { spawnSync } from 'node:child_process';
import { access, copyFile, mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, '..');
const sourceIconPath = path.join(appRoot, 'branding', 'source-assets', 'open-recorder-brand-image.png');
const tauriIconsDir = path.join(appRoot, 'src-tauri', 'icons');
const generatedPngIconsDir = path.join(appRoot, '.tmp', 'generated-icon-pngs');

const publicIconSizes = [16, 32, 64, 128, 256, 512, 1024];
const brandAssetSizes = [16, 32, 64, 128, 256, 512, 1024];
const repoIconSizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024];
const generatedPngSizes = Array.from(new Set([...publicIconSizes, ...brandAssetSizes, ...repoIconSizes]));

async function ensureFileExists(filePath) {
  await access(filePath);
}

async function copyWithParents(from, to) {
  await mkdir(path.dirname(to), { recursive: true });
  await copyFile(from, to);
}

function runTauriCommand(args, errorMessage) {
  const result = spawnSync('pnpm', ['exec', 'tauri', ...args], {
    cwd: appRoot,
    stdio: 'inherit',
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${errorMessage} with exit code ${result.status ?? 'unknown'}`);
  }
}

function runTauriIconBuilder() {
  runTauriCommand(
    ['icon', sourceIconPath, '--output', tauriIconsDir],
    'default tauri icon generation failed',
  );
}

function runCustomPngIconBuilder() {
  runTauriCommand(
    [
      'icon',
      sourceIconPath,
      '--output',
      generatedPngIconsDir,
      '--png',
      generatedPngSizes.join(','),
    ],
    'custom png icon generation failed',
  );
}

async function cleanupUnusedTauriAssets() {
  const extraPaths = [
    path.join(tauriIconsDir, '64x64.png'),
    path.join(tauriIconsDir, 'StoreLogo.png'),
    path.join(tauriIconsDir, 'Square30x30Logo.png'),
    path.join(tauriIconsDir, 'Square44x44Logo.png'),
    path.join(tauriIconsDir, 'Square71x71Logo.png'),
    path.join(tauriIconsDir, 'Square89x89Logo.png'),
    path.join(tauriIconsDir, 'Square107x107Logo.png'),
    path.join(tauriIconsDir, 'Square142x142Logo.png'),
    path.join(tauriIconsDir, 'Square150x150Logo.png'),
    path.join(tauriIconsDir, 'Square284x284Logo.png'),
    path.join(tauriIconsDir, 'Square310x310Logo.png'),
    path.join(tauriIconsDir, 'android'),
    path.join(tauriIconsDir, 'ios'),
    generatedPngIconsDir,
  ];

  await Promise.all(
    extraPaths.map((targetPath) =>
      rm(targetPath, {
        force: true,
        recursive: true,
      }),
    ),
  );
}

async function syncGeneratedAssets() {
  const copyJobs = [];

  for (const size of publicIconSizes) {
    copyJobs.push(
      copyWithParents(
        path.join(generatedPngIconsDir, `${size}x${size}.png`),
        path.join(appRoot, 'public', 'app-icons', `open-recorder-${size}.png`),
      ),
    );
  }

  for (const size of brandAssetSizes) {
    copyJobs.push(
      copyWithParents(
        path.join(generatedPngIconsDir, `${size}x${size}.png`),
        path.join(appRoot, 'branding', 'source-assets', `${size}-mac.png`),
      ),
    );
  }

  for (const size of repoIconSizes) {
    copyJobs.push(
      copyWithParents(
        path.join(generatedPngIconsDir, `${size}x${size}.png`),
        path.join(appRoot, 'icons', 'icons', 'png', `${size}x${size}.png`),
      ),
    );
  }

  copyJobs.push(
    copyWithParents(
      path.join(tauriIconsDir, 'icon.icns'),
      path.join(appRoot, 'icons', 'icons', 'mac', 'icon.icns'),
    ),
  );

  copyJobs.push(
    copyWithParents(
      path.join(tauriIconsDir, 'icon.ico'),
      path.join(appRoot, 'icons', 'icons', 'win', 'icon.ico'),
    ),
  );

  copyJobs.push(
    copyWithParents(
      path.join(generatedPngIconsDir, '128x128.png'),
      path.join(appRoot, 'public', 'rec-button.png'),
    ),
  );

  // Use the source image for full-size
  copyJobs.push(
    copyWithParents(
      sourceIconPath,
      path.join(appRoot, 'public', 'openscreen.png'),
    ),
  );

  await Promise.all(copyJobs);
}

async function main() {
  await ensureFileExists(sourceIconPath);
  await cleanupUnusedTauriAssets();
  runTauriIconBuilder();
  runCustomPngIconBuilder();
  await syncGeneratedAssets();
  await cleanupUnusedTauriAssets();
  console.log('Brand icons regenerated from branding/source-assets/open-recorder-brand-image.png');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
