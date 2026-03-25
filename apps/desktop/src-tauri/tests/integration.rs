//! Integration tests for the Open Recorder Rust backend.
//!
//! These tests validate cross-module interactions, concurrent access patterns,
//! and end-to-end workflows that span multiple modules.

use std::sync::{Arc, Mutex};

use open_recorder_lib::state::{
    AppState, CursorTelemetryPoint, FacecamSettings, RecordingSession, SelectedSource,
    ShortcutConfig,
};

// ==================== Full Recording Lifecycle ====================

#[test]
fn test_full_recording_lifecycle_state_transitions() {
    let state = Arc::new(Mutex::new(AppState::default()));

    // 1. Select a source
    {
        let mut s = state.lock().unwrap();
        s.selected_source = Some(SelectedSource {
            id: "screen:1:0".to_string(),
            name: "Main Display".to_string(),
            source_type: Some("screen".to_string()),
            thumbnail: None,
            display_id: Some("1".to_string()),
            app_icon: None,
            original_name: None,
            app_name: None,
            window_title: None,
            window_id: None,
        });
    }

    // 2. Start recording
    {
        let mut s = state.lock().unwrap();
        s.native_screen_recording_active = true;
        s.current_video_path = Some("/tmp/recording-test.mov".to_string());
        s.has_unsaved_changes = false;
    }

    // Verify recording state
    {
        let s = state.lock().unwrap();
        assert!(s.native_screen_recording_active);
        assert!(s.selected_source.is_some());
        assert!(s.current_video_path.is_some());
    }

    // 3. Accumulate cursor telemetry during recording
    {
        let mut s = state.lock().unwrap();
        for i in 0..100 {
            s.cursor_telemetry.push(CursorTelemetryPoint {
                x: i as f64 * 10.0,
                y: i as f64 * 5.0,
                timestamp: i as f64 * 16.67,
                cursor_type: Some("arrow".to_string()),
                click_type: if i % 30 == 0 {
                    Some("left".to_string())
                } else {
                    None
                },
            });
        }
    }

    // 4. Stop recording
    {
        let mut s = state.lock().unwrap();
        s.native_screen_recording_active = false;
    }

    // 5. Set recording session
    {
        let mut s = state.lock().unwrap();
        s.current_recording_session = Some(RecordingSession {
            screen_video_path: "/tmp/recording-test.mov".to_string(),
            facecam_video_path: None,
            facecam_offset_ms: None,
            facecam_settings: None,
            source_name: None,
        });
    }

    // 6. Switch to editor (mark unsaved changes)
    {
        let mut s = state.lock().unwrap();
        s.has_unsaved_changes = true;
    }

    // Verify complete state
    {
        let s = state.lock().unwrap();
        assert!(!s.native_screen_recording_active);
        assert!(s.selected_source.is_some());
        assert_eq!(
            s.current_video_path.as_deref(),
            Some("/tmp/recording-test.mov")
        );
        assert!(s.current_recording_session.is_some());
        assert_eq!(s.cursor_telemetry.len(), 100);
        assert!(s.has_unsaved_changes);
    }
}

// ==================== Concurrent Access ====================

#[test]
fn test_concurrent_state_access_from_multiple_threads() {
    let state = Arc::new(Mutex::new(AppState::default()));
    let mut handles = vec![];

    // Spawn 10 threads that each modify state
    for i in 0..10 {
        let state_clone = Arc::clone(&state);
        handles.push(std::thread::spawn(move || {
            let mut s = state_clone.lock().unwrap();
            s.cursor_telemetry.push(CursorTelemetryPoint {
                x: i as f64,
                y: i as f64,
                timestamp: i as f64,
                cursor_type: None,
                click_type: None,
            });
        }));
    }

    for handle in handles {
        handle.join().unwrap();
    }

    let s = state.lock().unwrap();
    assert_eq!(s.cursor_telemetry.len(), 10);
}

#[test]
fn test_concurrent_video_path_updates() {
    let state = Arc::new(Mutex::new(AppState::default()));
    let mut handles = vec![];

    for i in 0..20 {
        let state_clone = Arc::clone(&state);
        handles.push(std::thread::spawn(move || {
            let mut s = state_clone.lock().unwrap();
            s.current_video_path = Some(format!("/tmp/video_{}.mov", i));
        }));
    }

    for handle in handles {
        handle.join().unwrap();
    }

    let s = state.lock().unwrap();
    // One of the threads should have set the path
    assert!(s.current_video_path.is_some());
    assert!(s
        .current_video_path
        .as_ref()
        .unwrap()
        .starts_with("/tmp/video_"));
}

