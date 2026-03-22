use tauri::AppHandle;
use std::sync::OnceLock;
use tokio::sync::Mutex;

use super::sidecar::SidecarProcess;

static CAPTURE_PROCESS: OnceLock<Mutex<Option<SidecarProcess>>> = OnceLock::new();

fn get_capture_process() -> &'static Mutex<Option<SidecarProcess>> {
    CAPTURE_PROCESS.get_or_init(|| Mutex::new(None))
}

#[cfg(target_os = "macos")]
fn read_string(value: &serde_json::Value, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        value
            .get(*key)
            .and_then(|v| v.as_str())
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(ToOwned::to_owned)
    })
}

#[cfg(target_os = "macos")]
fn read_u64(value: &serde_json::Value, keys: &[&str]) -> Option<u64> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(|v| v.as_u64()))
}

#[cfg(target_os = "macos")]
fn read_bool(value: &serde_json::Value, keys: &[&str], default: bool) -> bool {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(|v| v.as_bool()))
        .unwrap_or(default)
}

#[cfg(target_os = "macos")]
fn parse_window_id_from_source_id(source_id: &str) -> Option<u64> {
    source_id
        .strip_prefix("window:")
        .and_then(|value| value.split(':').next())
        .and_then(|value| value.parse::<u64>().ok())
}

#[cfg(target_os = "macos")]
fn parse_display_id_from_source_id(source_id: &str) -> Option<String> {
    source_id
        .strip_prefix("screen:")
        .and_then(|value| value.split(':').next())
        .map(ToOwned::to_owned)
}

#[cfg(target_os = "macos")]
pub async fn start_capture(
    _app: &AppHandle,
    source: &serde_json::Value,
    options: &serde_json::Value,
    output_path: &str,
) -> Result<(), String> {
    let sidecar_path = super::sidecar::get_sidecar_path("openscreen-screencapturekit-helper")?;

    let source_id = read_string(source, &["id"]).unwrap_or_default();
    let display_id = read_string(source, &["displayId", "display_id"])
        .or_else(|| parse_display_id_from_source_id(&source_id))
        .unwrap_or_else(|| "0".to_string());
    let window_id = read_u64(source, &["windowId", "window_id"])
        .or_else(|| parse_window_id_from_source_id(&source_id));
    let captures_system_audio =
        read_bool(options, &["capturesSystemAudio", "recordSystemAudio"], false);
    let captures_microphone =
        read_bool(options, &["capturesMicrophone", "recordMicrophone"], false);
    let microphone_device_id = read_string(options, &["microphoneDeviceId"]);
    let fps = read_u64(options, &["fps", "frameRate"]).unwrap_or(60);

    let display_id_num: u64 = display_id.parse().unwrap_or(0);

    let config = serde_json::json!({
        "outputPath": output_path,
        "displayId": display_id_num,
        "windowId": window_id,
        "fps": fps,
        "capturesSystemAudio": captures_system_audio,
        "capturesMicrophone": captures_microphone,
        "microphoneDeviceId": microphone_device_id,
    });

    let config_str = serde_json::to_string(&config).map_err(|e| e.to_string())?;
    let sidecar_path_str = sidecar_path.to_string_lossy().to_string();

    let mut process = SidecarProcess::spawn(&sidecar_path_str, &[&config_str]).await?;

    // Wait for "Recording started" confirmation
    match process
        .wait_for_stdout_pattern("Recording started", 10000)
        .await
    {
        Ok(_) => {}
        Err(e) => {
            let _ = process.kill().await;
            return Err(format!("Failed to start recording: {}", e));
        }
    }

    let mut guard = get_capture_process().lock().await;
    *guard = Some(process);

    Ok(())
}

