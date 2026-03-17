mod recording_state;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SelectedSource {
    pub id: String,
    pub name: String,
    #[serde(default, alias = "sourceType")]
    pub source_type: Option<String>, // "screen" or "window"
    pub thumbnail: Option<String>,
    #[serde(default, alias = "displayId")]
    pub display_id: Option<String>,
    #[serde(default, alias = "appIcon")]
    pub app_icon: Option<String>,
    #[serde(default, alias = "originalName")]
    pub original_name: Option<String>,
    #[serde(default, alias = "appName")]
    pub app_name: Option<String>,
    #[serde(default, alias = "windowTitle")]
    pub window_title: Option<String>,
    #[serde(default, alias = "windowId")]
    pub window_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FacecamSettings {
    pub enabled: bool,
    pub shape: String,
    pub size: f64,
    pub corner_radius: f64,
    pub border_width: f64,
    pub border_color: String,
    pub margin: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingSession {
    pub screen_video_path: String,
    pub facecam_video_path: Option<String>,
    pub facecam_offset_ms: Option<f64>,
    pub facecam_settings: Option<FacecamSettings>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CursorTelemetryPoint {
    pub x: f64,
    pub y: f64,
    pub timestamp: f64,
    pub cursor_type: Option<String>,
    pub click_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShortcutConfig {
    pub start_stop_recording: Option<String>,
    pub pause_resume_recording: Option<String>,
    pub cancel_recording: Option<String>,
}

pub struct AppState {
    pub selected_source: Option<SelectedSource>,
    pub current_video_path: Option<String>,
    pub current_recording_session: Option<RecordingSession>,
    pub current_project_path: Option<String>,
    pub custom_recordings_dir: Option<String>,
    pub native_screen_recording_active: bool,
    pub cursor_telemetry: Vec<CursorTelemetryPoint>,
    pub cached_system_cursor_assets: Option<serde_json::Value>,
    pub has_unsaved_changes: bool,
    pub cursor_scale: f64,
    pub shortcuts: Option<ShortcutConfig>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            selected_source: None,
            current_video_path: None,
            current_recording_session: None,
            current_project_path: None,
            custom_recordings_dir: None,
            native_screen_recording_active: false,
            cursor_telemetry: Vec::new(),
            cached_system_cursor_assets: None,
            has_unsaved_changes: false,
            cursor_scale: 1.0,
            shortcuts: None,
        }
    }
}