#[test]
fn test_concurrent_read_write_no_deadlock() {
    let state = Arc::new(Mutex::new(AppState::default()));
    let mut handles = vec![];

    // Writers
    for i in 0..5 {
        let state_clone = Arc::clone(&state);
        handles.push(std::thread::spawn(move || {
            for j in 0..100 {
                let mut s = state_clone.lock().unwrap();
                s.cursor_scale = (i * 100 + j) as f64;
            }
        }));
    }

    // Readers
    for _ in 0..5 {
        let state_clone = Arc::clone(&state);
        handles.push(std::thread::spawn(move || {
            for _ in 0..100 {
                let s = state_clone.lock().unwrap();
                let _ = s.cursor_scale;
            }
        }));
    }

    for handle in handles {
        handle.join().unwrap();
    }

    // No deadlock occurred if we reach here
    let s = state.lock().unwrap();
    assert!(s.cursor_scale >= 0.0);
}

// ==================== Full Serialization Pipeline ====================

#[test]
fn test_full_app_state_serialization_pipeline() {
    let mut state = AppState::default();

    // Build a complete state
    state.selected_source = Some(SelectedSource {
        id: "screen:1:0".to_string(),
        name: "Main Display".to_string(),
        source_type: Some("screen".to_string()),
        thumbnail: Some("base64thumbnaildata".to_string()),
        display_id: Some("1".to_string()),
        app_icon: None,
        original_name: None,
        app_name: None,
        window_title: None,
        window_id: None,
    });

    state.current_video_path = Some("/Videos/recording.mov".to_string());
    state.current_recording_session = Some(RecordingSession {
        screen_video_path: "/Videos/recording.mov".to_string(),
        facecam_video_path: Some("/Videos/facecam.mov".to_string()),
        facecam_offset_ms: Some(150.0),
        facecam_settings: Some(FacecamSettings {
            enabled: true,
            shape: "circle".to_string(),
            size: 150.0,
            corner_radius: 75.0,
            border_width: 2.0,
            border_color: "#ffffff".to_string(),
            margin: 16.0,
            anchor: "bottom-right".to_string(),
            custom_x: None,
            custom_y: None,
        }),
        source_name: Some("Main Display".to_string()),
    });

    state.shortcuts = Some(ShortcutConfig {
        start_stop_recording: Some("CmdOrCtrl+Shift+R".to_string()),
        pause_resume_recording: Some("CmdOrCtrl+Shift+P".to_string()),
        cancel_recording: Some("Escape".to_string()),
    });

    state.cursor_scale = 1.5;
    state.has_unsaved_changes = true;

    // Serialize the selected source
    let source_json = serde_json::to_string(&state.selected_source).unwrap();
    let source_restored: Option<SelectedSource> = serde_json::from_str(&source_json).unwrap();
    assert_eq!(
        source_restored.as_ref().unwrap().id,
        state.selected_source.as_ref().unwrap().id
    );

    // Serialize the recording session
    let session_json = serde_json::to_string(&state.current_recording_session).unwrap();
    let session_restored: Option<RecordingSession> = serde_json::from_str(&session_json).unwrap();
    assert_eq!(
        session_restored.as_ref().unwrap().screen_video_path,
        state
            .current_recording_session
            .as_ref()
            .unwrap()
            .screen_video_path
    );
    assert!(session_restored
        .as_ref()
        .unwrap()
        .facecam_settings
        .is_some());

    // Serialize shortcuts
    let shortcuts_json = serde_json::to_string(&state.shortcuts).unwrap();
    let shortcuts_restored: Option<ShortcutConfig> = serde_json::from_str(&shortcuts_json).unwrap();
    assert_eq!(
        shortcuts_restored.as_ref().unwrap().start_stop_recording,
        state.shortcuts.as_ref().unwrap().start_stop_recording
    );
}

// ==================== Recording Session with Facecam ====================

