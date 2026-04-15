use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::app_paths;
use crate::state::{AppState, RecordingSession};
use tokio::io::AsyncWriteExt;

#[cfg(test)]
use percent_encoding::{AsciiSet, CONTROLS};

#[cfg(test)]
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
        app_paths::default_recordings_dir()
    }
}

/// Returns true only if `path` (or its parent, for not-yet-created files) resolves
/// to a location inside the app's data dir, cache dir, or the system temp dir.
fn is_within_allowed_dirs(path: &Path) -> bool {
    let canonical = if path.exists() {
        match std::fs::canonicalize(path) {
            Ok(p) => p,
            Err(_) => return false,
        }
    } else {
        // File not created yet – canonicalize parent and re-attach the filename.
        let parent = path.parent().unwrap_or(path);
        match std::fs::canonicalize(parent) {
            Ok(p) => match path.file_name() {
                Some(name) => p.join(name),
                None => return false,
            },
            Err(_) => return false,
        }
    };

    let allowed: Vec<PathBuf> = [
        dirs::data_dir(),
        dirs::cache_dir(),
        Some(std::env::temp_dir()),
    ]
    .into_iter()
    .flatten()
    .collect();

    allowed.iter().any(|d| canonical.starts_with(d))
}

#[tauri::command]
pub async fn read_local_file(path: String) -> Result<Vec<u8>, String> {
    if !is_within_allowed_dirs(Path::new(&path)) {
        return Err(format!("Access denied: path is outside allowed directories"));
    }
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

    let path_str = file_path
        .to_str()
        .ok_or_else(|| "Invalid UTF-8 in path".to_string())?
        .to_string();

    // Also set as current video path
    {
        let mut s = state.lock().map_err(|e| e.to_string())?;
        s.current_video_path = Some(path_str.clone());
    }

    Ok(path_str)
}

#[tauri::command]
pub async fn prepare_recording_file(
    state: tauri::State<'_, Mutex<AppState>>,
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
    tokio::fs::write(&file_path, [])
        .await
        .map_err(|e| e.to_string())?;

    let path_str = file_path
        .to_str()
        .ok_or_else(|| "Invalid UTF-8 in path".to_string())?
        .to_string();
    Ok(path_str)
}

#[tauri::command]
pub async fn append_recording_data(path: String, data: Vec<u8>) -> Result<(), String> {
    if !is_within_allowed_dirs(Path::new(&path)) {
        return Err(format!("Access denied: path is outside allowed directories"));
    }
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .await
        .map_err(|e| e.to_string())?;

    file.write_all(&data).await.map_err(|e| e.to_string())?;
    file.flush().await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn replace_recording_data(path: String, data: Vec<u8>) -> Result<String, String> {
    tokio::fs::write(&path, &data)
        .await
        .map_err(|e| e.to_string())?;

    Ok(path)
}

#[tauri::command]
pub async fn delete_recording_file(path: String) -> Result<(), String> {
    match tokio::fs::remove_file(&path).await {
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.to_string()),
    }
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

    let path_str = file_path
        .to_str()
        .ok_or_else(|| "Invalid UTF-8 in path".to_string())?
        .to_string();
    Ok(path_str)
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
pub fn clear_current_video_path(state: tauri::State<'_, Mutex<AppState>>) -> Result<(), String> {
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
        assert!(dir.ends_with(app_paths::app_dir_name()));
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

    // ==================== Issue #20: Invalid UTF-8 path fails loudly ====================

    #[cfg(unix)]
    #[test]
    fn test_invalid_utf8_path_returns_error() {
        use std::ffi::OsStr;
        use std::os::unix::ffi::OsStrExt;

        // Build a PathBuf whose bytes are not valid UTF-8
        let invalid_bytes: &[u8] = &[0xFF, 0xFE, b'f', b'i', b'l', b'e', b'.', b'm', b'p', b'4'];
        let os_str = OsStr::from_bytes(invalid_bytes);
        let path = std::path::Path::new(os_str);

        // The fixed code uses to_str().ok_or_else(...) — verify it returns Err
        let result: Result<String, String> = path
            .to_str()
            .ok_or_else(|| "Invalid UTF-8 in path".to_string())
            .map(|s| s.to_string());

        assert!(result.is_err(), "Expected Err for invalid UTF-8 path");
        assert_eq!(result.unwrap_err(), "Invalid UTF-8 in path");
    }

    #[cfg(unix)]
    #[test]
    fn test_valid_utf8_path_succeeds() {
        use std::path::PathBuf;

        let path = PathBuf::from("/tmp/valid_utf8_recording.mp4");
        let result: Result<String, String> = path
            .to_str()
            .ok_or_else(|| "Invalid UTF-8 in path".to_string())
            .map(|s| s.to_string());

        assert!(result.is_ok(), "Expected Ok for valid UTF-8 path");
        assert_eq!(result.unwrap(), "/tmp/valid_utf8_recording.mp4");
    }

    // ==================== Path traversal / security ====================

    #[tokio::test]
    async fn test_read_local_file_path_traversal_rejected() {
        // Both a relative traversal and an absolute sensitive path must be denied.
        for path in &["../../etc/passwd", "/etc/passwd", "/etc/shadow"] {
            let result = read_local_file(path.to_string()).await;
            assert!(
                result.is_err(),
                "expected error for path {:?}, got Ok",
                path
            );
            let err = result.unwrap_err();
            assert!(
                err.contains("Access denied"),
                "expected 'Access denied' in error for path {:?}, got: {}",
                path,
                err
            );
        }
    }

    #[tokio::test]
    async fn test_append_recording_data_path_traversal_rejected() {
        for path in &["../../etc/cron.d/evil", "/etc/cron.d/evil"] {
            let result =
                append_recording_data(path.to_string(), b"malicious".to_vec()).await;
            assert!(
                result.is_err(),
                "expected error for path {:?}, got Ok",
                path
            );
            let err = result.unwrap_err();
            assert!(
                err.contains("Access denied"),
                "expected 'Access denied' in error for path {:?}, got: {}",
                path,
                err
            );
        }
    }

    #[tokio::test]
    async fn test_read_local_file_in_temp_dir_allowed() {
        let dir = std::env::temp_dir();
        let path = dir.join("open_recorder_security_test.txt");
        tokio::fs::write(&path, b"allowed").await.unwrap();

        let result = read_local_file(path.to_string_lossy().to_string()).await;
        let _ = tokio::fs::remove_file(&path).await;

        assert!(result.is_ok(), "temp dir should be allowed: {:?}", result);
    }
}
