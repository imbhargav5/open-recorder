use std::path::PathBuf;

use tauri::{AppHandle, Manager};

const PROD_APP_DIR_NAME: &str = "Open Recorder";
const DEV_APP_DIR_NAME: &str = "Open Recorder Dev";

pub fn app_dir_name() -> &'static str {
    if cfg!(debug_assertions) {
        DEV_APP_DIR_NAME
    } else {
        PROD_APP_DIR_NAME
    }
}

pub fn app_config_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;

    if !cfg!(debug_assertions) {
        return Ok(dir);
    }

    if let Some(name) = dir.file_name().and_then(|value| value.to_str()) {
        return Ok(dir.with_file_name(format!("{name}-dev")));
    }

    Ok(dir.join("dev"))
}

pub fn default_recordings_dir() -> PathBuf {
    dirs::video_dir()
        .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Videos"))
        .join(app_dir_name())
}

pub fn default_screenshots_dir() -> PathBuf {
    dirs::picture_dir()
        .unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join("Pictures"))
        .join(app_dir_name())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_dir_name_matches_build_mode() {
        let expected = if cfg!(debug_assertions) {
            DEV_APP_DIR_NAME
        } else {
            PROD_APP_DIR_NAME
        };

        assert_eq!(app_dir_name(), expected);
    }

    #[test]
    fn test_default_recordings_dir_ends_with_app_name() {
        assert!(default_recordings_dir().ends_with(app_dir_name()));
    }

    #[test]
    fn test_default_screenshots_dir_ends_with_app_name() {
        assert!(default_screenshots_dir().ends_with(app_dir_name()));
    }

    // ==================== Path validity ====================

    #[test]
    fn test_default_recordings_dir_is_not_empty() {
        let dir = default_recordings_dir();
        assert!(
            dir.as_os_str().len() > 0,
            "Recordings dir should not be empty"
        );
    }

    #[test]
    fn test_default_recordings_dir_is_absolute() {
        let dir = default_recordings_dir();
        assert!(
            dir.is_absolute(),
            "Recordings dir should be absolute: {:?}",
            dir
        );
    }

    #[test]
    fn test_default_screenshots_dir_is_not_empty() {
        let dir = default_screenshots_dir();
        assert!(
            dir.as_os_str().len() > 0,
            "Screenshots dir should not be empty"
        );
    }

    #[test]
    fn test_default_screenshots_dir_is_absolute() {
        let dir = default_screenshots_dir();
        assert!(
            dir.is_absolute(),
            "Screenshots dir should be absolute: {:?}",
            dir
        );
    }

    #[test]
    fn test_recordings_and_screenshots_dirs_differ() {
        let rec = default_recordings_dir();
        let scr = default_screenshots_dir();
        assert_ne!(
            rec, scr,
            "Recordings and screenshots should use different directories"
        );
    }

    // ==================== App dir name constants ====================

    #[test]
    fn test_prod_app_dir_name_not_empty() {
        assert!(!PROD_APP_DIR_NAME.is_empty());
    }

    #[test]
    fn test_dev_app_dir_name_not_empty() {
        assert!(!DEV_APP_DIR_NAME.is_empty());
    }

    #[test]
    fn test_prod_and_dev_app_dir_names_differ() {
        assert_ne!(PROD_APP_DIR_NAME, DEV_APP_DIR_NAME);
    }

    #[test]
    fn test_dev_app_dir_name_contains_dev() {
        assert!(
            DEV_APP_DIR_NAME.contains("Dev"),
            "Dev dir name should contain 'Dev': {}",
            DEV_APP_DIR_NAME
        );
    }

    // ==================== Determinism ====================

    #[test]
    fn test_default_recordings_dir_is_deterministic() {
        assert_eq!(default_recordings_dir(), default_recordings_dir());
    }

    #[test]
    fn test_default_screenshots_dir_is_deterministic() {
        assert_eq!(default_screenshots_dir(), default_screenshots_dir());
    }
}
