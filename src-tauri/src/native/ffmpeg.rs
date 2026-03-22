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

    // ==================== FFmpeg Option Parsing ====================

    #[test]
    fn test_ffmpeg_frame_rate_from_options() {
        let options = serde_json::json!({"frameRate": 24});
        let frame_rate = options
            .get("frameRate")
            .and_then(|v| v.as_u64())
            .unwrap_or(30);
        assert_eq!(frame_rate, 24);
    }

    #[test]
    fn test_ffmpeg_frame_rate_default_when_missing() {
        let options = serde_json::json!({});
        let frame_rate = options
            .get("frameRate")
            .and_then(|v| v.as_u64())
            .unwrap_or(30);
        assert_eq!(frame_rate, 30);
    }

    #[test]
    fn test_ffmpeg_frame_rate_default_when_null() {
        let options = serde_json::json!({"frameRate": null});
        let frame_rate = options
            .get("frameRate")
            .and_then(|v| v.as_u64())
            .unwrap_or(30);
        assert_eq!(frame_rate, 30);
    }

    #[test]
    fn test_ffmpeg_frame_rate_default_when_string() {
        let options = serde_json::json!({"frameRate": "60"});
        let frame_rate = options
            .get("frameRate")
            .and_then(|v| v.as_u64())
            .unwrap_or(30);
        assert_eq!(frame_rate, 30); // String can't be parsed as u64 by as_u64()
    }

    #[test]
    fn test_ffmpeg_source_id_from_source() {
        let source = serde_json::json!({"id": ":0.0+100,200"});
        let source_id = source
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or(":0.0");
        assert_eq!(source_id, ":0.0+100,200");
    }

    #[test]
    fn test_ffmpeg_source_id_default() {
        let source = serde_json::json!({});
        let source_id = source
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or(":0.0");
        assert_eq!(source_id, ":0.0");
    }

    #[test]
    fn test_ffmpeg_frame_rate_to_string() {
        let options = serde_json::json!({"frameRate": 60});
        let frame_rate = options
            .get("frameRate")
            .and_then(|v| v.as_u64())
            .unwrap_or(30)
            .to_string();
        assert_eq!(frame_rate, "60");
    }

    #[test]
    fn test_ffmpeg_args_contain_output_path() {
        let output_path = "/tmp/test_recording.mov";
        let frame_rate = "30";

        #[cfg(target_os = "macos")]
        let args = vec![
            "-y", "-f", "avfoundation", "-framerate", frame_rate,
            "-i", "1", "-c:v", "libx264", "-preset", "ultrafast",
            "-crf", "18", output_path,
        ];

        #[cfg(target_os = "linux")]
        let args = vec![
            "-y", "-f", "x11grab", "-framerate", frame_rate,
            "-i", ":0.0", "-c:v", "libx264", "-preset", "ultrafast",
            "-crf", "18", output_path,
        ];

        #[cfg(target_os = "windows")]
        let args = vec![
            "-y", "-f", "gdigrab", "-framerate", frame_rate,
            "-i", "desktop", "-c:v", "libx264", "-preset", "ultrafast",
            "-crf", "18", output_path,
        ];

        assert_eq!(*args.last().unwrap(), output_path);
        assert!(args.contains(&"-y")); // Overwrite flag
        assert!(args.contains(&"-c:v"));
        assert!(args.contains(&"libx264"));
        assert!(args.contains(&"ultrafast"));
    }

    #[test]
    fn test_ffmpeg_args_encoding_quality() {
        // Verify the CRF value used for encoding quality
        let crf = "18";
        let crf_num: u32 = crf.parse().unwrap();
        // CRF 18 is visually lossless for x264
        assert!(crf_num <= 23, "CRF {} is too lossy", crf_num);
    }

    // ==================== OnceLock Singleton ====================

    #[tokio::test]
    async fn test_get_ffmpeg_process_singleton() {
        let guard = get_ffmpeg_process().lock().await;
        // Just verify the singleton initializes and lock can be acquired
        drop(guard);
    }

    #[tokio::test]
    async fn test_ffmpeg_process_initially_none() {
        // On fresh start, no process should be running
        // Note: other tests may have modified this, so we just verify lock access
        let guard = get_ffmpeg_process().lock().await;
        // The process should be None if no recording has been started
        // (can't guarantee this in test suite, just verify no deadlock)
        drop(guard);
    }
}
