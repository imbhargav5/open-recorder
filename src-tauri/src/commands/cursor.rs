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

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper: replicate the telemetry path construction logic for testing
    fn telemetry_path_for_video(video_path: &str) -> String {
        format!(
            "{}.cursor.json",
            video_path
                .trim_end_matches(".mov")
                .trim_end_matches(".mp4")
                .trim_end_matches(".webm")
        )
    }

    #[test]
    fn test_telemetry_path_from_mov() {
        let path = telemetry_path_for_video("/path/to/recording.mov");
        assert_eq!(path, "/path/to/recording.cursor.json");
    }

    #[test]
    fn test_telemetry_path_from_mp4() {
        let path = telemetry_path_for_video("/path/to/recording.mp4");
        assert_eq!(path, "/path/to/recording.cursor.json");
    }

    #[test]
    fn test_telemetry_path_from_webm() {
        let path = telemetry_path_for_video("/path/to/recording.webm");
        assert_eq!(path, "/path/to/recording.cursor.json");
    }

    #[test]
    fn test_telemetry_path_no_recognized_extension() {
        let path = telemetry_path_for_video("/path/to/recording.avi");
        assert_eq!(path, "/path/to/recording.avi.cursor.json");
    }

    #[test]
    fn test_telemetry_path_no_extension() {
        let path = telemetry_path_for_video("/path/to/recording");
        assert_eq!(path, "/path/to/recording.cursor.json");
    }

    #[test]
    fn test_telemetry_path_double_extension_mov_mp4() {
        // trim_end_matches strips sequentially: .mov → .mp4 → result
        let path = telemetry_path_for_video("/path/to/file.mp4.mov");
        assert_eq!(path, "/path/to/file.cursor.json");
    }

    #[test]
    fn test_telemetry_path_with_spaces() {
        let path = telemetry_path_for_video("/path/to/my recording.mov");
        assert_eq!(path, "/path/to/my recording.cursor.json");
    }

    #[test]
    fn test_telemetry_path_empty_string() {
        let path = telemetry_path_for_video("");
        assert_eq!(path, ".cursor.json");
    }

    #[tokio::test]
    async fn test_get_cursor_telemetry_missing_file_returns_fallback() {
        let result = get_cursor_telemetry("/nonexistent/path/video.mov".to_string()).await;
        assert!(result.is_ok());
        let value = result.unwrap();
        assert_eq!(value["samples"], serde_json::json!([]));
        assert_eq!(value["clicks"], serde_json::json!([]));
    }

    #[tokio::test]
    async fn test_get_cursor_telemetry_valid_json_file() {
        let dir = std::env::temp_dir();
        let video_path = dir.join("open_recorder_test_cursor.mov");
        let telemetry_path = dir.join("open_recorder_test_cursor.cursor.json");

        let telemetry_data = serde_json::json!({
            "samples": [{"x": 100, "y": 200, "t": 0}],
            "clicks": [{"x": 100, "y": 200, "t": 0, "type": "left"}]
        });
        tokio::fs::write(&telemetry_path, serde_json::to_string(&telemetry_data).unwrap())
            .await
            .unwrap();

        let result = get_cursor_telemetry(video_path.to_string_lossy().to_string()).await;
        let _ = tokio::fs::remove_file(&telemetry_path).await;

        assert!(result.is_ok());
        let value = result.unwrap();
        assert!(value["samples"].is_array());
        assert_eq!(value["samples"].as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn test_get_cursor_telemetry_invalid_json_returns_error() {
        let dir = std::env::temp_dir();
        let video_path = dir.join("open_recorder_test_bad_cursor.mov");
        let telemetry_path = dir.join("open_recorder_test_bad_cursor.cursor.json");

        tokio::fs::write(&telemetry_path, "not valid json {{{")
            .await
            .unwrap();

        let result = get_cursor_telemetry(video_path.to_string_lossy().to_string()).await;
        let _ = tokio::fs::remove_file(&telemetry_path).await;

        assert!(result.is_err());
    }
}
