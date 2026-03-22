use tauri::AppHandle;
use std::sync::OnceLock;
use tokio::sync::Mutex;

use super::sidecar::SidecarProcess;

static FFMPEG_PROCESS: OnceLock<Mutex<Option<SidecarProcess>>> = OnceLock::new();

fn get_ffmpeg_process() -> &'static Mutex<Option<SidecarProcess>> {
    FFMPEG_PROCESS.get_or_init(|| Mutex::new(None))
}

pub async fn start_capture(
    _app: &AppHandle,
    source: &serde_json::Value,
    options: &serde_json::Value,
    output_path: &str,
) -> Result<(), String> {
    let ffmpeg_path = which_ffmpeg()?;

    let frame_rate = options
        .get("frameRate")
        .and_then(|v| v.as_u64())
        .unwrap_or(30)
        .to_string();

    let _source_id = source
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or(":0.0");

    #[cfg(target_os = "linux")]
    let args = vec![
        "-y",
        "-f", "x11grab",
        "-framerate", &frame_rate,
        "-i", _source_id,
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "18",
        output_path,
    ];

    #[cfg(target_os = "windows")]
    let args = vec![
        "-y",
        "-f", "gdigrab",
        "-framerate", &frame_rate,
        "-i", "desktop",
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "18",
        output_path,
    ];

    #[cfg(target_os = "macos")]
    let args = vec![
        "-y",
        "-f", "avfoundation",
        "-framerate", &frame_rate,
        "-i", "1",
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "18",
        output_path,
    ];

    let process = SidecarProcess::spawn(&ffmpeg_path, &args.iter().map(|s| *s).collect::<Vec<_>>()).await?;

    let mut guard = get_ffmpeg_process().lock().await;
    *guard = Some(process);
    Ok(())
}

pub async fn stop_capture(_app: &AppHandle) -> Result<(), String> {
    let mut guard = get_ffmpeg_process().lock().await;
    if let Some(ref mut process) = *guard {
        // Send 'q' to ffmpeg to stop gracefully
        process.write_stdin("q\n").await?;
        let _ = process.wait_for_close().await?;
    }
    *guard = None;
    Ok(())
}

fn which_ffmpeg() -> Result<String, String> {
    // Check common FFmpeg paths
    let candidates = [
        "ffmpeg",
        "/usr/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/bin/ffmpeg",
    ];

    for candidate in &candidates {
        if std::process::Command::new(candidate)
            .arg("-version")
            .output()
            .is_ok()
        {
            return Ok(candidate.to_string());
        }
    }

    Err("FFmpeg not found. Please install FFmpeg.".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_which_ffmpeg_returns_result() {
        // which_ffmpeg either finds ffmpeg or returns an error
        let result = which_ffmpeg();
        match result {
            Ok(path) => {
                assert!(!path.is_empty());
                assert!(path.contains("ffmpeg"));
            }
            Err(err) => {
                assert_eq!(err, "FFmpeg not found. Please install FFmpeg.");
            }
        }
    }

    #[test]
    fn test_which_ffmpeg_returns_known_path_if_found() {
        let result = which_ffmpeg();
        if let Ok(path) = result {
            let known_paths = [
                "ffmpeg",
                "/usr/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/opt/homebrew/bin/ffmpeg",
            ];
            assert!(
                known_paths.contains(&path.as_str()),
                "Unexpected ffmpeg path: {}",
                path
            );
        }
    }

    #[test]
    fn test_which_ffmpeg_deterministic() {
        let r1 = which_ffmpeg();
        let r2 = which_ffmpeg();
        match (r1, r2) {
            (Ok(p1), Ok(p2)) => assert_eq!(p1, p2),
            (Err(e1), Err(e2)) => assert_eq!(e1, e2),
            _ => panic!("which_ffmpeg returned inconsistent results"),
        }
    }
}
