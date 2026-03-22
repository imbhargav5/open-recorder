use std::path::PathBuf;
use std::sync::Mutex;

use crate::state::{AppState, RecordingSession};
use percent_encoding::{AsciiSet, CONTROLS, utf8_percent_encode};

const URL_COMPONENT_ENCODE_SET: &AsciiSet = &CONTROLS
    .add(b' ')
    .add(b'"')
    .add(b'#')
    .add(b'$')
    .add(b'%')
    .add(b'&')
    .add(b'+')
    .add(b',')
    .add(b'/')
    .add(b':')
    .add(b';')
    .add(b'<')
    .add(b'=')
    .add(b'>')
    .add(b'?')
    .add(b'@')
    .add(b'[')
    .add(b'\\')
    .add(b']')
    .add(b'^')
    .add(b'`')
    .add(b'{')
    .add(b'|')
    .add(b'}');

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
pub fn resolve_media_playback_url(path: String) -> Result<String, String> {
    if path.trim().is_empty() {
        return Err("Path is required".to_string());
    }

    let encoded = utf8_percent_encode(&path, URL_COMPONENT_ENCODE_SET).to_string();

    #[cfg(target_os = "windows")]
    {
        Ok(format!("http://asset.localhost/{encoded}"))
    }

    #[cfg(not(target_os = "windows"))]
    {
        Ok(format!("asset://localhost/{encoded}"))
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use percent_encoding::utf8_percent_encode;

    // ==================== get_recordings_dir ====================

    #[test]
    fn test_get_recordings_dir_with_custom_dir() {
        let mut state = AppState::default();
        state.custom_recordings_dir = Some("/custom/recordings".to_string());
        let dir = get_recordings_dir(&state);
        assert_eq!(dir, PathBuf::from("/custom/recordings"));
    }

    #[test]
    fn test_get_recordings_dir_without_custom_dir() {
        let state = AppState::default();
        let dir = get_recordings_dir(&state);
        // Should end with "Open Recorder" regardless of platform
        assert!(dir.ends_with("Open Recorder"));
    }

    #[test]
    fn test_get_recordings_dir_custom_dir_overrides_default() {
        let mut state = AppState::default();
        let default_dir = get_recordings_dir(&state);

        state.custom_recordings_dir = Some("/my/custom/path".to_string());
        let custom_dir = get_recordings_dir(&state);

        assert_ne!(default_dir, custom_dir);
        assert_eq!(custom_dir, PathBuf::from("/my/custom/path"));
    }

    // ==================== URL encoding ====================

    #[test]
    fn test_url_encode_simple_path() {
        let path = "/Users/test/video.mov";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%2F")); // '/' is encoded
        assert!(encoded.contains("video.mov"));
    }

    #[test]
    fn test_url_encode_path_with_spaces() {
        let path = "/Users/test/my video.mov";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%20")); // space is encoded
        assert!(!encoded.contains(' '));
    }

    #[test]
    fn test_url_encode_path_with_special_chars() {
        let path = "/path/with#special&chars=test";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%23")); // '#' encoded
        assert!(encoded.contains("%26")); // '&' encoded
        assert!(encoded.contains("%3D")); // '=' encoded
    }

    #[test]
    fn test_url_encode_path_with_percent() {
        let path = "/path/50%done";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%25")); // '%' itself is encoded
    }

    #[test]
    fn test_url_encode_preserves_alphanumeric() {
        let path = "abcdefghijklmnopqrstuvwxyz0123456789";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert_eq!(encoded, path); // No encoding needed
    }

    #[test]
    fn test_url_encode_unicode_path() {
        let path = "/Users/用户/视频.mov";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        // Unicode chars should be percent-encoded as UTF-8 bytes
        assert!(!encoded.contains("用户"));
    }

    #[test]
    fn test_url_encode_encodes_question_mark() {
        let path = "/path/file?query";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%3F"));
    }

    #[test]
    fn test_url_encode_encodes_at_sign() {
        let path = "/path/user@host";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%40"));
    }

    #[test]
    fn test_url_encode_encodes_brackets() {
        let path = "/path/[file]";
        let encoded = utf8_percent_encode(path, URL_COMPONENT_ENCODE_SET).to_string();
        assert!(encoded.contains("%5B"));
        assert!(encoded.contains("%5D"));
    }

    // ==================== resolve_media_playback_url ====================

    #[test]
    fn test_resolve_media_playback_url_empty_path_returns_error() {
        let result = resolve_media_playback_url("".to_string());
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Path is required");
    }

    #[test]
    fn test_resolve_media_playback_url_whitespace_only_returns_error() {
        let result = resolve_media_playback_url("   ".to_string());
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Path is required");
    }

    #[test]
    fn test_resolve_media_playback_url_valid_path() {
        let result = resolve_media_playback_url("/path/to/video.mov".to_string());
        assert!(result.is_ok());
        let url = result.unwrap();
        // Should contain the encoded path
        assert!(url.contains("video.mov"));
    }

    #[test]
    fn test_resolve_media_playback_url_platform_scheme() {
        let result = resolve_media_playback_url("/video.mov".to_string());
        let url = result.unwrap();
        #[cfg(target_os = "windows")]
        assert!(url.starts_with("http://asset.localhost/"));
        #[cfg(not(target_os = "windows"))]
        assert!(url.starts_with("asset://localhost/"));
    }

    #[test]
    fn test_resolve_media_playback_url_encodes_spaces() {
        let result = resolve_media_playback_url("/my path/video file.mov".to_string());
        let url = result.unwrap();
        assert!(!url.contains(' '));
        assert!(url.contains("%20"));
    }

    // ==================== File I/O ====================

    #[tokio::test]
    async fn test_read_local_file_existing_file() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_read.txt");
        tokio::fs::write(&path, b"hello world").await.unwrap();

        let result = read_local_file(path.to_string_lossy().to_string()).await;
        let _ = tokio::fs::remove_file(&path).await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), b"hello world");
    }

    #[tokio::test]
    async fn test_read_local_file_nonexistent_file() {
        let result = read_local_file("/nonexistent/path/to/file.txt".to_string()).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_read_local_file_empty_file() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_empty.txt");
        tokio::fs::write(&path, b"").await.unwrap();

        let result = read_local_file(path.to_string_lossy().to_string()).await;
        let _ = tokio::fs::remove_file(&path).await;

        assert!(result.is_ok());
        assert!(result.unwrap().is_empty());
    }

    #[tokio::test]
    async fn test_read_local_file_binary_content() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_test_binary.bin");
        let data: Vec<u8> = (0..=255).collect();
        tokio::fs::write(&path, &data).await.unwrap();

        let result = read_local_file(path.to_string_lossy().to_string()).await;
        let _ = tokio::fs::remove_file(&path).await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), data);
    }
}
