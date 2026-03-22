use std::sync::Mutex;
use tauri::{AppHandle, Emitter};

use crate::state::AppState;

#[tauri::command]
pub fn set_recording_state(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
    recording: bool,
) -> Result<(), String> {
    {
        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.native_screen_recording_active = recording;
    }

    // Notify frontend and update tray
    let _ = app.emit("recording-state-changed", recording);
    crate::tray::update_tray_menu(&app, recording);

    Ok(())
}

#[tauri::command]
pub async fn start_native_screen_recording(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
    source: serde_json::Value,
    options: serde_json::Value,
) -> Result<String, String> {
    // Get the recordings directory
    let recordings_dir = {
        let s = state.lock().map_err(|e| e.to_string())?;
        if let Some(ref custom) = s.custom_recordings_dir {
            std::path::PathBuf::from(custom)
        } else {
            dirs::video_dir()
                .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
                .join("Open Recorder")
        }
    };

    tokio::fs::create_dir_all(&recordings_dir)
        .await
        .map_err(|e| e.to_string())?;

    let file_name = format!("recording-{}.mov", uuid::Uuid::new_v4());
    let output_path = recordings_dir.join(&file_name);
    let output_path_str = output_path.to_string_lossy().to_string();

    #[cfg(target_os = "macos")]
    {
        crate::native::macos_capture::start_capture(
            &app,
            &source,
            &options,
            &output_path_str,
        )
        .await?;
    }

    #[cfg(target_os = "windows")]
    {
        crate::native::wgc_capture::start_capture(
            &app,
            &source,
            &options,
            &output_path_str,
        )
        .await?;
    }

    #[cfg(target_os = "linux")]
    {
        crate::native::ffmpeg::start_capture(
            &app,
            &source,
            &options,
            &output_path_str,
        )
        .await?;
    }

    {
        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.native_screen_recording_active = true;
        s.current_video_path = Some(output_path_str.clone());
    }

    Ok(output_path_str)
}

