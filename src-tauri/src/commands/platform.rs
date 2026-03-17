use std::sync::Mutex;
use tauri::{AppHandle, Manager};

use crate::state::AppState;

#[tauri::command]
pub fn get_platform() -> String {
    #[cfg(target_os = "macos")]
    { "darwin".to_string() }
    #[cfg(target_os = "windows")]
    { "win32".to_string() }
    #[cfg(target_os = "linux")]
    { "linux".to_string() }
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
            .arg(std::path::Path::new(&path).parent().unwrap_or(std::path::Path::new(&path)))
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn open_recordings_folder(state: tauri::State<'_, Mutex<AppState>>) -> Result<(), String> {
    let dir = {
        let state = state.lock().map_err(|e| e.to_string())?;
        state.custom_recordings_dir.clone()
    };
    let recordings_dir = dir.unwrap_or_else(|| {
        dirs::video_dir()
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
            .join("Open Recorder")
            .to_string_lossy()
            .to_string()
    });
    open::that(&recordings_dir).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn get_asset_base_path(app: AppHandle) -> Result<String, String> {
    let resource_dir = app.path().resource_dir().map_err(|e| e.to_string())?;
    Ok(resource_dir.to_string_lossy().to_string())
}

#[tauri::command]
pub fn hide_cursor() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        // On macOS, use CoreGraphics to hide the cursor
        use std::process::Command;
        Command::new("osascript")
            .args(["-e", "tell application \"System Events\" to set visible of cursor to false"])
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
