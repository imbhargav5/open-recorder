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