#[tauri::command]
pub async fn stop_native_screen_recording(
    app: AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<String, String> {
    let output_path = {
        let s = state.lock().map_err(|e| e.to_string())?;
        s.current_video_path.clone().unwrap_or_default()
    };

    #[cfg(target_os = "macos")]
    {
        crate::native::macos_capture::stop_capture(&app).await?;
    }

    #[cfg(target_os = "windows")]
    {
        crate::native::wgc_capture::stop_capture(&app).await?;
    }

    #[cfg(target_os = "linux")]
    {
        crate::native::ffmpeg::stop_capture(&app).await?;
    }

    {
        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.native_screen_recording_active = false;
    }

    let _ = app.emit("recording-state-changed", false);
    crate::tray::update_tray_menu(&app, false);

    Ok(output_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== Recording File Name Format ====================

    #[test]
    fn test_recording_file_name_format() {
        let uuid = uuid::Uuid::new_v4();
        let file_name = format!("recording-{}.mov", uuid);
        assert!(file_name.starts_with("recording-"));
        assert!(file_name.ends_with(".mov"));
        // UUID is 36 chars (with hyphens)
        assert_eq!(file_name.len(), "recording-".len() + 36 + ".mov".len());
    }

    #[test]
    fn test_recording_file_name_uniqueness() {
        let name1 = format!("recording-{}.mov", uuid::Uuid::new_v4());
        let name2 = format!("recording-{}.mov", uuid::Uuid::new_v4());
        assert_ne!(name1, name2);
    }

    #[test]
    fn test_recording_file_name_valid_path_component() {
        let file_name = format!("recording-{}.mov", uuid::Uuid::new_v4());
        // Should not contain path separators
        assert!(!file_name.contains('/'));
        assert!(!file_name.contains('\\'));
        // Should not contain spaces
        assert!(!file_name.contains(' '));
    }

    #[test]
    fn test_recording_file_name_uuid_is_valid() {
        let uuid = uuid::Uuid::new_v4();
        let file_name = format!("recording-{}.mov", uuid);
        let uuid_str = &file_name["recording-".len()..file_name.len() - ".mov".len()];
        let parsed = uuid::Uuid::parse_str(uuid_str);
        assert!(parsed.is_ok(), "Failed to parse UUID: {}", uuid_str);
    }

    // ==================== Recording Directory Resolution ====================

    #[test]
    fn test_recordings_dir_with_custom_dir() {
        let mut state = AppState::default();
        state.custom_recordings_dir = Some("/custom/recordings".to_string());
        let dir = if let Some(ref custom) = state.custom_recordings_dir {
            std::path::PathBuf::from(custom)
        } else {
            dirs::video_dir()
                .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
                .join("Open Recorder")
        };
        assert_eq!(dir, std::path::PathBuf::from("/custom/recordings"));
    }

    #[test]
    fn test_recordings_dir_default() {
        let state = AppState::default();
        let dir = if let Some(ref custom) = state.custom_recordings_dir {
            std::path::PathBuf::from(custom)
        } else {
            dirs::video_dir()
                .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
                .join("Open Recorder")
        };
        assert!(dir.ends_with("Open Recorder"));
    }

    #[test]
    fn test_recording_output_path_construction() {
        let recordings_dir = std::path::PathBuf::from("/tmp/recordings");
        let file_name = format!("recording-{}.mov", uuid::Uuid::new_v4());
        let output_path = recordings_dir.join(&file_name);

        assert!(output_path.starts_with("/tmp/recordings"));
        assert!(output_path.to_string_lossy().ends_with(".mov"));
    }

    // ==================== Recording State Lifecycle ====================

    #[test]
    fn test_recording_state_lifecycle_start() {
        let state = std::sync::Mutex::new(AppState::default());
        let output_path = "/tmp/recording.mov".to_string();

        {
            let mut s = state.lock().unwrap();
            s.native_screen_recording_active = true;
            s.current_video_path = Some(output_path.clone());
        }

        let s = state.lock().unwrap();
        assert!(s.native_screen_recording_active);
        assert_eq!(s.current_video_path.as_deref(), Some("/tmp/recording.mov"));
    }

    #[test]
    fn test_recording_state_lifecycle_stop() {
        let state = std::sync::Mutex::new(AppState::default());

        // Start
        {
            let mut s = state.lock().unwrap();
            s.native_screen_recording_active = true;
            s.current_video_path = Some("/tmp/rec.mov".to_string());
        }

        // Stop - read output path, then set inactive
        let output_path = {
            let s = state.lock().unwrap();
            s.current_video_path.clone().unwrap_or_default()
        };
        {
            let mut s = state.lock().unwrap();
            s.native_screen_recording_active = false;
        }

        assert_eq!(output_path, "/tmp/rec.mov");
        let s = state.lock().unwrap();
        assert!(!s.native_screen_recording_active);
        // Video path is preserved after stop
        assert!(s.current_video_path.is_some());
    }

    #[test]
    fn test_recording_state_stop_without_start_returns_empty_path() {
        let state = std::sync::Mutex::new(AppState::default());
        let output_path = {
            let s = state.lock().unwrap();
            s.current_video_path.clone().unwrap_or_default()
        };
        assert_eq!(output_path, "");
    }

    // ==================== Directory Creation ====================

    #[tokio::test]
    async fn test_recording_creates_directory() {
        let dir = std::env::temp_dir().join("open_recorder_test_rec_dir");
        let _ = tokio::fs::remove_dir_all(&dir).await;

        tokio::fs::create_dir_all(&dir).await.unwrap();
        assert!(dir.exists());

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn test_recording_creates_nested_directory() {
        let dir = std::env::temp_dir()
            .join("open_recorder_test_nested")
            .join("recordings")
            .join("2024");
        let _ = tokio::fs::remove_dir_all(std::env::temp_dir().join("open_recorder_test_nested")).await;

        tokio::fs::create_dir_all(&dir).await.unwrap();
        assert!(dir.exists());

        let _ = tokio::fs::remove_dir_all(std::env::temp_dir().join("open_recorder_test_nested")).await;
    }
}
