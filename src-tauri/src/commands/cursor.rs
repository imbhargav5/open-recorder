use std::sync::Mutex;

use crate::state::AppState;

#[tauri::command]
pub async fn get_cursor_telemetry(
    video_path: String,
) -> Result<serde_json::Value, String> {
    // Cursor telemetry is stored as a JSON sidecar next to the video file
    let telemetry_path = format!("{}.cursor.json", video_path.trim_end_matches(".mov").trim_end_matches(".mp4").trim_end_matches(".webm"));

    if let Ok(data) = tokio::fs::read_to_string(&telemetry_path).await {
        serde_json::from_str(&data).map_err(|e| e.to_string())
    } else {
        Ok(serde_json::json!({ "samples": [], "clicks": [] }))
    }
}

#[tauri::command]
pub fn set_cursor_scale(
    state: tauri::State<'_, Mutex<AppState>>,
    scale: f64,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.cursor_scale = scale;
    Ok(())
}

#[tauri::command]
pub async fn get_system_cursor_assets(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<serde_json::Value, String> {
    // Check cache first
    {
        let s = state.lock().map_err(|e| e.to_string())?;
        if let Some(ref cached) = s.cached_system_cursor_assets {
            return Ok(cached.clone());
        }
    }

    #[cfg(target_os = "macos")]
    {
        let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
        let bin_dir = exe_path.parent().ok_or("Cannot find binary directory")?;

        let triple = if cfg!(target_arch = "aarch64") {
            "aarch64-apple-darwin"
        } else {
            "x86_64-apple-darwin"
        };

        let sidecar_name = format!("openscreen-system-cursors-{}", triple);
        let sidecar_path = bin_dir.join(&sidecar_name);

        if sidecar_path.exists() {
            let output = tokio::process::Command::new(&sidecar_path)
                .output()
                .await
                .map_err(|e| e.to_string())?;

            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let assets: serde_json::Value =
                    serde_json::from_str(&stdout).map_err(|e| e.to_string())?;

                // Cache the result
                let mut s = state.lock().map_err(|e| e.to_string())?;
                s.cached_system_cursor_assets = Some(assets.clone());

                return Ok(assets);
            }
        }
    }

    Ok(serde_json::json!({}))
}
