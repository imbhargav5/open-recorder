use std::path::PathBuf;
use std::sync::Mutex;
use tauri::AppHandle;
use tauri::Manager;

use crate::state::{AppState, ShortcutConfig};

fn get_config_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app.path().app_config_dir().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn get_recordings_directory(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<String, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    let dir = if let Some(ref custom) = s.custom_recordings_dir {
        PathBuf::from(custom)
    } else {
        dirs::video_dir()
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
            .join("Open Recorder")
    };
    Ok(dir.to_string_lossy().to_string())
}

#[tauri::command]
pub async fn choose_recordings_directory(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;

    let (tx, rx) = tokio::sync::oneshot::channel();

    app.dialog()
        .file()
        .pick_folder(move |path| {
            let _ = tx.send(path);
        });

    let folder = rx.await.map_err(|_| "Dialog cancelled".to_string())?;

    if let Some(file_path) = folder {
        let path_str = file_path.to_string();

        {
            let mut s = state.lock().map_err(|e| e.to_string())?;
            s.custom_recordings_dir = Some(path_str.clone());
        }

        // Persist the choice
        let config_dir = get_config_dir(&app)?;
        tokio::fs::create_dir_all(&config_dir)
            .await
            .map_err(|e: std::io::Error| e.to_string())?;
        let settings_path = config_dir.join("settings.json");
        let settings = serde_json::json!({ "recordingsDirectory": path_str });
        tokio::fs::write(&settings_path, serde_json::to_string_pretty(&settings).unwrap())
            .await
            .map_err(|e: std::io::Error| e.to_string())?;

        Ok(Some(path_str))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn get_shortcuts(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<ShortcutConfig>, String> {
    // Check cached first
    {
        let s = state.lock().map_err(|e| e.to_string())?;
        if s.shortcuts.is_some() {
            return Ok(s.shortcuts.clone());
        }
    }

    // Load from file
    let config_dir = get_config_dir(&app)?;
    let shortcuts_path = config_dir.join("shortcuts.json");

    if shortcuts_path.exists() {
        let data = tokio::fs::read_to_string(&shortcuts_path)
            .await
            .map_err(|e: std::io::Error| e.to_string())?;
        let shortcuts: ShortcutConfig =
            serde_json::from_str(&data).map_err(|e| e.to_string())?;

        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.shortcuts = Some(shortcuts.clone());

        Ok(Some(shortcuts))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn save_shortcuts(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
    shortcuts: ShortcutConfig,
) -> Result<(), String> {
    let config_dir = get_config_dir(&app)?;
    tokio::fs::create_dir_all(&config_dir)
        .await
        .map_err(|e: std::io::Error| e.to_string())?;

    let shortcuts_path = config_dir.join("shortcuts.json");
    let data = serde_json::to_string_pretty(&shortcuts).map_err(|e| e.to_string())?;
    tokio::fs::write(&shortcuts_path, data)
        .await
        .map_err(|e: std::io::Error| e.to_string())?;

    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.shortcuts = Some(shortcuts);

    Ok(())
}