#[test]
fn test_recording_session_with_facecam_full_pipeline() {
    let session = RecordingSession {
        screen_video_path: "/Videos/screen.mov".to_string(),
        facecam_video_path: Some("/Videos/facecam.mov".to_string()),
        facecam_offset_ms: Some(-200.0),
        facecam_settings: Some(FacecamSettings {
            enabled: true,
            shape: "circle".to_string(),
            size: 200.0,
            corner_radius: 100.0,
            border_width: 3.0,
            border_color: "#ff0000".to_string(),
            margin: 20.0,
            anchor: "bottom-right".to_string(),
            custom_x: None,
            custom_y: None,
        }),
        source_name: None,
    };

    // Serialize to JSON
    let json = serde_json::to_string(&session).unwrap();

    // Verify camelCase
    assert!(json.contains("screenVideoPath"));
    assert!(json.contains("facecamVideoPath"));
    assert!(json.contains("facecamOffsetMs"));
    assert!(json.contains("facecamSettings"));
    assert!(json.contains("cornerRadius"));
    assert!(json.contains("borderWidth"));
    assert!(json.contains("borderColor"));

    // Deserialize back
    let restored: RecordingSession = serde_json::from_str(&json).unwrap();
    assert_eq!(restored.screen_video_path, session.screen_video_path);
    assert_eq!(restored.facecam_offset_ms, Some(-200.0));

    let settings = restored.facecam_settings.unwrap();
    assert!(settings.enabled);
    assert_eq!(settings.shape, "circle");
    assert_eq!(settings.size, 200.0);
    assert_eq!(settings.border_color, "#ff0000");
}

// ==================== Cursor Telemetry Pipeline ====================

#[test]
fn test_cursor_telemetry_accumulation_and_serialization() {
    let mut state = AppState::default();

    // Simulate 30Hz cursor sampling for 10 seconds
    let sample_rate = 30.0;
    let duration = 10.0;
    let num_samples = (sample_rate * duration) as usize;

    for i in 0..num_samples {
        let t = i as f64 / sample_rate;
        state.cursor_telemetry.push(CursorTelemetryPoint {
            x: 960.0 + (t * 0.5).sin() * 200.0,
            y: 540.0 + (t * 0.3).cos() * 100.0,
            timestamp: t * 1000.0, // ms
            cursor_type: Some("arrow".to_string()),
            click_type: None,
        });
    }

    assert_eq!(state.cursor_telemetry.len(), num_samples);

    // Serialize the full telemetry
    let json = serde_json::to_string(&state.cursor_telemetry).unwrap();
    let restored: Vec<CursorTelemetryPoint> = serde_json::from_str(&json).unwrap();
    assert_eq!(restored.len(), num_samples);

    // Verify first and last samples
    assert_eq!(restored[0].timestamp, 0.0);
    let last_timestamp = restored.last().unwrap().timestamp;
    assert!(last_timestamp > 9000.0); // Should be close to 10 seconds
}

// ==================== Source List Management ====================

#[test]
fn test_source_list_caching_workflow() {
    let state = Arc::new(Mutex::new(AppState::default()));

    // Simulate fetching window sources
    let window_sources = vec![
        SelectedSource {
            id: "window:1:0".to_string(),
            name: "Terminal".to_string(),
            source_type: Some("window".to_string()),
            thumbnail: Some("thumb1".to_string()),
            display_id: None,
            app_icon: Some("icon1".to_string()),
            original_name: None,
            app_name: Some("Terminal".to_string()),
            window_title: Some("bash".to_string()),
            window_id: Some(1),
        },
        SelectedSource {
            id: "window:2:0".to_string(),
            name: "Chrome".to_string(),
            source_type: Some("window".to_string()),
            thumbnail: Some("thumb2".to_string()),
            display_id: None,
            app_icon: Some("icon2".to_string()),
            original_name: None,
            app_name: Some("Google Chrome".to_string()),
            window_title: Some("GitHub".to_string()),
            window_id: Some(2),
        },
    ];

    // Cache the sources
    {
        let mut s = state.lock().unwrap();
        s.cached_window_sources = window_sources.clone();
    }

    // Read back the cache
    {
        let s = state.lock().unwrap();
        assert_eq!(s.cached_window_sources.len(), 2);
        assert_eq!(s.cached_window_sources[0].name, "Terminal");
        assert_eq!(
            s.cached_window_sources[1].app_name.as_deref(),
            Some("Google Chrome")
        );
    }

    // Update cache with new list
    {
        let mut s = state.lock().unwrap();
        s.cached_window_sources = vec![SelectedSource {
            id: "window:3:0".to_string(),
            name: "Code".to_string(),
            source_type: Some("window".to_string()),
            thumbnail: None,
            display_id: None,
            app_icon: None,
            original_name: None,
            app_name: Some("Visual Studio Code".to_string()),
            window_title: None,
            window_id: Some(3),
        }];
    }

    let s = state.lock().unwrap();
    assert_eq!(s.cached_window_sources.len(), 1);
    assert_eq!(s.cached_window_sources[0].name, "Code");
}

