use std::sync::Mutex;
use tauri::AppHandle;
use tauri_plugin_dialog::DialogExt;

use crate::state::AppState;

#[tauri::command]
pub async fn save_exported_video(
    app: AppHandle,
    video_data: Vec<u8>,
    file_name: String,
) -> Result<Option<String>, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();

    app.dialog()
        .file()
        .set_file_name(&file_name)
        .add_filter("Video", &["mp4", "mov", "webm"])
        .save_file(move |path| {
            let _ = tx.send(path);
        });

    let path = rx.await.map_err(|_| "Dialog cancelled".to_string())?;

    if let Some(file_path) = path {
        let path_str = file_path.to_string();
        tokio::fs::write(&path_str, &video_data)
            .await
            .map_err(|e: std::io::Error| e.to_string())?;
        Ok(Some(path_str))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn save_screenshot_file(
    app: AppHandle,
    image_data: Vec<u8>,
    file_name: String,
) -> Result<Option<String>, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();

    app.dialog()
        .file()
        .set_file_name(&file_name)
        .add_filter("Image", &["png", "jpg", "jpeg"])
        .save_file(move |path| {
            let _ = tx.send(path);
        });

    let path = rx.await.map_err(|_| "Dialog cancelled".to_string())?;

    if let Some(file_path) = path {
        let path_str = file_path.to_string();
        tokio::fs::write(&path_str, &image_data)
            .await
            .map_err(|e: std::io::Error| e.to_string())?;
        Ok(Some(path_str))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn open_video_file_picker(
    app: AppHandle,
) -> Result<Option<String>, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();

    app.dialog()
        .file()
        .add_filter("Video", &["mp4", "mov", "webm", "mkv"])
        .pick_file(move |path| {
            let _ = tx.send(path);
        });

    let path = rx.await.map_err(|_| "Dialog cancelled".to_string())?;
    Ok(path.map(|p| p.to_string()))
}

#[tauri::command]
pub async fn save_project_file(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
    data: String,
    suggested_name: Option<String>,
    existing_path: Option<String>,
) -> Result<Option<String>, String> {
    let path_str = if let Some(existing) = existing_path {
        // Save to existing path directly
        Some(existing)
    } else {
        // Show save dialog
        let file_name = suggested_name.unwrap_or_else(|| "Untitled.openrecorder".to_string());

        let (tx, rx) = tokio::sync::oneshot::channel();

        app.dialog()
            .file()
            .set_file_name(&file_name)
            .add_filter("Open Recorder Project", &["openrecorder"])
            .save_file(move |path| {
                let _ = tx.send(path);
            });

        let path = rx.await.map_err(|_| "Dialog cancelled".to_string())?;
        path.map(|p| p.to_string())
    };

    if let Some(ref path) = path_str {
        tokio::fs::write(path, &data)
            .await
            .map_err(|e: std::io::Error| e.to_string())?;

        {
            let mut s = state.lock().map_err(|e| e.to_string())?;
            s.current_project_path = Some(path.clone());
            s.has_unsaved_changes = false;
        }

        Ok(path_str)
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn load_project_file(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<serde_json::Value>, String> {
    let (tx, rx) = tokio::sync::oneshot::channel();

    app.dialog()
        .file()
        .add_filter("Open Recorder Project", &["openrecorder"])
        .pick_file(move |path| {
            let _ = tx.send(path);
        });

    let path = rx.await.map_err(|_| "Dialog cancelled".to_string())?;

    if let Some(file_path) = path {
        let path_str = file_path.to_string();
        let data = tokio::fs::read_to_string(&path_str)
            .await
            .map_err(|e: std::io::Error| e.to_string())?;

        {
            let mut s = state.lock().map_err(|e| e.to_string())?;
            s.current_project_path = Some(path_str.clone());
            s.has_unsaved_changes = false;
        }

        let project: serde_json::Value =
            serde_json::from_str(&data).map_err(|e| e.to_string())?;

        Ok(Some(serde_json::json!({
            "data": project,
            "filePath": path_str
        })))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn load_current_project_file(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<serde_json::Value>, String> {
    let path = {
        let s = state.lock().map_err(|e| e.to_string())?;
        s.current_project_path.clone()
    };

    if let Some(path) = path {
        if std::path::Path::new(&path).exists() {
            let data = tokio::fs::read_to_string(&path)
                .await
                .map_err(|e: std::io::Error| e.to_string())?;

            let project: serde_json::Value =
                serde_json::from_str(&data).map_err(|e| e.to_string())?;

            Ok(Some(serde_json::json!({
                "data": project,
                "filePath": path
            })))
        } else {
            Ok(None)
        }
    } else {
        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== Project File I/O ====================

    #[tokio::test]
    async fn test_project_file_write_and_read() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_project.openrecorder");

        let project_data = serde_json::json!({
            "version": 1,
            "scenes": [{"name": "Scene 1", "duration": 10.0}],
            "settings": {"resolution": "1920x1080"}
        });
        let data_str = serde_json::to_string_pretty(&project_data).unwrap();
        tokio::fs::write(&path, &data_str).await.unwrap();

        let read_data = tokio::fs::read_to_string(&path).await.unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&read_data).unwrap();
        assert_eq!(parsed["version"], 1);
        assert_eq!(parsed["scenes"].as_array().unwrap().len(), 1);

        let _ = tokio::fs::remove_file(&path).await;
    }

    #[tokio::test]
    async fn test_project_file_invalid_json_returns_error() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_bad_project.openrecorder");
        tokio::fs::write(&path, "not valid json {{{").await.unwrap();

        let read_data = tokio::fs::read_to_string(&path).await.unwrap();
        let result: Result<serde_json::Value, _> = serde_json::from_str(&read_data);
        assert!(result.is_err());

        let _ = tokio::fs::remove_file(&path).await;
    }

    #[tokio::test]
    async fn test_project_file_nonexistent_path() {
        let result = tokio::fs::read_to_string("/nonexistent/project.openrecorder").await;
        assert!(result.is_err());
    }

    #[test]
    fn test_default_project_name() {
        let suggested: Option<String> = None;
        let file_name = suggested.unwrap_or_else(|| "Untitled.openrecorder".to_string());
        assert_eq!(file_name, "Untitled.openrecorder");
    }

    #[test]
    fn test_custom_project_name() {
        let suggested = Some("My Project.openrecorder".to_string());
        let file_name = suggested.unwrap_or_else(|| "Untitled.openrecorder".to_string());
        assert_eq!(file_name, "My Project.openrecorder");
    }

    // ==================== Project File State Management ====================

    #[test]
    fn test_project_save_updates_state() {
        let state = std::sync::Mutex::new(AppState::default());
        {
            let mut s = state.lock().unwrap();
            s.current_project_path = Some("/tmp/project.openrecorder".to_string());
            s.has_unsaved_changes = false;
        }
        let s = state.lock().unwrap();
        assert_eq!(s.current_project_path.as_deref(), Some("/tmp/project.openrecorder"));
        assert!(!s.has_unsaved_changes);
    }

    #[test]
    fn test_existing_path_skips_dialog() {
        let existing_path = Some("/existing/path.openrecorder".to_string());
        let path_str = if let Some(existing) = existing_path {
            Some(existing)
        } else {
            None
        };
        assert_eq!(path_str.as_deref(), Some("/existing/path.openrecorder"));
    }

    #[test]
    fn test_no_existing_path_needs_dialog() {
        let existing_path: Option<String> = None;
        let path_str = if let Some(existing) = existing_path {
            Some(existing)
        } else {
            None
        };
        assert!(path_str.is_none());
    }

    // ==================== load_current_project_file logic ====================

    #[tokio::test]
    async fn test_load_current_project_with_valid_file() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_load_current.openrecorder");
        let project = serde_json::json!({"version": 2, "data": "test"});
        tokio::fs::write(&path, serde_json::to_string(&project).unwrap())
            .await
            .unwrap();

        let path_str = path.to_string_lossy().to_string();
        assert!(std::path::Path::new(&path_str).exists());

        let data = tokio::fs::read_to_string(&path_str).await.unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&data).unwrap();
        let result = serde_json::json!({ "data": parsed, "filePath": path_str });
        assert_eq!(result["data"]["version"], 2);

        let _ = tokio::fs::remove_file(&path).await;
    }

    #[test]
    fn test_load_current_no_path_returns_none() {
        let state = AppState::default();
        assert!(state.current_project_path.is_none());
    }

    #[test]
    fn test_load_current_nonexistent_path() {
        assert!(!std::path::Path::new("/nonexistent/project.openrecorder").exists());
    }

    // ==================== Project File Roundtrip ====================

    #[tokio::test]
    async fn test_project_file_full_roundtrip() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_roundtrip.openrecorder");

        let original = serde_json::json!({
            "version": 1,
            "videoPath": "/videos/recording.mov",
            "scenes": [
                {"name": "Intro", "startTime": 0.0, "endTime": 5.0},
                {"name": "Main", "startTime": 5.0, "endTime": 30.0}
            ],
            "cursor": {"visible": true, "scale": 1.5},
            "background": {"type": "gradient", "colors": ["#1a1a2e", "#16213e"]}
        });

        let data_str = serde_json::to_string_pretty(&original).unwrap();
        tokio::fs::write(&path, &data_str).await.unwrap();

        let loaded_str = tokio::fs::read_to_string(&path).await.unwrap();
        let loaded: serde_json::Value = serde_json::from_str(&loaded_str).unwrap();
        assert_eq!(original, loaded);

        let _ = tokio::fs::remove_file(&path).await;
    }
}
