mod recording_state;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SelectedSource {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub source_type: Option<String>, // "screen" or "window"
    pub thumbnail: Option<String>,
    #[serde(default, alias = "display_id")]
    pub display_id: Option<String>,
    #[serde(default)]
    pub app_icon: Option<String>,
    #[serde(default)]
    pub original_name: Option<String>,
    #[serde(default)]
    pub app_name: Option<String>,
    #[serde(default)]
    pub window_title: Option<String>,
    #[serde(default)]
    pub window_id: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
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
#[serde(rename_all = "camelCase")]
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
    pub cached_window_sources: Vec<SelectedSource>,
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
    pub current_screenshot_path: Option<String>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            selected_source: None,
            cached_window_sources: Vec::new(),
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
            current_screenshot_path: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== AppState Default ====================

    #[test]
    fn test_app_state_default_selected_source_is_none() {
        let state = AppState::default();
        assert!(state.selected_source.is_none());
    }

    #[test]
    fn test_app_state_default_cached_window_sources_is_empty() {
        let state = AppState::default();
        assert!(state.cached_window_sources.is_empty());
    }

    #[test]
    fn test_app_state_default_current_video_path_is_none() {
        let state = AppState::default();
        assert!(state.current_video_path.is_none());
    }

    #[test]
    fn test_app_state_default_current_recording_session_is_none() {
        let state = AppState::default();
        assert!(state.current_recording_session.is_none());
    }

    #[test]
    fn test_app_state_default_current_project_path_is_none() {
        let state = AppState::default();
        assert!(state.current_project_path.is_none());
    }

    #[test]
    fn test_app_state_default_custom_recordings_dir_is_none() {
        let state = AppState::default();
        assert!(state.custom_recordings_dir.is_none());
    }

    #[test]
    fn test_app_state_default_native_recording_not_active() {
        let state = AppState::default();
        assert!(!state.native_screen_recording_active);
    }

    #[test]
    fn test_app_state_default_cursor_telemetry_is_empty() {
        let state = AppState::default();
        assert!(state.cursor_telemetry.is_empty());
    }

    #[test]
    fn test_app_state_default_cached_cursor_assets_is_none() {
        let state = AppState::default();
        assert!(state.cached_system_cursor_assets.is_none());
    }

    #[test]
    fn test_app_state_default_has_unsaved_changes_is_false() {
        let state = AppState::default();
        assert!(!state.has_unsaved_changes);
    }

    #[test]
    fn test_app_state_default_cursor_scale_is_one() {
        let state = AppState::default();
        assert_eq!(state.cursor_scale, 1.0);
    }

    #[test]
    fn test_app_state_default_shortcuts_is_none() {
        let state = AppState::default();
        assert!(state.shortcuts.is_none());
    }

    // ==================== SelectedSource Serialization ====================

    #[test]
    fn test_selected_source_serialize_uses_camel_case() {
        let source = SelectedSource {
            id: "window:123:0".to_string(),
            name: "Terminal".to_string(),
            source_type: Some("window".to_string()),
            thumbnail: None,
            display_id: None,
            app_icon: None,
            original_name: None,
            app_name: Some("Terminal".to_string()),
            window_title: Some("bash".to_string()),
            window_id: Some(123),
        };
        let json = serde_json::to_string(&source).unwrap();
        assert!(json.contains("\"sourceType\""));
        assert!(json.contains("\"appName\""));
        assert!(json.contains("\"windowTitle\""));
        assert!(json.contains("\"windowId\""));
        // Must NOT contain snake_case keys
        assert!(!json.contains("\"source_type\""));
        assert!(!json.contains("\"app_name\""));
        assert!(!json.contains("\"window_title\""));
        assert!(!json.contains("\"window_id\""));
    }

    #[test]
    fn test_selected_source_serialize_full() {
        let source = SelectedSource {
            id: "screen:1:0".to_string(),
            name: "Main Display".to_string(),
            source_type: Some("screen".to_string()),
            thumbnail: Some("base64data".to_string()),
            display_id: Some("1".to_string()),
            app_icon: None,
            original_name: Some("Built-in Retina Display".to_string()),
            app_name: None,
            window_title: None,
            window_id: None,
        };
        let json = serde_json::to_string(&source).unwrap();
        assert!(json.contains("\"id\":\"screen:1:0\""));
        assert!(json.contains("\"sourceType\":\"screen\""));
        assert!(json.contains("\"displayId\":\"1\""));
    }

