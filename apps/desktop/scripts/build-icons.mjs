import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync } from 'node:fs';
import { access, copyFile, mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(__dirname, '..');
const sourceIconPath = path.join(appRoot, 'branding', 'source-assets', 'open-recorder-brand-image.png');
const generatedPngIconsDir = path.join(appRoot, '.tmp', 'generated-icon-pngs');
const iconsetDir = path.join(appRoot, '.tmp', 'icon.iconset');

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

async function cleanup() {
  await Promise.all([
    rm(generatedPngIconsDir, { force: true, recursive: true }),
    rm(iconsetDir, { force: true, recursive: true }),
  ]);
}

async function syncGeneratedAssets(icnsPath, icoPath) {
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

  // ICNS — for electron-builder (buildResources) and repo icons
  copyJobs.push(
    copyWithParents(icnsPath, path.join(appRoot, 'public', 'icons', 'icon.icns')),
    copyWithParents(icnsPath, path.join(appRoot, 'icons', 'icons', 'mac', 'icon.icns')),
  );

  // ICO — only if generation succeeded
  if (icoPath) {
    copyJobs.push(
      copyWithParents(icoPath, path.join(appRoot, 'public', 'icons', 'icon.ico')),
      copyWithParents(icoPath, path.join(appRoot, 'icons', 'icons', 'win', 'icon.ico')),
    );
  }

  copyJobs.push(
    copyWithParents(
      path.join(generatedPngIconsDir, '128x128.png'),
      path.join(appRoot, 'public', 'rec-button.png'),
    ),
  );

  copyJobs.push(
    copyWithParents(
      sourceIconPath,
      path.join(appRoot, 'public', 'openscreen.png'),
    ),
  );

  await Promise.all(copyJobs);
}

async function main() {
  if (process.platform !== 'darwin') {
    console.error('Error: Icon generation requires macOS (uses sips and iconutil).');
    process.exit(1);
  }

  await ensureFileExists(sourceIconPath);
  await cleanup();

  // ── Generate PNGs at all required sizes using sips (macOS built-in) ─────────
  mkdirSync(generatedPngIconsDir, { recursive: true });
  console.log('Generating PNG icons with sips...');

  for (const size of generatedPngSizes) {
    const outPath = path.join(generatedPngIconsDir, `${size}x${size}.png`);
    const result = spawnSync('sips', ['-z', String(size), String(size), sourceIconPath, '--out', outPath], {
      encoding: 'utf8',
    });
    if (result.status !== 0) {
      const details = [result.stderr, result.stdout].filter(Boolean).join('\n').trim();
      throw new Error(details || `sips failed for size ${size}`);
    }
  }

  // ── Generate ICNS using iconutil (macOS built-in) ────────────────────────────
  console.log('Generating icon.icns with iconutil...');
  const icnsPath = path.join(appRoot, '.tmp', 'icon.icns');
  mkdirSync(iconsetDir, { recursive: true });

  // iconutil requires .iconset directory with specific filenames
  const icnsSlots = [
    { size: 16, name: 'icon_16x16.png' },
    { size: 32, name: 'icon_16x16@2x.png' },
    { size: 32, name: 'icon_32x32.png' },
    { size: 64, name: 'icon_32x32@2x.png' },
    { size: 128, name: 'icon_128x128.png' },
    { size: 256, name: 'icon_128x128@2x.png' },
    { size: 256, name: 'icon_256x256.png' },
    { size: 512, name: 'icon_256x256@2x.png' },
    { size: 512, name: 'icon_512x512.png' },
    { size: 1024, name: 'icon_512x512@2x.png' },
  ];
  for (const { size, name } of icnsSlots) {
    copyFileSync(path.join(generatedPngIconsDir, `${size}x${size}.png`), path.join(iconsetDir, name));
  }

  const icnsResult = spawnSync('iconutil', ['-c', 'icns', iconsetDir, '-o', icnsPath], { encoding: 'utf8' });
  if (icnsResult.status !== 0) {
    const details = [icnsResult.stderr, icnsResult.stdout].filter(Boolean).join('\n').trim();
    throw new Error(details || 'iconutil failed');
  }

  // ── Generate ICO using ImageMagick (optional) ─────────────────────────────────
  console.log('Generating icon.ico with ImageMagick...');
  const icoPath = path.join(appRoot, '.tmp', 'icon.ico');
  const icoPngs = [16, 32, 48, 64, 128, 256].map((s) => path.join(generatedPngIconsDir, `${s}x${s}.png`));
  const magick = ['magick', 'convert'].find(
    (cmd) => spawnSync(cmd, ['--version'], { encoding: 'utf8' }).status === 0,
  );

  let icoGenerated = false;
  if (magick) {
    const icoArgs = magick === 'magick'
      ? ['convert', ...icoPngs, icoPath]
      : [...icoPngs, icoPath];
    const icoResult = spawnSync(magick, icoArgs, { encoding: 'utf8' });
    if (icoResult.status !== 0) {
      const details = [icoResult.stderr, icoResult.stdout].filter(Boolean).join('\n').trim();
      throw new Error(details || 'ImageMagick ico generation failed');
    }
    icoGenerated = true;
  } else {
    console.warn('Warning: ImageMagick not found, skipping icon.ico generation.');
    console.warn('Install ImageMagick to generate Windows icons: brew install imagemagick');
  }

  await syncGeneratedAssets(icnsPath, icoGenerated ? icoPath : null);
  await cleanup();

  console.log('Brand icons regenerated from branding/source-assets/open-recorder-brand-image.png');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
