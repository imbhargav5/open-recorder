use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::process::{Child, ChildStderr, ChildStdout, Command};

pub struct SidecarProcess {
    child: Child,
    stdout_lines: Option<Lines<BufReader<ChildStdout>>>,
    stderr: Option<ChildStderr>,
}

impl SidecarProcess {
    pub async fn spawn(path: &str, args: &[&str]) -> Result<Self, String> {
        let mut child = Command::new(path)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Failed to spawn sidecar '{}': {}", path, e))?;

        let stdout = child.stdout.take().ok_or("stdout not available")?;
        let stdout_lines = BufReader::new(stdout).lines();
        let stderr = child.stderr.take();

        Ok(Self {
            child,
            stdout_lines: Some(stdout_lines),
            stderr,
        })
    }

    pub async fn write_stdin(&mut self, data: &str) -> Result<(), String> {
        if let Some(ref mut stdin) = self.child.stdin {
            stdin
                .write_all(data.as_bytes())
                .await
                .map_err(|e| e.to_string())?;
            stdin.flush().await.map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    pub async fn wait_for_stdout_pattern(
        &mut self,
        pattern: &str,
        timeout_ms: u64,
    ) -> Result<String, String> {
        let lines = self
            .stdout_lines
            .as_mut()
            .ok_or("stdout reader not available")?;

        let timeout = tokio::time::Duration::from_millis(timeout_ms);

        let result = tokio::time::timeout(timeout, async {
            while let Ok(Some(line)) = lines.next_line().await {
                if line.contains(pattern) {
                    return Ok(line);
                }
            }
            Err("Pattern not found in stdout".to_string())
        })
        .await
        .map_err(|_| format!("Timeout waiting for pattern '{}'", pattern))?;

        // If the pattern was not found (process exited), try to read stderr
        // for a more informative error message
        if let Err(_) = &result {
            let stderr_output = self.read_stderr().await;
            if !stderr_output.is_empty() {
                return Err(format!("Process exited with error: {}", stderr_output));
            }
        }

        result
    }

    async fn read_stderr(&mut self) -> String {
        let Some(stderr) = self.stderr.take() else {
            return String::new();
        };

        let mut buffer = Vec::new();
        let mut reader = tokio::io::BufReader::new(stderr);

        // Use a short timeout to avoid blocking if the process is still running
        let read_result = tokio::time::timeout(
            tokio::time::Duration::from_millis(500),
            reader.read_to_end(&mut buffer),
        )
        .await;

        match read_result {
            Ok(Ok(_)) => String::from_utf8_lossy(&buffer).trim().to_string(),
            _ => String::new(),
        }
    }

    pub async fn wait_for_close(&mut self) -> Result<i32, String> {
        let status = self.child.wait().await.map_err(|e| e.to_string())?;
        Ok(status.code().unwrap_or(-1))
    }

    pub async fn kill(&mut self) -> Result<(), String> {
        self.child.kill().await.map_err(|e| e.to_string())
    }
}

/// Get the path to a sidecar binary, respecting Tauri's naming convention.
pub fn get_sidecar_path(name: &str) -> Result<std::path::PathBuf, String> {
    let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
    let bin_dir = exe_path
        .parent()
        .ok_or("Cannot determine binary directory")?;

    let triple = get_target_triple();
    let sidecar_name = format!("{}-{}", name, triple);
    let path = bin_dir.join(&sidecar_name);

    if path.exists() {
        Ok(path)
    } else {
        // Also try without triple suffix (for dev mode)
        let fallback = bin_dir.join(name);
        if fallback.exists() {
            Ok(fallback)
        } else {
            Err(format!(
                "Sidecar '{}' not found at {:?} or {:?}",
                name, path, fallback
            ))
        }
    }
}

fn get_target_triple() -> &'static str {
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    {
        "aarch64-apple-darwin"
    }
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    {
        "x86_64-apple-darwin"
    }
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    {
        "x86_64-pc-windows-msvc"
    }
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        "x86_64-unknown-linux-gnu"
    }
    #[cfg(not(any(
        all(target_os = "macos", target_arch = "aarch64"),
        all(target_os = "macos", target_arch = "x86_64"),
        all(target_os = "windows", target_arch = "x86_64"),
        all(target_os = "linux", target_arch = "x86_64"),
    )))]
    {
        "unknown-unknown-unknown"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== get_target_triple ====================

    #[test]
    fn test_get_target_triple_is_not_empty() {
        let triple = get_target_triple();
        assert!(!triple.is_empty());
    }

    #[test]
    fn test_get_target_triple_contains_os() {
        let triple = get_target_triple();
        let has_known_os = triple.contains("apple-darwin")
            || triple.contains("windows")
            || triple.contains("linux")
            || triple == "unknown-unknown-unknown";
        assert!(has_known_os, "Unexpected triple: {}", triple);
    }

    #[test]
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    fn test_get_target_triple_macos_arm() {
        assert_eq!(get_target_triple(), "aarch64-apple-darwin");
    }

    #[test]
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    fn test_get_target_triple_macos_x86() {
        assert_eq!(get_target_triple(), "x86_64-apple-darwin");
    }

    #[test]
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    fn test_get_target_triple_windows() {
        assert_eq!(get_target_triple(), "x86_64-pc-windows-msvc");
    }

    #[test]
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    fn test_get_target_triple_linux() {
        assert_eq!(get_target_triple(), "x86_64-unknown-linux-gnu");
    }

    #[test]
    fn test_get_target_triple_deterministic() {
        assert_eq!(get_target_triple(), get_target_triple());
    }

    // ==================== get_sidecar_path ====================

    #[test]
    fn test_get_sidecar_path_nonexistent_sidecar() {
        // Neither the triple-suffixed nor the plain name should exist
        let result = get_sidecar_path("nonexistent-sidecar-binary-12345");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.contains("not found"), "Error: {}", err);
    }

    #[test]
    fn test_get_sidecar_path_error_contains_sidecar_name() {
        let result = get_sidecar_path("my-test-sidecar");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("my-test-sidecar"));
    }

    #[test]
    fn test_get_sidecar_path_builds_triple_suffixed_name() {
        // We can't easily test success (no sidecar present in test env),
        // but we can verify the error message mentions the expected path format
        let result = get_sidecar_path("test-helper");
        if let Err(err) = result {
            let triple = get_target_triple();
            let expected_name = format!("test-helper-{}", triple);
            assert!(
                err.contains(&expected_name),
                "Error should mention {}: {}",
                expected_name,
                err
            );
        }
    }

    // ==================== SidecarProcess ====================

    #[tokio::test]
    async fn test_sidecar_spawn_valid_command() {
        let result = SidecarProcess::spawn("echo", &["hello"]).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_sidecar_spawn_invalid_command() {
        let result = SidecarProcess::spawn("/nonexistent/binary", &[]).await;
        assert!(result.is_err());
        match result {
            Err(err) => assert!(err.contains("Failed to spawn sidecar")),
            Ok(_) => panic!("Expected error"),
        }
    }

    #[tokio::test]
    async fn test_sidecar_spawn_error_contains_path() {
        let result = SidecarProcess::spawn("/fake/path/to/sidecar", &[]).await;
        match result {
            Err(err) => assert!(err.contains("/fake/path/to/sidecar")),
            Ok(_) => panic!("Expected error"),
        }
    }

    #[tokio::test]
    async fn test_sidecar_wait_for_close_echo() {
        let mut proc = SidecarProcess::spawn("echo", &["done"]).await.unwrap();
        let exit_code = proc.wait_for_close().await.unwrap();
        assert_eq!(exit_code, 0);
    }

    #[tokio::test]
    async fn test_sidecar_wait_for_close_false_command() {
        let mut proc = SidecarProcess::spawn("false", &[]).await.unwrap();
        let exit_code = proc.wait_for_close().await.unwrap();
        assert_ne!(exit_code, 0);
    }

    #[tokio::test]
    async fn test_sidecar_kill() {
        let mut proc = SidecarProcess::spawn("sleep", &["60"]).await.unwrap();
        let result = proc.kill().await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_sidecar_wait_for_stdout_pattern_found() {
        // Use printf to output a line with our pattern
        let mut proc = SidecarProcess::spawn("echo", &["Recording started"])
            .await
            .unwrap();
        let result = proc
            .wait_for_stdout_pattern("Recording started", 5000)
            .await;
        assert!(result.is_ok());
        assert!(result.unwrap().contains("Recording started"));
    }

    #[tokio::test]
    async fn test_sidecar_wait_for_stdout_pattern_timeout() {
        // sleep produces no stdout, so pattern will timeout
        let mut proc = SidecarProcess::spawn("sleep", &["60"]).await.unwrap();
        let result = proc.wait_for_stdout_pattern("will-never-appear", 100).await;
        let _ = proc.kill().await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Timeout"));
    }

    #[tokio::test]
    async fn test_sidecar_wait_for_stdout_pattern_process_exits_without_match() {
        // echo outputs "hello" then exits - pattern "xyz" won't be found
        let mut proc = SidecarProcess::spawn("echo", &["hello"]).await.unwrap();
        let result = proc.wait_for_stdout_pattern("xyz", 2000).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_sidecar_write_stdin() {
        // cat reads from stdin and echoes to stdout
        let mut proc = SidecarProcess::spawn("cat", &[]).await.unwrap();
        let write_result = proc.write_stdin("test input\n").await;
        assert!(write_result.is_ok());
        let _ = proc.kill().await;
    }

    // ==================== Target triple format ====================

    #[test]
    fn test_get_target_triple_contains_two_hyphens() {
        let triple = get_target_triple();
        let hyphen_count = triple.chars().filter(|&c| c == '-').count();
        assert!(
            hyphen_count >= 2,
            "Triple '{}' should contain at least 2 hyphens (arch-vendor-os), found {}",
            triple,
            hyphen_count
        );
    }

    #[test]
    fn test_get_target_triple_no_whitespace() {
        let triple = get_target_triple();
        assert!(
            !triple.contains(' ') && !triple.contains('\t') && !triple.contains('\n'),
            "Triple should not contain whitespace: '{}'",
            triple
        );
    }

    #[test]
    fn test_get_target_triple_all_lowercase() {
        let triple = get_target_triple();
        assert_eq!(
            triple,
            triple.to_lowercase(),
            "Triple should be all lowercase: '{}'",
            triple
        );
    }

    // ==================== get_sidecar_path error details ====================

    #[test]
    fn test_get_sidecar_path_error_mentions_both_paths() {
        let result = get_sidecar_path("nonexistent-test-binary");
        if let Err(err) = result {
            // Should mention the triple-suffixed path
            let triple = get_target_triple();
            assert!(
                err.contains(&format!("nonexistent-test-binary-{}", triple)),
                "Error should mention triple-suffixed path: {}",
                err
            );
            // Should also mention the plain fallback path
            assert!(
                err.contains("nonexistent-test-binary"),
                "Error should mention plain fallback path: {}",
                err
            );
        }
    }

    #[test]
    fn test_get_sidecar_path_error_with_special_chars_in_name() {
        let result = get_sidecar_path("my-app_v2.0");
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(
            err.contains("my-app_v2.0"),
            "Error should contain the exact sidecar name: {}",
            err
        );
    }

    #[tokio::test]
    async fn test_sidecar_write_stdin_then_read_pattern() {
        let mut proc = SidecarProcess::spawn("cat", &[]).await.unwrap();
        proc.write_stdin("MAGIC_PATTERN\n").await.unwrap();
        let result = proc.wait_for_stdout_pattern("MAGIC_PATTERN", 2000).await;
        let _ = proc.kill().await;
        assert!(result.is_ok());
    }
}