    #[test]
    fn test_selected_source_deserialize_camel_case() {
        let json = r#"{"id":"screen:0:0","name":"Display","sourceType":"screen"}"#;
        let source: SelectedSource = serde_json::from_str(json).unwrap();
        assert_eq!(source.id, "screen:0:0");
        assert_eq!(source.name, "Display");
        assert_eq!(source.source_type.as_deref(), Some("screen"));
    }

    #[test]
    fn test_selected_source_deserialize_display_id_alias() {
        // The display_id field has a serde alias for "display_id" (snake_case)
        let json = r#"{"id":"screen:1:0","name":"Display","display_id":"1"}"#;
        let source: SelectedSource = serde_json::from_str(json).unwrap();
        assert_eq!(source.display_id.as_deref(), Some("1"));
    }

    #[test]
    fn test_selected_source_deserialize_display_id_camel_case() {
        let json = r#"{"id":"screen:1:0","name":"Display","displayId":"42"}"#;
        let source: SelectedSource = serde_json::from_str(json).unwrap();
        assert_eq!(source.display_id.as_deref(), Some("42"));
    }

    #[test]
    fn test_selected_source_deserialize_missing_optional_fields() {
        let json = r#"{"id":"screen:0:0","name":"Display"}"#;
        let source: SelectedSource = serde_json::from_str(json).unwrap();
        assert!(source.source_type.is_none());
        assert!(source.thumbnail.is_none());
        assert!(source.display_id.is_none());
        assert!(source.app_icon.is_none());
        assert!(source.original_name.is_none());
        assert!(source.app_name.is_none());
        assert!(source.window_title.is_none());
        assert!(source.window_id.is_none());
    }

    #[test]
    fn test_selected_source_deserialize_missing_required_id_fails() {
        let json = r#"{"name":"Display"}"#;
        let result: Result<SelectedSource, _> = serde_json::from_str(json);
        assert!(result.is_err());
    }

    #[test]
    fn test_selected_source_deserialize_missing_required_name_fails() {
        let json = r#"{"id":"screen:0:0"}"#;
        let result: Result<SelectedSource, _> = serde_json::from_str(json);
        assert!(result.is_err());
    }

    #[test]
    fn test_selected_source_deserialize_extra_fields_ignored() {
        let json = r#"{"id":"s:0","name":"D","extraField":"ignored","anotherOne":42}"#;
        let result: Result<SelectedSource, _> = serde_json::from_str(json);
        assert!(result.is_ok());
    }

    #[test]
    fn test_selected_source_roundtrip() {
        let original = SelectedSource {
            id: "window:42:0".to_string(),
            name: "My Window".to_string(),
            source_type: Some("window".to_string()),
            thumbnail: Some("thumb_data".to_string()),
            display_id: None,
            app_icon: Some("icon_data".to_string()),
            original_name: Some("Original".to_string()),
            app_name: Some("MyApp".to_string()),
            window_title: Some("Title".to_string()),
            window_id: Some(42),
        };
        let json = serde_json::to_string(&original).unwrap();
        let restored: SelectedSource = serde_json::from_str(&json).unwrap();
        assert_eq!(original.id, restored.id);
        assert_eq!(original.name, restored.name);
        assert_eq!(original.source_type, restored.source_type);
        assert_eq!(original.thumbnail, restored.thumbnail);
        assert_eq!(original.display_id, restored.display_id);
        assert_eq!(original.app_icon, restored.app_icon);
        assert_eq!(original.original_name, restored.original_name);
        assert_eq!(original.app_name, restored.app_name);
        assert_eq!(original.window_title, restored.window_title);
        assert_eq!(original.window_id, restored.window_id);
    }

    #[test]
    fn test_selected_source_clone() {
        let source = SelectedSource {
            id: "screen:1:0".to_string(),
            name: "Display 1".to_string(),
            source_type: Some("screen".to_string()),
            thumbnail: None,
            display_id: Some("1".to_string()),
            app_icon: None,
            original_name: None,
            app_name: None,
            window_title: None,
            window_id: None,
        };
        let cloned = source.clone();
        assert_eq!(source.id, cloned.id);
        assert_eq!(source.name, cloned.name);
        assert_eq!(source.source_type, cloned.source_type);
    }

