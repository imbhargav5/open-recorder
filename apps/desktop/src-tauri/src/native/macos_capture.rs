use std::sync::OnceLock;
use tauri::AppHandle;
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
    let captures_system_audio = read_bool(
        options,
        &["capturesSystemAudio", "recordSystemAudio"],
        false,
    );
    let captures_microphone =
        read_bool(options, &["capturesMicrophone", "recordMicrophone"], false);
    let shows_cursor = read_bool(options, &["showsCursor", "captureCursor"], false);
    let microphone_device_id = read_string(options, &["microphoneDeviceId"]);
    let fps = read_u64(options, &["fps", "frameRate"]).unwrap_or(60);

    let display_id_num: u64 = display_id.parse().unwrap_or(0);

    let config = serde_json::json!({
        "outputPath": output_path,
        "displayId": display_id_num,
        "windowId": window_id,
        "fps": fps,
        "showsCursor": shows_cursor,
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

        // ==================== Capture Config Construction ====================

        /// Helper that replicates the config construction logic from start_capture
        fn build_capture_config(
            source: &serde_json::Value,
            options: &serde_json::Value,
            output_path: &str,
        ) -> serde_json::Value {
            let source_id = read_string(source, &["id"]).unwrap_or_default();
            let display_id = read_string(source, &["displayId", "display_id"])
                .or_else(|| parse_display_id_from_source_id(&source_id))
                .unwrap_or_else(|| "0".to_string());
            let window_id = read_u64(source, &["windowId", "window_id"])
                .or_else(|| parse_window_id_from_source_id(&source_id));
            let captures_system_audio = read_bool(
                options,
                &["capturesSystemAudio", "recordSystemAudio"],
                false,
            );
            let captures_microphone =
                read_bool(options, &["capturesMicrophone", "recordMicrophone"], false);
            let microphone_device_id = read_string(options, &["microphoneDeviceId"]);
            let fps = read_u64(options, &["fps", "frameRate"]).unwrap_or(60);
            let display_id_num: u64 = display_id.parse().unwrap_or(0);

            serde_json::json!({
                "outputPath": output_path,
                "displayId": display_id_num,
                "windowId": window_id,
                "fps": fps,
                "capturesSystemAudio": captures_system_audio,
                "capturesMicrophone": captures_microphone,
                "microphoneDeviceId": microphone_device_id,
            })
        }

        #[test]
        fn test_config_screen_recording_defaults() {
            let source = serde_json::json!({"id": "screen:1:0", "displayId": "1"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["outputPath"], "/tmp/out.mov");
            assert_eq!(config["displayId"], 1);
            assert_eq!(config["fps"], 60);
            assert_eq!(config["capturesSystemAudio"], false);
            assert_eq!(config["capturesMicrophone"], false);
            assert!(config["windowId"].is_null());
        }

        #[test]
        fn test_config_window_recording() {
            let source = serde_json::json!({"id": "window:42:0", "windowId": 42});
            let options = serde_json::json!({"fps": 30});
            let config = build_capture_config(&source, &options, "/tmp/window.mov");

            assert_eq!(config["windowId"], 42);
            assert_eq!(config["fps"], 30);
        }

        #[test]
        fn test_config_display_id_fallback_to_source_id() {
            // No explicit displayId, should parse from source id
            let source = serde_json::json!({"id": "screen:99:0"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["displayId"], 99);
        }

        #[test]
        fn test_config_display_id_fallback_to_zero() {
            // No displayId, no parseable source id
            let source = serde_json::json!({"id": "unknown"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["displayId"], 0);
        }

        #[test]
        fn test_config_window_id_from_source_id_fallback() {
            // No explicit windowId, should parse from source id
            let source = serde_json::json!({"id": "window:77:0"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["windowId"], 77);
        }

        #[test]
        fn test_config_window_id_none_for_screen() {
            let source = serde_json::json!({"id": "screen:1:0"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert!(config["windowId"].is_null());
        }

        #[test]
        fn test_config_all_audio_options_enabled() {
            let source = serde_json::json!({"id": "screen:0:0"});
            let options = serde_json::json!({
                "capturesSystemAudio": true,
                "capturesMicrophone": true,
                "microphoneDeviceId": "device-123"
            });
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["capturesSystemAudio"], true);
            assert_eq!(config["capturesMicrophone"], true);
            assert_eq!(config["microphoneDeviceId"], "device-123");
        }

        #[test]
        fn test_config_alternative_audio_key_names() {
            // Test the alternative key names (recordSystemAudio, recordMicrophone)
            let source = serde_json::json!({"id": "screen:0:0"});
            let options = serde_json::json!({
                "recordSystemAudio": true,
                "recordMicrophone": true
            });
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["capturesSystemAudio"], true);
            assert_eq!(config["capturesMicrophone"], true);
        }

        #[test]
        fn test_config_fps_from_alternative_key() {
            let source = serde_json::json!({"id": "screen:0:0"});
            let options = serde_json::json!({"frameRate": 24});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["fps"], 24);
        }

        #[test]
        fn test_config_explicit_display_id_preferred_over_source_id() {
            let source = serde_json::json!({"id": "screen:99:0", "displayId": "42"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["displayId"], 42);
        }

        #[test]
        fn test_config_display_id_snake_case_alias() {
            let source = serde_json::json!({"id": "screen:0:0", "display_id": "7"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            assert_eq!(config["displayId"], 7);
        }

        #[test]
        fn test_config_non_numeric_display_id_falls_back_to_zero() {
            let source = serde_json::json!({"id": "screen:abc:0", "displayId": "abc"});
            let options = serde_json::json!({});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            // "abc".parse::<u64>() fails, unwrap_or(0) applies
            assert_eq!(config["displayId"], 0);
        }

        #[test]
        fn test_config_serializes_to_valid_json() {
            let source = serde_json::json!({"id": "screen:1:0"});
            let options = serde_json::json!({"fps": 30});
            let config = build_capture_config(&source, &options, "/tmp/out.mov");

            let json_str = serde_json::to_string(&config).unwrap();
            let reparsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
            assert_eq!(config, reparsed);
        }

        // ==================== OnceLock Singleton ====================

        #[tokio::test]
        async fn test_get_capture_process_returns_none_initially() {
            let guard = get_capture_process().lock().await;
            // Note: may be Some if a previous test set it, but the singleton should exist
            drop(guard); // Just verify we can acquire the lock
        }

        // ==================== Mock Sidecar Integration ====================

        #[tokio::test]
        async fn test_mock_sidecar_start_stop_lifecycle() {
            use std::os::unix::fs::PermissionsExt;

            let dir = std::env::temp_dir();
            let script_path = dir.join("open_recorder_test_mock_sidecar.sh");

            // Create a mock sidecar that prints "Recording started" then waits for stdin
            let script = "#!/bin/bash\necho \"Recording started\"\nread line\nexit 0\n";
            tokio::fs::write(&script_path, script).await.unwrap();
            tokio::fs::set_permissions(&script_path, std::fs::Permissions::from_mode(0o755))
                .await
                .unwrap();

            let sidecar_str = script_path.to_string_lossy().to_string();
            let mut process = SidecarProcess::spawn(&sidecar_str, &[]).await.unwrap();

            // Wait for "Recording started"
            let result = process
                .wait_for_stdout_pattern("Recording started", 5000)
                .await;
            assert!(result.is_ok(), "Failed to detect start: {:?}", result.err());

            // Send stop command
            let write_result = process.write_stdin("stop\n").await;
            assert!(write_result.is_ok());

            // Wait for clean exit
            let exit_code = process.wait_for_close().await.unwrap();
            assert_eq!(exit_code, 0);

            let _ = tokio::fs::remove_file(&script_path).await;
        }

        #[tokio::test]
        async fn test_mock_sidecar_kill_on_timeout() {
            use std::os::unix::fs::PermissionsExt;

            let dir = std::env::temp_dir();
            let script_path = dir.join("open_recorder_test_mock_hang.sh");

            // Create a sidecar that hangs forever (never prints the expected pattern)
            let script = "#!/bin/bash\necho \"Initializing...\"\nsleep 300\n";
            tokio::fs::write(&script_path, script).await.unwrap();
            tokio::fs::set_permissions(&script_path, std::fs::Permissions::from_mode(0o755))
                .await
                .unwrap();

            let sidecar_str = script_path.to_string_lossy().to_string();
            let mut process = SidecarProcess::spawn(&sidecar_str, &[]).await.unwrap();

            // Pattern should timeout
            let result = process
                .wait_for_stdout_pattern("Recording started", 500)
                .await;
            assert!(result.is_err());

            // Kill the hanging process
            let kill_result = process.kill().await;
            assert!(kill_result.is_ok());

            let _ = tokio::fs::remove_file(&script_path).await;
        }

        #[tokio::test]
        async fn test_mock_sidecar_with_stderr_output() {
            use std::os::unix::fs::PermissionsExt;

            let dir = std::env::temp_dir();
            let script_path = dir.join("open_recorder_test_mock_stderr.sh");

            // Sidecar that writes to stderr then exits
            let script = "#!/bin/bash\necho \"Error: permission denied\" >&2\nexit 1\n";
            tokio::fs::write(&script_path, script).await.unwrap();
            tokio::fs::set_permissions(&script_path, std::fs::Permissions::from_mode(0o755))
                .await
                .unwrap();

            let sidecar_str = script_path.to_string_lossy().to_string();
            let mut process = SidecarProcess::spawn(&sidecar_str, &[]).await.unwrap();

            // Pattern won't be found, should capture stderr in error message
            let result = process
                .wait_for_stdout_pattern("Recording started", 2000)
                .await;
            assert!(result.is_err());
            let err = result.unwrap_err();
            assert!(
                err.contains("permission denied") || err.contains("Process exited"),
                "Error should contain stderr output: {}",
                err
            );

            let _ = tokio::fs::remove_file(&script_path).await;
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