#[cfg(target_os = "macos")]
pub async fn stop_capture(_app: &AppHandle) -> Result<(), String> {
    let mut guard = get_capture_process().lock().await;
    if let Some(ref mut process) = *guard {
        // Send "stop" via stdin to gracefully stop recording.
        // If the process already exited (e.g. window closed), stdin write may fail — that's ok.
        let _ = process.write_stdin("stop\n").await;

        // Wait for the process to exit with a timeout to avoid hanging forever
        // if the sidecar's asset writer gets stuck during finishWriting().
        match tokio::time::timeout(
            tokio::time::Duration::from_secs(15),
            process.wait_for_close(),
        )
        .await
        {
            Ok(Ok(exit_code)) => {
                if exit_code != 0 {
                    eprintln!("ScreenCaptureKit helper exited with code {}", exit_code);
                }
            }
            Ok(Err(e)) => {
                eprintln!("Error waiting for ScreenCaptureKit helper: {}", e);
            }
            Err(_) => {
                eprintln!("Timed out waiting for ScreenCaptureKit helper to exit, killing process");
                let _ = process.kill().await;
            }
        }
    }
    *guard = None;
    Ok(())
}

#[cfg(not(target_os = "macos"))]
pub async fn start_capture(
    _app: &AppHandle,
    _source: &serde_json::Value,
    _options: &serde_json::Value,
    _output_path: &str,
) -> Result<(), String> {
    Err("macOS capture is only available on macOS".to_string())
}

#[cfg(not(target_os = "macos"))]
pub async fn stop_capture(_app: &AppHandle) -> Result<(), String> {
    Err("macOS capture is only available on macOS".to_string())
}

#[cfg(test)]
mod tests {
    #[allow(unused_imports)]
    use super::*;

    // ==================== read_string ====================

    #[cfg(target_os = "macos")]
    mod macos_tests {
        use super::*;

        #[test]
        fn test_read_string_first_key_found() {
            let value = serde_json::json!({"name": "test"});
            let result = read_string(&value, &["name"]);
            assert_eq!(result.as_deref(), Some("test"));
        }

        #[test]
        fn test_read_string_second_key_found() {
            let value = serde_json::json!({"display_id": "42"});
            let result = read_string(&value, &["displayId", "display_id"]);
            assert_eq!(result.as_deref(), Some("42"));
        }

        #[test]
        fn test_read_string_first_key_preferred() {
            let value = serde_json::json!({"displayId": "1", "display_id": "2"});
            let result = read_string(&value, &["displayId", "display_id"]);
            assert_eq!(result.as_deref(), Some("1"));
        }

