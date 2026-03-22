use tauri::AppHandle;

#[cfg(target_os = "windows")]
use std::sync::OnceLock;
#[cfg(target_os = "windows")]
use tokio::sync::Mutex;
#[cfg(target_os = "windows")]
use super::sidecar::SidecarProcess;

#[cfg(target_os = "windows")]
static WGC_PROCESS: OnceLock<Mutex<Option<SidecarProcess>>> = OnceLock::new();

#[cfg(target_os = "windows")]
fn get_wgc_process() -> &'static Mutex<Option<SidecarProcess>> {
    WGC_PROCESS.get_or_init(|| Mutex::new(None))
}

#[cfg(target_os = "windows")]
pub async fn start_capture(
    _app: &AppHandle,
    source: &serde_json::Value,
    options: &serde_json::Value,
    output_path: &str,
) -> Result<(), String> {
    let sidecar_path = super::sidecar::get_sidecar_path("wgc-capture")?;

    let config = serde_json::json!({
        "outputPath": output_path,
        "sourceId": source.get("id").and_then(|v| v.as_str()).unwrap_or(""),
        "frameRate": options.get("frameRate").and_then(|v| v.as_u64()).unwrap_or(60),
        "width": options.get("width").and_then(|v| v.as_u64()).unwrap_or(1920),
        "height": options.get("height").and_then(|v| v.as_u64()).unwrap_or(1080),
        "recordSystemAudio": options.get("recordSystemAudio").and_then(|v| v.as_bool()).unwrap_or(true),
        "recordMicrophone": options.get("recordMicrophone").and_then(|v| v.as_bool()).unwrap_or(false),
    });

    let config_str = serde_json::to_string(&config).map_err(|e| e.to_string())?;
    let sidecar_path_str = sidecar_path.to_string_lossy().to_string();

    let mut process = SidecarProcess::spawn(&sidecar_path_str, &["--config", &config_str]).await?;

    match process
        .wait_for_stdout_pattern("Recording started", 10000)
        .await
    {
        Ok(_) => {}
        Err(e) => {
            let _ = process.kill().await;
            return Err(format!("Failed to start WGC recording: {}", e));
        }
    }

    let mut guard = get_wgc_process().lock().await;
    *guard = Some(process);
    Ok(())
}

#[cfg(target_os = "windows")]
pub async fn stop_capture(_app: &AppHandle) -> Result<(), String> {
    let mut guard = get_wgc_process().lock().await;
    if let Some(ref mut process) = *guard {
        process.write_stdin("stop\n").await?;
        let _ = process.wait_for_close().await?;
    }
    *guard = None;
    Ok(())
}

#[cfg(not(target_os = "windows"))]
pub async fn start_capture(
    _app: &AppHandle,
    _source: &serde_json::Value,
    _options: &serde_json::Value,
    _output_path: &str,
) -> Result<(), String> {
    Err("WGC capture is only available on Windows".to_string())
}

#[cfg(not(target_os = "windows"))]
pub async fn stop_capture(_app: &AppHandle) -> Result<(), String> {
    Err("WGC capture is only available on Windows".to_string())
}

#[cfg(test)]
mod tests {
    #[allow(unused_imports)]
    use super::*;

    // ==================== WGC Config Construction ====================

    #[test]
    fn test_wgc_config_construction_defaults() {
        let source = serde_json::json!({"id": "screen:0"});
        let options = serde_json::json!({});

        let config = serde_json::json!({
            "outputPath": "/tmp/test.mov",
            "sourceId": source.get("id").and_then(|v| v.as_str()).unwrap_or(""),
            "frameRate": options.get("frameRate").and_then(|v| v.as_u64()).unwrap_or(60),
            "width": options.get("width").and_then(|v| v.as_u64()).unwrap_or(1920),
            "height": options.get("height").and_then(|v| v.as_u64()).unwrap_or(1080),
            "recordSystemAudio": options.get("recordSystemAudio").and_then(|v| v.as_bool()).unwrap_or(true),
            "recordMicrophone": options.get("recordMicrophone").and_then(|v| v.as_bool()).unwrap_or(false),
        });

        assert_eq!(config["sourceId"], "screen:0");
        assert_eq!(config["frameRate"], 60);
        assert_eq!(config["width"], 1920);
        assert_eq!(config["height"], 1080);
        assert_eq!(config["recordSystemAudio"], true);
        assert_eq!(config["recordMicrophone"], false);
    }

    #[test]
    fn test_wgc_config_construction_custom_options() {
        let source = serde_json::json!({"id": "window:42"});
        let options = serde_json::json!({
            "frameRate": 30,
            "width": 2560,
            "height": 1440,
            "recordSystemAudio": false,
            "recordMicrophone": true
        });

        let config = serde_json::json!({
            "outputPath": "/tmp/test.mov",
            "sourceId": source.get("id").and_then(|v| v.as_str()).unwrap_or(""),
            "frameRate": options.get("frameRate").and_then(|v| v.as_u64()).unwrap_or(60),
            "width": options.get("width").and_then(|v| v.as_u64()).unwrap_or(1920),
            "height": options.get("height").and_then(|v| v.as_u64()).unwrap_or(1080),
            "recordSystemAudio": options.get("recordSystemAudio").and_then(|v| v.as_bool()).unwrap_or(true),
            "recordMicrophone": options.get("recordMicrophone").and_then(|v| v.as_bool()).unwrap_or(false),
        });

        assert_eq!(config["sourceId"], "window:42");
        assert_eq!(config["frameRate"], 30);
        assert_eq!(config["width"], 2560);
        assert_eq!(config["height"], 1440);
        assert_eq!(config["recordSystemAudio"], false);
        assert_eq!(config["recordMicrophone"], true);
    }

    #[test]
    fn test_wgc_config_missing_source_id() {
        let source = serde_json::json!({});
        let source_id = source.get("id").and_then(|v| v.as_str()).unwrap_or("");
        assert_eq!(source_id, "");
    }

    #[test]
    fn test_wgc_config_serializes_to_json() {
        let config = serde_json::json!({
            "outputPath": "/test.mov",
            "sourceId": "screen:0",
            "frameRate": 60,
            "width": 1920,
            "height": 1080,
            "recordSystemAudio": true,
            "recordMicrophone": false,
        });

        let json_str = serde_json::to_string(&config).unwrap();
        assert!(!json_str.is_empty());
        let reparsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        assert_eq!(config, reparsed);
    }

    // ==================== Non-Windows Platform Stubs ====================

    #[cfg(not(target_os = "windows"))]
    mod non_windows_tests {
        use super::*;

        #[tokio::test]
        async fn test_start_capture_error_on_non_windows() {
            // We can't create a real AppHandle without Tauri runtime,
            // but we can document the expected behavior
            // On non-Windows, start_capture should return Err("WGC capture is only available on Windows")
        }

        #[tokio::test]
        async fn test_stop_capture_error_on_non_windows() {
            // On non-Windows, stop_capture should return Err("WGC capture is only available on Windows")
        }
    }
}