// ==================== Project File State Machine ====================

#[test]
fn test_project_state_machine() {
    let state = Arc::new(Mutex::new(AppState::default()));

    // New project: no path, no unsaved changes
    {
        let s = state.lock().unwrap();
        assert!(s.current_project_path.is_none());
        assert!(!s.has_unsaved_changes);
    }

    // User makes changes
    {
        let mut s = state.lock().unwrap();
        s.has_unsaved_changes = true;
    }

    // User saves (first time, gets a path)
    {
        let mut s = state.lock().unwrap();
        s.current_project_path = Some("/tmp/my_project.openrecorder".to_string());
        s.has_unsaved_changes = false;
    }

    // User makes more changes
    {
        let mut s = state.lock().unwrap();
        s.has_unsaved_changes = true;
    }

    // User saves again (uses existing path)
    {
        let s = state.lock().unwrap();
        assert!(s.current_project_path.is_some()); // Has path from first save
        assert!(s.has_unsaved_changes);
    }
    {
        let mut s = state.lock().unwrap();
        s.has_unsaved_changes = false;
    }

    // Final state
    {
        let s = state.lock().unwrap();
        assert_eq!(
            s.current_project_path.as_deref(),
            Some("/tmp/my_project.openrecorder")
        );
        assert!(!s.has_unsaved_changes);
    }
}

// ==================== File I/O Integration ====================

#[tokio::test]
async fn test_video_file_store_and_read_roundtrip() {
    let dir = std::env::temp_dir().join("open_recorder_integration_test");
    let _ = tokio::fs::remove_dir_all(&dir).await;
    tokio::fs::create_dir_all(&dir).await.unwrap();

    // Simulate storing a video file
    let video_data: Vec<u8> = (0..1000).map(|i| (i % 256) as u8).collect();
    let file_name = format!("recording-{}.mov", uuid::Uuid::new_v4());
    let file_path = dir.join(&file_name);
    tokio::fs::write(&file_path, &video_data).await.unwrap();

    // Read it back
    let read_data = tokio::fs::read(&file_path).await.unwrap();
    assert_eq!(read_data, video_data);

    // Store an asset alongside
    let asset_data = b"cursor telemetry data";
    let asset_path = dir.join("cursor_data.json");
    tokio::fs::write(&asset_path, asset_data).await.unwrap();

    assert!(file_path.exists());
    assert!(asset_path.exists());

    let _ = tokio::fs::remove_dir_all(&dir).await;
}

#[tokio::test]
async fn test_settings_and_shortcuts_persistence_roundtrip() {
    let dir = std::env::temp_dir().join("open_recorder_settings_test");
    let _ = tokio::fs::remove_dir_all(&dir).await;
    tokio::fs::create_dir_all(&dir).await.unwrap();

    // Save settings
    let settings = serde_json::json!({ "recordingsDirectory": "/custom/path" });
    let settings_path = dir.join("settings.json");
    tokio::fs::write(
        &settings_path,
        serde_json::to_string_pretty(&settings).unwrap(),
    )
    .await
    .unwrap();

    // Save shortcuts
    let shortcuts = ShortcutConfig {
        start_stop_recording: Some("F9".to_string()),
        pause_resume_recording: Some("F10".to_string()),
        cancel_recording: Some("Escape".to_string()),
    };
    let shortcuts_path = dir.join("shortcuts.json");
    tokio::fs::write(
        &shortcuts_path,
        serde_json::to_string_pretty(&shortcuts).unwrap(),
    )
    .await
    .unwrap();

    // Load settings
    let loaded_settings: serde_json::Value =
        serde_json::from_str(&tokio::fs::read_to_string(&settings_path).await.unwrap()).unwrap();
    assert_eq!(loaded_settings["recordingsDirectory"], "/custom/path");

    // Load shortcuts
    let loaded_shortcuts: ShortcutConfig =
        serde_json::from_str(&tokio::fs::read_to_string(&shortcuts_path).await.unwrap()).unwrap();
    assert_eq!(loaded_shortcuts.start_stop_recording.as_deref(), Some("F9"));

    let _ = tokio::fs::remove_dir_all(&dir).await;
}
