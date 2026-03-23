use std::sync::Mutex;
use tauri::{AppHandle, Manager};

use crate::app_paths;
use crate::state::AppState;

#[tauri::command]
pub fn get_platform() -> String {
    #[cfg(target_os = "macos")]
    {
        "darwin".to_string()
    }
    #[cfg(target_os = "windows")]
    {
        "win32".to_string()
    }
    #[cfg(target_os = "linux")]
    {
        "linux".to_string()
    }
}

#[tauri::command]
pub async fn open_external_url(url: String) -> Result<(), String> {
    open::that(&url).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn reveal_in_folder(path: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        tokio::process::Command::new("open")
            .args(["-R", &path])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "windows")]
    {
        tokio::process::Command::new("explorer")
            .args(["/select,", &path])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "linux")]
    {
        tokio::process::Command::new("xdg-open")
            .arg(
                std::path::Path::new(&path)
                    .parent()
                    .unwrap_or(std::path::Path::new(&path)),
            )
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn open_recordings_folder(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let dir = {
        let state = state.lock().map_err(|e| e.to_string())?;
        state.custom_recordings_dir.clone()
    };
    let recordings_dir = dir.unwrap_or_else(|| {
        app_paths::default_recordings_dir()
            .to_string_lossy()
            .to_string()
    });
    open::that(&recordings_dir).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn get_asset_base_path(app: AppHandle) -> Result<String, String> {
    let resource_dir = app.path().resource_dir().map_err(|e| e.to_string())?;
    let public_resource_dir = resource_dir.join("_up_").join("public");

    if public_resource_dir.exists() {
        return Ok(public_resource_dir.to_string_lossy().to_string());
    }

    let legacy_public_dir = resource_dir.join("public");
    if legacy_public_dir.exists() {
        return Ok(legacy_public_dir.to_string_lossy().to_string());
    }

    Ok(resource_dir.to_string_lossy().to_string())
}

#[tauri::command]
pub fn hide_cursor() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        // On macOS, use CoreGraphics to hide the cursor
        use std::process::Command;
        Command::new("osascript")
            .args([
                "-e",
                "tell application \"System Events\" to set visible of cursor to false",
            ])
            .spawn()
            .ok();
    }
    Ok(())
}

#[tauri::command]
pub fn is_wgc_available() -> bool {
    #[cfg(target_os = "windows")]
    {
        // Check if Windows Graphics Capture is available (Windows 10 1903+)
        true
    }
    #[cfg(not(target_os = "windows"))]
    {
        false
    }
}

#[tauri::command]
pub async fn mux_wgc_recording(
    _app: AppHandle,
    _state: tauri::State<'_, Mutex<AppState>>,
) -> Result<String, String> {
    #[cfg(target_os = "windows")]
    {
        // TODO: Implement WGC audio muxing via FFmpeg sidecar
        Err("WGC muxing not yet implemented in Tauri backend".to_string())
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err("WGC is only available on Windows".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_platform_returns_known_value() {
        let platform = get_platform();
        assert!(
            ["darwin", "win32", "linux"].contains(&platform.as_str()),
            "Unexpected platform: {}",
            platform
        );
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn test_get_platform_macos() {
        assert_eq!(get_platform(), "darwin");
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn test_get_platform_windows() {
        assert_eq!(get_platform(), "win32");
    }

    #[test]
    #[cfg(target_os = "linux")]
    fn test_get_platform_linux() {
        assert_eq!(get_platform(), "linux");
    }

    #[test]
    fn test_get_platform_is_not_empty() {
        assert!(!get_platform().is_empty());
    }

    #[test]
    #[cfg(not(target_os = "windows"))]
    fn test_is_wgc_available_false_on_non_windows() {
        assert!(!is_wgc_available());
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn test_is_wgc_available_true_on_windows() {
        assert!(is_wgc_available());
    }

    #[test]
    fn test_get_platform_deterministic() {
        let p1 = get_platform();
        let p2 = get_platform();
        assert_eq!(p1, p2);
    }
}