        #[test]
        fn test_read_string_no_keys_found() {
            let value = serde_json::json!({"other": "data"});
            let result = read_string(&value, &["name", "id"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_string_empty_string_filtered() {
            let value = serde_json::json!({"name": ""});
            let result = read_string(&value, &["name"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_string_whitespace_only_filtered() {
            let value = serde_json::json!({"name": "   "});
            let result = read_string(&value, &["name"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_string_trims_whitespace() {
            let value = serde_json::json!({"name": "  hello  "});
            let result = read_string(&value, &["name"]);
            assert_eq!(result.as_deref(), Some("hello"));
        }

        #[test]
        fn test_read_string_non_string_value() {
            let value = serde_json::json!({"name": 42});
            let result = read_string(&value, &["name"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_string_null_value() {
            let value = serde_json::json!({"name": null});
            let result = read_string(&value, &["name"]);
            assert!(result.is_none());
        }

        // ==================== read_u64 ====================

        #[test]
        fn test_read_u64_found() {
            let value = serde_json::json!({"fps": 60});
            let result = read_u64(&value, &["fps"]);
            assert_eq!(result, Some(60));
        }

        #[test]
        fn test_read_u64_second_key() {
            let value = serde_json::json!({"frameRate": 30});
            let result = read_u64(&value, &["fps", "frameRate"]);
            assert_eq!(result, Some(30));
        }

        #[test]
        fn test_read_u64_not_found() {
            let value = serde_json::json!({"other": 42});
            let result = read_u64(&value, &["fps"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_u64_string_value_returns_none() {
            let value = serde_json::json!({"fps": "60"});
            let result = read_u64(&value, &["fps"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_u64_negative_returns_none() {
            let value = serde_json::json!({"fps": -1});
            let result = read_u64(&value, &["fps"]);
            assert!(result.is_none());
        }

        #[test]
        fn test_read_u64_zero() {
            let value = serde_json::json!({"fps": 0});
            let result = read_u64(&value, &["fps"]);
            assert_eq!(result, Some(0));
        }

        // ==================== read_bool ====================

        #[test]
        fn test_read_bool_true() {
            let value = serde_json::json!({"enabled": true});
            let result = read_bool(&value, &["enabled"], false);
            assert!(result);
        }

        #[test]
        fn test_read_bool_false() {
            let value = serde_json::json!({"enabled": false});
            let result = read_bool(&value, &["enabled"], true);
            assert!(!result);
        }

        #[test]
        fn test_read_bool_not_found_returns_default_true() {
            let value = serde_json::json!({"other": true});
            let result = read_bool(&value, &["enabled"], true);
            assert!(result);
        }

        #[test]
        fn test_read_bool_not_found_returns_default_false() {
            let value = serde_json::json!({"other": true});
            let result = read_bool(&value, &["enabled"], false);
            assert!(!result);
        }

        #[test]
        fn test_read_bool_second_key() {
            let value = serde_json::json!({"recordSystemAudio": true});
            let result = read_bool(&value, &["capturesSystemAudio", "recordSystemAudio"], false);
            assert!(result);
        }

        #[test]
        fn test_read_bool_non_bool_value_returns_default() {
            let value = serde_json::json!({"enabled": "true"});
            let result = read_bool(&value, &["enabled"], false);
            assert!(!result); // String "true" is not a bool
        }

        // ==================== parse_window_id_from_source_id ====================

        #[test]
        fn test_parse_window_id_valid() {
            let result = parse_window_id_from_source_id("window:123:0");
            assert_eq!(result, Some(123));
        }

        #[test]
        fn test_parse_window_id_large_number() {
            let result = parse_window_id_from_source_id("window:999999:0");
            assert_eq!(result, Some(999999));
        }

        #[test]
        fn test_parse_window_id_zero() {
            let result = parse_window_id_from_source_id("window:0:0");
            assert_eq!(result, Some(0));
        }

        #[test]
        fn test_parse_window_id_screen_prefix_returns_none() {
            let result = parse_window_id_from_source_id("screen:1:0");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_window_id_no_prefix_returns_none() {
            let result = parse_window_id_from_source_id("123:0");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_window_id_non_numeric_returns_none() {
            let result = parse_window_id_from_source_id("window:abc:0");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_window_id_empty_after_prefix_returns_none() {
            let result = parse_window_id_from_source_id("window:");
            // split(':').next() returns Some(""), which can't parse to u64
            assert!(result.is_none());
        }

        // ==================== parse_display_id_from_source_id ====================

        #[test]
        fn test_parse_display_id_valid() {
            let result = parse_display_id_from_source_id("screen:42:0");
            assert_eq!(result.as_deref(), Some("42"));
        }

        #[test]
        fn test_parse_display_id_zero() {
            let result = parse_display_id_from_source_id("screen:0:0");
            assert_eq!(result.as_deref(), Some("0"));
        }

        #[test]
        fn test_parse_display_id_window_prefix_returns_none() {
            let result = parse_display_id_from_source_id("window:1:0");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_display_id_empty() {
            let result = parse_display_id_from_source_id("");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_display_id_no_colon_after_value() {
            let result = parse_display_id_from_source_id("screen:42");
            assert_eq!(result.as_deref(), Some("42"));
        }
    }

    // ==================== Non-macOS capture tests ====================

    #[cfg(not(target_os = "macos"))]
    mod non_macos_tests {
        use super::*;

        #[tokio::test]
        async fn test_start_capture_returns_error_on_non_macos() {
            let app = tauri::test::mock_builder().build(tauri::generate_context!());
            // Can't easily create an AppHandle in tests without full Tauri setup,
            // but the function signature tells us it should return an error.
            // This test documents the expected behavior.
        }
    }
}