    // ==================== FacecamSettings Serialization ====================

    #[test]
    fn test_facecam_settings_serialize_uses_camel_case() {
        let settings = FacecamSettings {
            enabled: true,
            shape: "circle".to_string(),
            size: 150.0,
            corner_radius: 75.0,
            border_width: 2.0,
            border_color: "#ffffff".to_string(),
            margin: 16.0,
        };
        let json = serde_json::to_string(&settings).unwrap();
        assert!(json.contains("\"cornerRadius\":75"));
        assert!(json.contains("\"borderWidth\":2"));
        assert!(json.contains("\"borderColor\":\"#ffffff\""));
    }

    #[test]
    fn test_facecam_settings_deserialize() {
        let json = r##"{"enabled":false,"shape":"rectangle","size":200.0,"cornerRadius":10.0,"borderWidth":1.0,"borderColor":"#000","margin":8.0}"##;
        let s: FacecamSettings = serde_json::from_str(json).unwrap();
        assert!(!s.enabled);
        assert_eq!(s.shape, "rectangle");
        assert_eq!(s.size, 200.0);
        assert_eq!(s.corner_radius, 10.0);
        assert_eq!(s.border_width, 1.0);
        assert_eq!(s.border_color, "#000");
        assert_eq!(s.margin, 8.0);
    }

    #[test]
    fn test_facecam_settings_roundtrip() {
        let original = FacecamSettings {
            enabled: true,
            shape: "circle".to_string(),
            size: 180.0,
            corner_radius: 90.0,
            border_width: 3.5,
            border_color: "#ff0000".to_string(),
            margin: 20.0,
        };
        let json = serde_json::to_string(&original).unwrap();
        let restored: FacecamSettings = serde_json::from_str(&json).unwrap();
        assert_eq!(original.enabled, restored.enabled);
        assert_eq!(original.shape, restored.shape);
        assert_eq!(original.size, restored.size);
        assert_eq!(original.corner_radius, restored.corner_radius);
        assert_eq!(original.border_width, restored.border_width);
        assert_eq!(original.border_color, restored.border_color);
        assert_eq!(original.margin, restored.margin);
    }

