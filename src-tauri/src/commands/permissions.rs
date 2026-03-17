use tauri::AppHandle;

#[tauri::command]
pub async fn get_screen_recording_permission_status(
    _app: AppHandle,
) -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
        let bin_dir = exe_path.parent().ok_or("Cannot find binary directory")?;

        let triple = if cfg!(target_arch = "aarch64") {
            "aarch64-apple-darwin"
        } else {
            "x86_64-apple-darwin"
        };

        let sidecar_name = format!("openscreen-screencapturekit-helper-{}", triple);
        let sidecar_path = bin_dir.join(&sidecar_name);

        if sidecar_path.exists() {
            let output = tokio::process::Command::new(&sidecar_path)
                .arg("--preflight-screen-capture-access")
                .output()
                .await
                .map_err(|e| e.to_string())?;

            let status = String::from_utf8_lossy(&output.stdout).trim().to_lowercase();
            if status == "granted" {
                return Ok("granted".to_string());
            }
            if status == "denied" {
                return Ok("denied".to_string());
            }

            if output.status.success() {
                return Ok("unknown".to_string());
            }

            return Ok("denied".to_string());
        }

        // Fallback: assume we need to check
        Ok("unknown".to_string())
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok("granted".to_string())
    }
}

#[tauri::command]
pub async fn request_screen_recording_permission(
    _app: AppHandle,
) -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        let exe_path = std::env::current_exe().map_err(|e| e.to_string())?;
        let bin_dir = exe_path.parent().ok_or("Cannot find binary directory")?;

        let triple = if cfg!(target_arch = "aarch64") {
            "aarch64-apple-darwin"
        } else {
            "x86_64-apple-darwin"
        };

        let sidecar_name = format!("openscreen-screencapturekit-helper-{}", triple);
        let sidecar_path = bin_dir.join(&sidecar_name);

        if sidecar_path.exists() {
            let output = tokio::process::Command::new(&sidecar_path)
                .arg("--request-screen-capture-access")
                .output()
                .await
                .map_err(|e| e.to_string())?;

            let status = String::from_utf8_lossy(&output.stdout).trim().to_lowercase();
            return Ok(status == "granted");
        }

        Ok(false)
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok(true)
    }
}

#[tauri::command]
pub async fn open_screen_recording_preferences() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        open::that("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn get_accessibility_permission_status() -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        // Use the macOS accessibility API to check status
        let output = tokio::process::Command::new("osascript")
            .args(["-e", "tell application \"System Events\" to return (exists process 1)"])
            .output()
            .await
            .map_err(|e| e.to_string())?;

        if output.status.success() {
            Ok("granted".to_string())
        } else {
            Ok("denied".to_string())
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok("granted".to_string())
    }
}

#[tauri::command]
pub async fn request_accessibility_permission() -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        // Opening accessibility preferences prompts the user
        open::that("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .map_err(|e| e.to_string())?;
        Ok(true)
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok(true)
    }
}

#[tauri::command]
pub async fn open_accessibility_preferences() -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        open::that("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}
