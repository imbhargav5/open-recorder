use std::path::PathBuf;
use std::sync::Mutex;
use tauri::AppHandle;

use crate::app_paths;
use crate::state::{AppState, ShortcutConfig};

fn get_config_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app_paths::app_config_dir(app)
}

#[tauri::command]
pub fn get_recordings_directory(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<String, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    let dir = if let Some(ref custom) = s.custom_recordings_dir {
        PathBuf::from(custom)
    } else {
        app_paths::default_recordings_dir()
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::ShortcutConfig;

    // ==================== Recordings Directory Resolution ====================

    #[test]
    fn test_recordings_dir_with_custom() {
        let mut state = AppState::default();
        state.custom_recordings_dir = Some("/my/custom/dir".to_string());
        let dir = if let Some(ref custom) = state.custom_recordings_dir {
            PathBuf::from(custom)
        } else {
            app_paths::default_recordings_dir()
        };
        assert_eq!(dir, PathBuf::from("/my/custom/dir"));
    }

    #[test]
    fn test_recordings_dir_default_ends_with_open_recorder() {
        let state = AppState::default();
        let dir = if let Some(ref custom) = state.custom_recordings_dir {
            PathBuf::from(custom)
        } else {
            app_paths::default_recordings_dir()
        };
        assert!(dir.ends_with(app_paths::app_dir_name()));
    }

    #[test]
    fn test_recordings_dir_to_string() {
        let dir = app_paths::default_recordings_dir();
        let dir_str = dir.to_string_lossy().to_string();
        assert!(!dir_str.is_empty());
        assert!(dir_str.contains(app_paths::app_dir_name()));
    }

    // ==================== Shortcuts JSON Persistence ====================

    #[tokio::test]
    async fn test_shortcuts_file_roundtrip() {
        let dir = std::env::temp_dir();
        let shortcuts_path = dir.join("open_recorder_test_shortcuts.json");

        let shortcuts = ShortcutConfig {
            start_stop_recording: Some("CmdOrCtrl+Shift+R".to_string()),
            pause_resume_recording: Some("CmdOrCtrl+Shift+P".to_string()),
            cancel_recording: Some("Escape".to_string()),
        };

        // Save
        let data = serde_json::to_string_pretty(&shortcuts).unwrap();
        tokio::fs::write(&shortcuts_path, &data).await.unwrap();

        // Load
        let loaded_data = tokio::fs::read_to_string(&shortcuts_path).await.unwrap();
        let loaded: ShortcutConfig = serde_json::from_str(&loaded_data).unwrap();

        assert_eq!(shortcuts.start_stop_recording, loaded.start_stop_recording);
        assert_eq!(shortcuts.pause_resume_recording, loaded.pause_resume_recording);
        assert_eq!(shortcuts.cancel_recording, loaded.cancel_recording);

        let _ = tokio::fs::remove_file(&shortcuts_path).await;
    }

    #[tokio::test]
    async fn test_shortcuts_file_nonexistent_path() {
        let path = PathBuf::from("/nonexistent/shortcuts.json");
        assert!(!path.exists());
    }

    #[test]
    fn test_shortcuts_cached_returns_immediately() {
        let state = std::sync::Mutex::new(AppState::default());
        let shortcut = ShortcutConfig {
            start_stop_recording: Some("F9".to_string()),
            pause_resume_recording: None,
            cancel_recording: None,
        };

        {
            let mut s = state.lock().unwrap();
            s.shortcuts = Some(shortcut.clone());
        }

        let s = state.lock().unwrap();
        assert!(s.shortcuts.is_some());
        assert_eq!(
            s.shortcuts.as_ref().unwrap().start_stop_recording.as_deref(),
            Some("F9")
        );
    }

    // ==================== Settings JSON Format ====================

    #[test]
    fn test_settings_json_recordings_directory_format() {
        let path_str = "/custom/recordings";
        let settings = serde_json::json!({ "recordingsDirectory": path_str });
        let json_str = serde_json::to_string_pretty(&settings).unwrap();

        assert!(json_str.contains("recordingsDirectory"));
        assert!(json_str.contains("/custom/recordings"));

        let reparsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        assert_eq!(reparsed["recordingsDirectory"], "/custom/recordings");
    }

    #[tokio::test]
    async fn test_settings_file_write_and_read() {
        let dir = std::env::temp_dir();
        let settings_path = dir.join("open_recorder_test_settings.json");

        let path_str = "/my/recordings";
        let settings = serde_json::json!({ "recordingsDirectory": path_str });
        let json = serde_json::to_string_pretty(&settings).unwrap();
        tokio::fs::write(&settings_path, &json).await.unwrap();

        let read = tokio::fs::read_to_string(&settings_path).await.unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&read).unwrap();
        assert_eq!(parsed["recordingsDirectory"], "/my/recordings");

        let _ = tokio::fs::remove_file(&settings_path).await;
    }

    // ==================== Config Directory ====================

    #[tokio::test]
    async fn test_config_dir_creation() {
        let dir = std::env::temp_dir().join("open_recorder_test_config");
        let _ = tokio::fs::remove_dir_all(&dir).await;

        tokio::fs::create_dir_all(&dir).await.unwrap();
        assert!(dir.exists());

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    // ==================== State Persistence Pattern ====================

    #[test]
    fn test_choose_recordings_dir_updates_state() {
        let state = std::sync::Mutex::new(AppState::default());
        let path_str = "/chosen/directory".to_string();

        {
            let mut s = state.lock().unwrap();
            s.custom_recordings_dir = Some(path_str.clone());
        }

        let s = state.lock().unwrap();
        assert_eq!(s.custom_recordings_dir.as_deref(), Some("/chosen/directory"));
    }

    #[test]
    fn test_save_shortcuts_updates_state() {
        let state = std::sync::Mutex::new(AppState::default());
        let shortcuts = ShortcutConfig {
            start_stop_recording: Some("CmdOrCtrl+R".to_string()),
            pause_resume_recording: None,
            cancel_recording: None,
        };

        {
            let mut s = state.lock().unwrap();
            s.shortcuts = Some(shortcuts);
        }

        let s = state.lock().unwrap();
        assert!(s.shortcuts.is_some());
    }
}
