use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::process::{Child, ChildStdout, Command};

pub struct SidecarProcess {
    child: Child,
    stdout_lines: Option<Lines<BufReader<ChildStdout>>>,
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

        Ok(Self {
            child,
            stdout_lines: Some(stdout_lines),
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

        tokio::time::timeout(timeout, async {
            while let Ok(Some(line)) = lines.next_line().await {
                if line.contains(pattern) {
                    return Ok(line);
                }
            }
            Err("Pattern not found in stdout".to_string())
        })
        .await
        .map_err(|_| format!("Timeout waiting for pattern '{}'", pattern))?
    }

    pub async fn wait_for_close(&mut self) -> Result<i32, String> {
        let status = self
            .child
            .wait()
            .await
            .map_err(|e| e.to_string())?;
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
    { "aarch64-apple-darwin" }
    #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
    { "x86_64-apple-darwin" }
    #[cfg(all(target_os = "windows", target_arch = "x86_64"))]
    { "x86_64-pc-windows-msvc" }
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    { "x86_64-unknown-linux-gnu" }
    #[cfg(not(any(
        all(target_os = "macos", target_arch = "aarch64"),
        all(target_os = "macos", target_arch = "x86_64"),
        all(target_os = "windows", target_arch = "x86_64"),
        all(target_os = "linux", target_arch = "x86_64"),
    )))]
    { "unknown-unknown-unknown" }
}
