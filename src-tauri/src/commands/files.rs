use std::path::PathBuf;
use std::sync::Mutex;

use crate::state::{AppState, RecordingSession};

fn get_recordings_dir(state: &AppState) -> PathBuf {
    if let Some(ref custom) = state.custom_recordings_dir {
        PathBuf::from(custom)
    } else {
        dirs::video_dir()
            .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
            .join("Open Recorder")
    }
}

#[tauri::command]
pub async fn read_local_file(path: String) -> Result<Vec<u8>, String> {
    tokio::fs::read(&path).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn store_recorded_video(
    state: tauri::State<'_, Mutex<AppState>>,
    video_data: Vec<u8>,
    file_name: String,
) -> Result<String, String> {
    let recordings_dir = {
        let s = state.lock().map_err(|e| e.to_string())?;
        get_recordings_dir(&s)
    };

    tokio::fs::create_dir_all(&recordings_dir)
        .await
        .map_err(|e| e.to_string())?;

    let file_path = recordings_dir.join(&file_name);
    tokio::fs::write(&file_path, &video_data)
        .await
        .map_err(|e| e.to_string())?;

    let path_str = file_path.to_string_lossy().to_string();

    // Also set as current video path
    {
        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.current_video_path = Some(path_str.clone());
    }

    Ok(path_str)
}

#[tauri::command]
pub async fn store_recording_asset(
    state: tauri::State<'_, Mutex<AppState>>,
    asset_data: Vec<u8>,
    file_name: String,
) -> Result<String, String> {
    let recordings_dir = {
        let s = state.lock().map_err(|e| e.to_string())?;
        get_recordings_dir(&s)
    };

    tokio::fs::create_dir_all(&recordings_dir)
        .await
        .map_err(|e| e.to_string())?;

    let file_path = recordings_dir.join(&file_name);
    tokio::fs::write(&file_path, &asset_data)
        .await
        .map_err(|e| e.to_string())?;

    Ok(file_path.to_string_lossy().to_string())
}

#[tauri::command]
pub fn get_recorded_video_path(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<String>, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    Ok(s.current_video_path.clone())
}

#[tauri::command]
pub fn set_current_video_path(
    state: tauri::State<'_, Mutex<AppState>>,
    path: String,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.current_video_path = Some(path);
    Ok(())
}

#[tauri::command]
pub fn get_current_video_path(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<String>, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    Ok(s.current_video_path.clone())
}

#[tauri::command]
pub fn clear_current_video_path(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.current_video_path = None;
    Ok(())
}

#[tauri::command]
pub fn get_current_recording_session(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<RecordingSession>, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    Ok(s.current_recording_session.clone())
}

#[tauri::command]
pub fn set_current_recording_session(
    state: tauri::State<'_, Mutex<AppState>>,
    session: RecordingSession,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.current_recording_session = Some(session);
    Ok(())
}
