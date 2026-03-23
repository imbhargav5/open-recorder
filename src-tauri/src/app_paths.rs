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
}
