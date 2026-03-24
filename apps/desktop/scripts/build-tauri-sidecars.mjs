/**
 * Build script for Tauri sidecars.
 *
 * Compiles Swift helpers on macOS and copies them to src-tauri/binaries/
 * with Tauri's triple-suffixed naming convention:
 *   e.g., openscreen-screencapturekit-helper-aarch64-apple-darwin
 */

import { spawnSync } from 'node:child_process';
import { chmod, mkdir, copyFile } from 'node:fs/promises';
import path from 'node:path';
import { existsSync } from 'node:fs';

const projectRoot = process.cwd();
const nativeRoot = path.join(projectRoot, 'src-tauri', 'native');
const outputDir = path.join(projectRoot, 'src-tauri', 'binaries');

function getTargetTripleFromArgs() {
  const targetFlagIndex = process.argv.indexOf('--target');
  if (targetFlagIndex !== -1 && process.argv[targetFlagIndex + 1]) {
    return process.argv[targetFlagIndex + 1];
  }

  return null;
}

// Determine Tauri target triple
function getHostTriple() {
  const platform = process.platform;
  const arch = process.arch;

  if (platform === 'darwin') {
    return arch === 'arm64' ? 'aarch64-apple-darwin' : 'x86_64-apple-darwin';
  }
  if (platform === 'win32') {
    return 'x86_64-pc-windows-msvc';
  }
  if (platform === 'linux') {
    return 'x86_64-unknown-linux-gnu';
  }
  throw new Error(`Unsupported platform: ${platform}-${arch}`);
}

function getTargetTriple() {
  return (
    process.env.TAURI_TARGET_TRIPLE ||
    process.env.npm_config_target ||
    getTargetTripleFromArgs() ||
    getHostTriple()
  );
}

function getSwiftTargetTriple(targetTriple) {
  const deploymentTarget = getMacOSDeploymentTarget();

  switch (targetTriple) {
    case 'aarch64-apple-darwin':
      return `arm64-apple-macos${deploymentTarget}`;
    case 'x86_64-apple-darwin':
      return `x86_64-apple-macos${deploymentTarget}`;
    default:
      throw new Error(`Unsupported macOS target triple for Swift sidecars: ${targetTriple}`);
  }
}

function getMacOSDeploymentTarget() {
  if (process.env.MACOSX_DEPLOYMENT_TARGET) {
    return process.env.MACOSX_DEPLOYMENT_TARGET;
  }

  const versionCheck = spawnSync('sw_vers', ['-productVersion'], { encoding: 'utf8' });
  if (versionCheck.status === 0) {
    const [major] = versionCheck.stdout.trim().split('.');
    if (major) {
      return `${major}.0`;
    }
  }

  return '14.0';
}

const triple = getTargetTriple();

await mkdir(outputDir, { recursive: true });

// ─── macOS Swift Helpers ────────────────────────────────────────────────────

if (process.platform === 'darwin') {
  const swiftTargetTriple = getSwiftTargetTriple(triple);
  const swiftcCheck = spawnSync('swiftc', ['--version'], { encoding: 'utf8' });
  if (swiftcCheck.status !== 0) {
    const details = [swiftcCheck.stderr, swiftcCheck.stdout].filter(Boolean).join('\n').trim();
    throw new Error(details || 'swiftc is unavailable; install Xcode Command Line Tools.');
  }

  const helpers = [
    {
      source: 'ScreenCaptureKitRecorder.swift',
      output: 'openscreen-screencapturekit-helper',
    },
    {
      source: 'ScreenCaptureKitWindowList.swift',
      output: 'openscreen-window-list',
    },
    {
      source: 'SystemCursorAssets.swift',
      output: 'openscreen-system-cursors',
    },
    {
      source: 'NativeCursorMonitor.swift',
      output: 'openscreen-native-cursor-monitor',
    },
    {
      source: 'ScreenSelectionFlash.swift',
      output: 'openscreen-screen-selection-flash',
    },
  ];

  for (const helper of helpers) {
    const sourcePath = path.join(nativeRoot, helper.source);
    if (!existsSync(sourcePath)) {
      console.warn(`[build-tauri-sidecars] Source not found: ${sourcePath}, skipping.`);
      continue;
    }

    // Compile to a temporary location
    const tempOutput = path.join(outputDir, helper.output);
    const result = spawnSync(
      'swiftc',
      ['-target', swiftTargetTriple, '-O', sourcePath, '-o', tempOutput],
      {
        encoding: 'utf8',
        timeout: 120000,
      }
    );

    if (result.status !== 0) {
      const details = [result.stderr, result.stdout].filter(Boolean).join('\n').trim();
      throw new Error(details || `Failed to compile ${helper.source}`);
    }

    // Rename with triple suffix for Tauri
    const tauriOutput = path.join(outputDir, `${helper.output}-${triple}`);
    await copyFile(tempOutput, tauriOutput);
    await chmod(tauriOutput, 0o755);

    // Clean up temp file (without triple)
    const { unlinkSync } = await import('node:fs');
    try {
      unlinkSync(tempOutput);
    } catch {
      // ignore
    }

    console.log(`[build-tauri-sidecars] Built ${helper.output}-${triple}`);
  }
}

// ─── Windows WGC Capture ────────────────────────────────────────────────────

if (process.platform === 'win32') {
  const wgcDir = path.join(nativeRoot, 'wgc-capture');
  if (existsSync(wgcDir)) {
    console.log('[build-tauri-sidecars] Building WGC capture helper...');
    const result = spawnSync('dotnet', ['publish', '-c', 'Release', '-o', outputDir], {
      cwd: wgcDir,
      encoding: 'utf8',
      timeout: 120000,
    });

    if (result.status !== 0) {
      console.warn('[build-tauri-sidecars] WGC build failed:', result.stderr);
    } else {
      // Rename with triple suffix
      const exeSrc = path.join(outputDir, 'wgc-capture.exe');
      const exeDst = path.join(outputDir, `wgc-capture-${triple}.exe`);
      if (existsSync(exeSrc)) {
        await copyFile(exeSrc, exeDst);
        console.log(`[build-tauri-sidecars] Built wgc-capture-${triple}.exe`);
      }
    }
  }
}

console.log('[build-tauri-sidecars] Done.');
