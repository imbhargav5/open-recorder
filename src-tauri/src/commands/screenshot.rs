use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::{AppHandle, Manager};

use crate::state::AppState;

fn get_screenshots_dir(state: &AppState) -> PathBuf {
    if let Some(ref custom) = state.custom_recordings_dir {
        PathBuf::from(custom)
    } else {
        dirs::picture_dir()
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Pictures"))
            .join("Open Recorder")
    }
}

/// Take a screenshot using native platform tools.
///
/// `capture_type`:
///   - `"screen"` — capture the entire primary display
///   - `"window"` — capture a specific window by `window_id`
///   - `"area"`   — interactive area selection
///
/// Returns the file path of the saved PNG screenshot.
#[tauri::command]
pub async fn take_screenshot(
    app: AppHandle,
    capture_type: String,
    window_id: Option<u64>,
) -> Result<String, String> {
    let state: tauri::State<'_, Mutex<AppState>> = app.state();
    let dir = {
        let s = state.lock().map_err(|e| e.to_string())?;
        get_screenshots_dir(&s)
    };

    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let filename = format!("screenshot-{}.png", timestamp);
    let screenshot_path = dir.join(&filename);
    let path_str = screenshot_path.to_string_lossy().to_string();

    #[cfg(target_os = "macos")]
    {
        use std::process::Command;

        let mut cmd = Command::new("screencapture");
        cmd.arg("-x"); // suppress shutter sound

        match capture_type.as_str() {
            "window" => {
                if let Some(wid) = window_id {
                    cmd.arg(format!("-l{}", wid));
                }
            }
            "area" => {
                cmd.arg("-i"); // interactive selection
            }
            _ => {
                // Full screen — default screencapture behaviour
            }
        }

        cmd.arg(&path_str);

        let output = cmd
            .output()
            .map_err(|e| format!("Failed to run screencapture: {}", e))?;

        if !output.status.success() {
            return Err("Screenshot capture failed or was cancelled".to_string());
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        return Err("Screenshot capture is currently only supported on macOS".to_string());
    }

    // screencapture may exit 0 even if the user cancelled; verify the file exists
    if !screenshot_path.exists() {
        return Err("Screenshot was cancelled".to_string());
    }

    // Persist the path in application state
    {
        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.current_screenshot_path = Some(path_str.clone());
    }

    Ok(path_str)
}

#[tauri::command]
pub fn get_current_screenshot_path(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<String>, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    Ok(s.current_screenshot_path.clone())
}

#[tauri::command]
pub fn set_current_screenshot_path(
    state: tauri::State<'_, Mutex<AppState>>,
    path: Option<String>,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.current_screenshot_path = path;
    Ok(())
}
