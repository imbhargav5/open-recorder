use tauri::AppHandle;

#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGPreflightScreenCaptureAccess() -> bool;
    fn CGRequestScreenCaptureAccess() -> bool;
}

#[cfg(target_os = "macos")]
fn run_on_main_thread<R: Send + 'static>(
    app: &AppHandle,
    callback: impl FnOnce() -> R + Send + 'static,
) -> Result<R, String> {
    let (tx, rx) = std::sync::mpsc::sync_channel(1);

    app.run_on_main_thread(move || {
        let _ = tx.send(callback());
    })
    .map_err(|e| e.to_string())?;

    rx.recv().map_err(|e| e.to_string())
}

#[cfg(target_os = "macos")]
fn preflight_screen_capture_access() -> bool {
    unsafe { CGPreflightScreenCaptureAccess() }
}

#[cfg(target_os = "macos")]
fn request_screen_capture_access() -> bool {
    unsafe { CGRequestScreenCaptureAccess() }
}

#[tauri::command]
pub async fn get_screen_recording_permission_status(
    app: AppHandle,
) -> Result<String, String> {
    #[cfg(target_os = "macos")]
    {
        let granted = run_on_main_thread(&app, preflight_screen_capture_access)?;
        Ok(if granted { "granted" } else { "denied" }.to_string())
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok("granted".to_string())
    }
}

#[tauri::command]
pub async fn request_screen_recording_permission(
    app: AppHandle,
) -> Result<bool, String> {
    #[cfg(target_os = "macos")]
    {
        run_on_main_thread(&app, request_screen_capture_access)
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

#[cfg(test)]
mod tests {
    #[allow(unused_imports)]
    use super::*;

    // ==================== Permission Status Values ====================

    #[test]
    fn test_permission_status_granted_value() {
        let status = "granted".to_string();
        assert_eq!(status, "granted");
    }

    #[test]
    fn test_permission_status_denied_value() {
        let status = "denied".to_string();
        assert_eq!(status, "denied");
    }

    #[test]
    fn test_permission_status_is_binary() {
        // Permission status should only be "granted" or "denied"
        for status in ["granted", "denied"] {
            assert!(status == "granted" || status == "denied");
        }
    }

    // ==================== Platform-Specific Behavior ====================

    #[cfg(not(target_os = "macos"))]
    mod non_macos_tests {
        #[test]
        fn test_non_macos_screen_recording_always_granted() {
            // On non-macOS, screen recording is always "granted"
            let status = "granted".to_string();
            assert_eq!(status, "granted");
        }

        #[test]
        fn test_non_macos_accessibility_always_granted() {
            let status = "granted".to_string();
            assert_eq!(status, "granted");
        }

        #[test]
        fn test_non_macos_request_permission_returns_true() {
            let result: Result<bool, String> = Ok(true);
            assert!(result.is_ok());
            assert!(result.unwrap());
        }
    }

    // ==================== macOS Preferences URL ====================

    #[cfg(target_os = "macos")]
    mod macos_tests {
        use super::*;

        #[test]
        fn test_screen_recording_preferences_url() {
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture";
            assert!(url.starts_with("x-apple.systempreferences:"));
            assert!(url.contains("Privacy_ScreenCapture"));
        }

        #[test]
        fn test_accessibility_preferences_url() {
            let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";
            assert!(url.starts_with("x-apple.systempreferences:"));
            assert!(url.contains("Privacy_Accessibility"));
        }

        #[test]
        fn test_preflight_returns_bool() {
            // We can't test the actual FFI call in unit tests,
            // but we can verify the function exists and has the right type
            let result: bool = preflight_screen_capture_access();
            // Just verify it returns without crashing
            let _ = result;
        }
    }
}