    #[test]
    fn test_facecam_settings_zero_values() {
        let settings = FacecamSettings {
            enabled: false,
            shape: "".to_string(),
            size: 0.0,
            corner_radius: 0.0,
            border_width: 0.0,
            border_color: "".to_string(),
            margin: 0.0,
        };
        let json = serde_json::to_string(&settings).unwrap();
        let restored: FacecamSettings = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.size, 0.0);
        assert_eq!(restored.border_width, 0.0);
    }

    // ==================== RecordingSession Serialization ====================

    #[test]
    fn test_recording_session_serialize_minimal() {
        let session = RecordingSession {
            screen_video_path: "/path/to/video.mov".to_string(),
            facecam_video_path: None,
            facecam_offset_ms: None,
            facecam_settings: None,
        };
        let json = serde_json::to_string(&session).unwrap();
        assert!(json.contains("\"screenVideoPath\":\"/path/to/video.mov\""));
    }

    #[test]
    fn test_recording_session_serialize_with_facecam() {
        let session = RecordingSession {
            screen_video_path: "/video.mov".to_string(),
            facecam_video_path: Some("/facecam.mov".to_string()),
            facecam_offset_ms: Some(150.5),
            facecam_settings: Some(FacecamSettings {
                enabled: true,
                shape: "circle".to_string(),
                size: 150.0,
                corner_radius: 75.0,
                border_width: 2.0,
                border_color: "#fff".to_string(),
                margin: 16.0,
            }),
        };
        let json = serde_json::to_string(&session).unwrap();
        assert!(json.contains("\"facecamVideoPath\":\"/facecam.mov\""));
        assert!(json.contains("\"facecamOffsetMs\":150.5"));
        assert!(json.contains("\"facecamSettings\""));
    }

    #[test]
    fn test_recording_session_deserialize() {
        let json = r#"{"screenVideoPath":"/tmp/test.mov","facecamVideoPath":null,"facecamOffsetMs":null,"facecamSettings":null}"#;
        let session: RecordingSession = serde_json::from_str(json).unwrap();
        assert_eq!(session.screen_video_path, "/tmp/test.mov");
        assert!(session.facecam_video_path.is_none());
        assert!(session.facecam_offset_ms.is_none());
        assert!(session.facecam_settings.is_none());
    }

    #[test]
    fn test_recording_session_roundtrip() {
        let original = RecordingSession {
            screen_video_path: "/videos/rec.mov".to_string(),
            facecam_video_path: Some("/videos/cam.mov".to_string()),
            facecam_offset_ms: Some(-200.0),
            facecam_settings: None,
        };
        let json = serde_json::to_string(&original).unwrap();
        let restored: RecordingSession = serde_json::from_str(&json).unwrap();
        assert_eq!(original.screen_video_path, restored.screen_video_path);
        assert_eq!(original.facecam_video_path, restored.facecam_video_path);
        assert_eq!(original.facecam_offset_ms, restored.facecam_offset_ms);
    }

    #[test]
    fn test_recording_session_negative_offset() {
        let session = RecordingSession {
            screen_video_path: "/v.mov".to_string(),
            facecam_video_path: None,
            facecam_offset_ms: Some(-500.0),
            facecam_settings: None,
        };
        let json = serde_json::to_string(&session).unwrap();
        let restored: RecordingSession = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.facecam_offset_ms, Some(-500.0));
    }

    // ==================== CursorTelemetryPoint ====================

    #[test]
    fn test_cursor_telemetry_point_serialize() {
        let point = CursorTelemetryPoint {
            x: 100.5,
            y: 200.75,
            timestamp: 1234567890.123,
            cursor_type: Some("arrow".to_string()),
            click_type: Some("left".to_string()),
        };
        let json = serde_json::to_string(&point).unwrap();
        assert!(json.contains("\"x\":100.5"));
        assert!(json.contains("\"y\":200.75"));
        assert!(json.contains("\"cursor_type\":\"arrow\""));
        assert!(json.contains("\"click_type\":\"left\""));
    }

    #[test]
    fn test_cursor_telemetry_point_deserialize_minimal() {
        let json = r#"{"x":0.0,"y":0.0,"timestamp":0.0}"#;
        let point: CursorTelemetryPoint = serde_json::from_str(json).unwrap();
        assert_eq!(point.x, 0.0);
        assert_eq!(point.y, 0.0);
        assert!(point.cursor_type.is_none());
        assert!(point.click_type.is_none());
    }

    #[test]
    fn test_cursor_telemetry_point_roundtrip() {
        let original = CursorTelemetryPoint {
            x: 1920.0,
            y: 1080.0,
            timestamp: 9999.999,
            cursor_type: Some("ibeam".to_string()),
            click_type: None,
        };
        let json = serde_json::to_string(&original).unwrap();
        let restored: CursorTelemetryPoint = serde_json::from_str(&json).unwrap();
        assert_eq!(original.x, restored.x);
        assert_eq!(original.y, restored.y);
        assert_eq!(original.timestamp, restored.timestamp);
        assert_eq!(original.cursor_type, restored.cursor_type);
        assert_eq!(original.click_type, restored.click_type);
    }

    #[test]
    fn test_cursor_telemetry_point_negative_coordinates() {
        let point = CursorTelemetryPoint {
            x: -50.0,
            y: -100.0,
            timestamp: 1.0,
            cursor_type: None,
            click_type: None,
        };
        let json = serde_json::to_string(&point).unwrap();
        let restored: CursorTelemetryPoint = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.x, -50.0);
        assert_eq!(restored.y, -100.0);
    }

    #[test]
    fn test_cursor_telemetry_point_large_coordinates() {
        let point = CursorTelemetryPoint {
            x: 7680.0,
            y: 4320.0,
            timestamp: f64::MAX,
            cursor_type: None,
            click_type: None,
        };
        let json = serde_json::to_string(&point).unwrap();
        let restored: CursorTelemetryPoint = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.x, 7680.0);
        assert_eq!(restored.y, 4320.0);
    }

    // ==================== ShortcutConfig ====================

    #[test]
    fn test_shortcut_config_serialize_all_set() {
        let config = ShortcutConfig {
            start_stop_recording: Some("CmdOrCtrl+Shift+R".to_string()),
            pause_resume_recording: Some("CmdOrCtrl+Shift+P".to_string()),
            cancel_recording: Some("Escape".to_string()),
        };
        let json = serde_json::to_string(&config).unwrap();
        assert!(json.contains("\"start_stop_recording\""));
        assert!(json.contains("CmdOrCtrl+Shift+R"));
    }

    #[test]
    fn test_shortcut_config_serialize_all_none() {
        let config = ShortcutConfig {
            start_stop_recording: None,
            pause_resume_recording: None,
            cancel_recording: None,
        };
        let json = serde_json::to_string(&config).unwrap();
        let restored: ShortcutConfig = serde_json::from_str(&json).unwrap();
        assert!(restored.start_stop_recording.is_none());
        assert!(restored.pause_resume_recording.is_none());
        assert!(restored.cancel_recording.is_none());
    }

    #[test]
    fn test_shortcut_config_roundtrip() {
        let original = ShortcutConfig {
            start_stop_recording: Some("F9".to_string()),
            pause_resume_recording: None,
            cancel_recording: Some("F10".to_string()),
        };
        let json = serde_json::to_string(&original).unwrap();
        let restored: ShortcutConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(original.start_stop_recording, restored.start_stop_recording);
        assert_eq!(
            original.pause_resume_recording,
            restored.pause_resume_recording
        );
        assert_eq!(original.cancel_recording, restored.cancel_recording);
    }

    // ==================== AppState Mutation ====================

    #[test]
    fn test_app_state_set_selected_source() {
        let mut state = AppState::default();
        state.selected_source = Some(SelectedSource {
            id: "screen:0:0".to_string(),
            name: "Display".to_string(),
            source_type: Some("screen".to_string()),
            thumbnail: None,
            display_id: Some("0".to_string()),
            app_icon: None,
            original_name: None,
            app_name: None,
            window_title: None,
            window_id: None,
        });
        assert_eq!(state.selected_source.as_ref().unwrap().id, "screen:0:0");
    }

    #[test]
    fn test_app_state_set_and_clear_video_path() {
        let mut state = AppState::default();
        state.current_video_path = Some("/tmp/video.mov".to_string());
        assert_eq!(state.current_video_path.as_deref(), Some("/tmp/video.mov"));
        state.current_video_path = None;
        assert!(state.current_video_path.is_none());
    }

    #[test]
    fn test_app_state_recording_active_toggle() {
        let mut state = AppState::default();
        assert!(!state.native_screen_recording_active);
        state.native_screen_recording_active = true;
        assert!(state.native_screen_recording_active);
        state.native_screen_recording_active = false;
        assert!(!state.native_screen_recording_active);
    }

    #[test]
    fn test_app_state_cursor_telemetry_append() {
        let mut state = AppState::default();
        state.cursor_telemetry.push(CursorTelemetryPoint {
            x: 100.0,
            y: 200.0,
            timestamp: 1.0,
            cursor_type: None,
            click_type: None,
        });
        state.cursor_telemetry.push(CursorTelemetryPoint {
            x: 150.0,
            y: 250.0,
            timestamp: 2.0,
            cursor_type: Some("pointer".to_string()),
            click_type: Some("left".to_string()),
        });
        assert_eq!(state.cursor_telemetry.len(), 2);
        assert_eq!(state.cursor_telemetry[0].x, 100.0);
        assert_eq!(
            state.cursor_telemetry[1].cursor_type.as_deref(),
            Some("pointer")
        );
    }

    #[test]
    fn test_app_state_cursor_scale_modification() {
        let mut state = AppState::default();
        state.cursor_scale = 2.5;
        assert_eq!(state.cursor_scale, 2.5);
    }

    #[test]
    fn test_app_state_unsaved_changes_toggle() {
        let mut state = AppState::default();
        state.has_unsaved_changes = true;
        assert!(state.has_unsaved_changes);
    }

    #[test]
    fn test_app_state_shortcuts_set_and_clear() {
        let mut state = AppState::default();
        state.shortcuts = Some(ShortcutConfig {
            start_stop_recording: Some("CmdOrCtrl+R".to_string()),
            pause_resume_recording: None,
            cancel_recording: None,
        });
        assert!(state.shortcuts.is_some());
        state.shortcuts = None;
        assert!(state.shortcuts.is_none());
    }

    #[test]
    fn test_app_state_set_recording_session() {
        let mut state = AppState::default();
        state.current_recording_session = Some(RecordingSession {
            screen_video_path: "/tmp/screen.mov".to_string(),
            facecam_video_path: None,
            facecam_offset_ms: None,
            facecam_settings: None,
        });
        assert_eq!(
            state
                .current_recording_session
                .as_ref()
                .unwrap()
                .screen_video_path,
            "/tmp/screen.mov"
        );
    }

    #[test]
    fn test_app_state_cached_window_sources() {
        let mut state = AppState::default();
        state.cached_window_sources.push(SelectedSource {
            id: "window:1:0".to_string(),
            name: "Finder".to_string(),
            source_type: Some("window".to_string()),
            thumbnail: None,
            display_id: None,
            app_icon: None,
            original_name: None,
            app_name: Some("Finder".to_string()),
            window_title: None,
            window_id: Some(1),
        });
        assert_eq!(state.cached_window_sources.len(), 1);
        assert_eq!(state.cached_window_sources[0].name, "Finder");
    }

    // ==================== Mutex Concurrency ====================

    #[test]
    fn test_app_state_mutex_lock_and_modify() {
        let state = std::sync::Mutex::new(AppState::default());
        {
            let mut s = state.lock().unwrap();
            s.current_video_path = Some("/test.mov".to_string());
        }
        {
            let s = state.lock().unwrap();
            assert_eq!(s.current_video_path.as_deref(), Some("/test.mov"));
        }
    }

    #[test]
    fn test_app_state_mutex_sequential_recording_lifecycle() {
        let state = std::sync::Mutex::new(AppState::default());

        // Start recording
        {
            let mut s = state.lock().unwrap();
            s.native_screen_recording_active = true;
            s.current_video_path = Some("/recording.mov".to_string());
        }

        // Stop recording
        {
            let mut s = state.lock().unwrap();
            s.native_screen_recording_active = false;
        }

        // Verify final state
        {
            let s = state.lock().unwrap();
            assert!(!s.native_screen_recording_active);
            assert_eq!(s.current_video_path.as_deref(), Some("/recording.mov"));
        }
    }

    // ==================== Serialization of collections ====================

    #[test]
    fn test_selected_source_vec_serialization() {
        let sources = vec![
            SelectedSource {
                id: "screen:0:0".to_string(),
                name: "Main".to_string(),
                source_type: Some("screen".to_string()),
                thumbnail: None,
                display_id: Some("0".to_string()),
                app_icon: None,
                original_name: None,
                app_name: None,
                window_title: None,
                window_id: None,
            },
            SelectedSource {
                id: "window:1:0".to_string(),
                name: "Browser".to_string(),
                source_type: Some("window".to_string()),
                thumbnail: None,
                display_id: None,
                app_icon: None,
                original_name: None,
                app_name: Some("Chrome".to_string()),
                window_title: Some("Google".to_string()),
                window_id: Some(1),
            },
        ];
        let json = serde_json::to_string(&sources).unwrap();
        let restored: Vec<SelectedSource> = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.len(), 2);
        assert_eq!(restored[0].id, "screen:0:0");
        assert_eq!(restored[1].app_name.as_deref(), Some("Chrome"));
    }

    #[test]
    fn test_cursor_telemetry_vec_serialization() {
        let points = vec![
            CursorTelemetryPoint {
                x: 0.0,
                y: 0.0,
                timestamp: 0.0,
                cursor_type: None,
                click_type: None,
            },
            CursorTelemetryPoint {
                x: 100.0,
                y: 100.0,
                timestamp: 16.67,
                cursor_type: Some("arrow".to_string()),
                click_type: None,
            },
            CursorTelemetryPoint {
                x: 200.0,
                y: 200.0,
                timestamp: 33.33,
                cursor_type: Some("pointer".to_string()),
                click_type: Some("left".to_string()),
            },
        ];
        let json = serde_json::to_string(&points).unwrap();
        let restored: Vec<CursorTelemetryPoint> = serde_json::from_str(&json).unwrap();
        assert_eq!(restored.len(), 3);
        assert_eq!(restored[2].click_type.as_deref(), Some("left"));
    }
}
