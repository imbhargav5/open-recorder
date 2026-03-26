use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::{AppHandle, Manager};

use crate::app_paths;
use crate::state::AppState;

fn get_screenshots_dir(state: &AppState) -> PathBuf {
    if let Some(ref custom) = state.custom_recordings_dir {
        PathBuf::from(custom)
    } else {
        app_paths::default_screenshots_dir()
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

/// Build screencapture args for the given capture type and optional window id.
/// This is extracted for testability — the actual command also prepends `-x`
/// and appends the output path.
fn screencapture_args(capture_type: &str, window_id: Option<u64>) -> Vec<String> {
    let mut args = Vec::new();
    match capture_type {
        "window" => {
            if let Some(wid) = window_id {
                args.push(format!("-l{}", wid));
            }
        }
        "area" => {
            args.push("-i".to_string());
        }
        _ => {
            // Full screen — default screencapture behaviour
        }
    }
    args
}

/// Build a screenshot filename from the given timestamp.
fn screenshot_filename(timestamp: u64) -> String {
    format!("screenshot-{}.png", timestamp)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app_paths;
    use crate::state::AppState;

    // ==================== get_screenshots_dir ====================

    #[test]
    fn test_get_screenshots_dir_with_custom_dir() {
        let mut state = AppState::default();
        state.custom_recordings_dir = Some("/custom/output".to_string());
        let dir = get_screenshots_dir(&state);
        assert_eq!(dir, PathBuf::from("/custom/output"));
    }

    #[test]
    fn test_get_screenshots_dir_without_custom_dir() {
        let state = AppState::default();
        let dir = get_screenshots_dir(&state);
        assert_eq!(dir, app_paths::default_screenshots_dir());
    }

    #[test]
    fn test_get_screenshots_dir_empty_custom_dir_is_still_used() {
        // An empty string is Some(""), so it's treated as custom
        let mut state = AppState::default();
        state.custom_recordings_dir = Some("".to_string());
        let dir = get_screenshots_dir(&state);
        assert_eq!(dir, PathBuf::from(""));
    }

    // ==================== screenshot_filename ====================

    #[test]
    fn test_screenshot_filename_format() {
        let name = screenshot_filename(1700000000);
        assert_eq!(name, "screenshot-1700000000.png");
    }

    #[test]
    fn test_screenshot_filename_starts_with_screenshot() {
        let name = screenshot_filename(42);
        assert!(name.starts_with("screenshot-"));
    }

    #[test]
    fn test_screenshot_filename_ends_with_png() {
        let name = screenshot_filename(42);
        assert!(name.ends_with(".png"));
    }

    #[test]
    fn test_screenshot_filename_zero_timestamp() {
        let name = screenshot_filename(0);
        assert_eq!(name, "screenshot-0.png");
    }

    #[test]
    fn test_screenshot_filename_contains_numeric_timestamp() {
        let name = screenshot_filename(9876543210);
        // Extract the numeric part between "screenshot-" and ".png"
        let numeric = name
            .strip_prefix("screenshot-")
            .unwrap()
            .strip_suffix(".png")
            .unwrap();
        assert!(numeric.parse::<u64>().is_ok());
        assert_eq!(numeric, "9876543210");
    }

    // ==================== screencapture_args ====================

    #[test]
    fn test_screencapture_args_screen_type() {
        let args = screencapture_args("screen", None);
        assert!(args.is_empty(), "Full screen should have no extra args");
    }

    #[test]
    fn test_screencapture_args_window_with_id() {
        let args = screencapture_args("window", Some(12345));
        assert_eq!(args, vec!["-l12345"]);
    }

    #[test]
    fn test_screencapture_args_window_without_id() {
        // Edge case: capture_type is "window" but no window_id provided
        // This silently falls back to full-screen behavior (no -l flag)
        let args = screencapture_args("window", None);
        assert!(
            args.is_empty(),
            "Window capture without id should produce no extra args"
        );
    }

    #[test]
    fn test_screencapture_args_area_type() {
        let args = screencapture_args("area", None);
        assert_eq!(args, vec!["-i"]);
    }

    #[test]
    fn test_screencapture_args_area_ignores_window_id() {
        let args = screencapture_args("area", Some(999));
        assert_eq!(args, vec!["-i"], "Area mode should ignore window_id");
    }

    #[test]
    fn test_screencapture_args_unknown_type_defaults_to_fullscreen() {
        let args = screencapture_args("monitor", None);
        assert!(args.is_empty());
    }

    #[test]
    fn test_screencapture_args_empty_type_defaults_to_fullscreen() {
        let args = screencapture_args("", None);
        assert!(args.is_empty());
    }
}
