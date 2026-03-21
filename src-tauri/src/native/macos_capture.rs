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
