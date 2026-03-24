use tauri::{AppHandle, Emitter};

use super::sidecar::SidecarProcess;

/// Start the native cursor monitor sidecar (macOS only).
/// Emits `cursor-state-changed` events to the frontend.
#[cfg(target_os = "macos")]
pub async fn start_cursor_monitor(app: AppHandle) -> Result<(), String> {
    let sidecar_path = super::sidecar::get_sidecar_path("openscreen-native-cursor-monitor")?;

    let sidecar_str = sidecar_path.to_string_lossy().to_string();
    let mut process = SidecarProcess::spawn(&sidecar_str, &[]).await?;

    // Read stdout lines in a background task
    tokio::spawn(async move {
        loop {
            match process.wait_for_stdout_pattern("STATE:", 60000).await {
                Ok(line) => {
                    // Parse "STATE:<cursor_type>" format
                    if let Some(cursor_type) = line.strip_prefix("STATE:") {
                        let _ = app.emit("cursor-state-changed", cursor_type.trim());
                    }
                }
                Err(_) => break,
            }
        }
    });

    Ok(())
}

#[cfg(not(target_os = "macos"))]
pub async fn start_cursor_monitor(_app: AppHandle) -> Result<(), String> {
    // Cursor monitoring via sidecar is only available on macOS
    Ok(())
}
