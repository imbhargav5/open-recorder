use std::env;
use std::fs;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    compile_sidecars();
    tauri_build::build();
}

fn compile_sidecars() {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os != "macos" {
        return;
    }

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let native_dir = manifest_dir.join("native");
    let binaries_dir = manifest_dir.join("binaries");
    let target_triple = get_target_triple();

    let helpers = [
        ("ScreenCaptureKitRecorder.swift", "openscreen-screencapturekit-helper"),
        ("ScreenCaptureKitWindowList.swift", "openscreen-window-list"),
        ("SystemCursorAssets.swift", "openscreen-system-cursors"),
        ("NativeCursorMonitor.swift", "openscreen-native-cursor-monitor"),
        ("ScreenSelectionFlash.swift", "openscreen-screen-selection-flash"),
    ];

    println!("cargo:rerun-if-changed={}", native_dir.display());
    fs::create_dir_all(&binaries_dir).expect("failed to create src-tauri/binaries");

    for (source_name, output_name) in helpers {
        let source_path = native_dir.join(source_name);
        if !source_path.exists() {
            continue;
        }

        println!("cargo:rerun-if-changed={}", source_path.display());

        let output_path = binaries_dir.join(format!("{output_name}-{target_triple}"));
        if !needs_rebuild(&source_path, &output_path) {
            continue;
        }

        let status = Command::new("swiftc")
            .arg("-O")
            .arg(&source_path)
            .arg("-o")
            .arg(&output_path)
            .status()
            .unwrap_or_else(|error| panic!("failed to spawn swiftc for {}: {}", source_name, error));

        if !status.success() {
            panic!("failed to compile {}", source_name);
        }

        #[cfg(unix)]
        {
            let mut permissions = fs::metadata(&output_path)
                .expect("failed to stat sidecar")
                .permissions();
            permissions.set_mode(0o755);
            fs::set_permissions(&output_path, permissions)
                .expect("failed to set sidecar permissions");
        }
    }
}

fn needs_rebuild(source_path: &Path, output_path: &Path) -> bool {
    let source_modified = fs::metadata(source_path)
        .and_then(|metadata| metadata.modified())
        .expect("failed to read sidecar source metadata");

    let output_modified = fs::metadata(output_path)
        .and_then(|metadata| metadata.modified())
        .ok();

    match output_modified {
        Some(modified) => modified < source_modified,
        None => true,
    }
}

fn get_target_triple() -> String {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();

    match (target_os.as_str(), target_arch.as_str()) {
        ("macos", "aarch64") => "aarch64-apple-darwin".to_string(),
        ("macos", "x86_64") => "x86_64-apple-darwin".to_string(),
        ("windows", "x86_64") => "x86_64-pc-windows-msvc".to_string(),
        ("linux", "x86_64") => "x86_64-unknown-linux-gnu".to_string(),
        _ => format!("{target_arch}-{target_os}"),
    }
}
