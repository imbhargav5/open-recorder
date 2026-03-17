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
