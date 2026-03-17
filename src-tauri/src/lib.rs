mod commands;
mod state;
mod native;
mod input;
mod tray;
mod menu;

use state::AppState;
use std::sync::Mutex;
use tauri::{Emitter, Manager};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_process::init())
        .manage(Mutex::new(AppState::default()))
        .setup(|app| {
            tray::setup_tray(app)?;
            menu::setup_menu(app)?;

            // Position HUD overlay at bottom-center of the primary monitor
            if let Some(window) = app.get_webview_window("hud-overlay") {
                if let Some(monitor) = window.primary_monitor()? {
                    let monitor_size = monitor.size();
                    let monitor_pos = monitor.position();
                    let scale = monitor.scale_factor();
                    let w = 600.0;
                    let h = 155.0;
                    let x = monitor_pos.x as f64
                        + (monitor_size.width as f64 / scale - w) / 2.0;
                    let y = monitor_pos.y as f64
                        + (monitor_size.height as f64 / scale - h) - 5.0;
                    window.set_position(tauri::PhysicalPosition::new(
                        (x * scale) as i32,
                        (y * scale) as i32,
                    ))?;
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Platform
            commands::platform::get_platform,
            commands::platform::open_external_url,
            commands::platform::reveal_in_folder,
            commands::platform::open_recordings_folder,
            commands::platform::get_asset_base_path,
            commands::platform::hide_cursor,
            // Files
            commands::files::read_local_file,
            commands::files::store_recorded_video,
            commands::files::store_recording_asset,
            commands::files::get_recorded_video_path,
            commands::files::set_current_video_path,
            commands::files::get_current_video_path,
            commands::files::clear_current_video_path,
            commands::files::get_current_recording_session,
            commands::files::set_current_recording_session,
            // Settings
            commands::settings::get_recordings_directory,
            commands::settings::choose_recordings_directory,
            commands::settings::get_shortcuts,
            commands::settings::save_shortcuts,
            // Sources
            commands::sources::select_source,
            commands::sources::get_selected_source,
            commands::sources::get_sources,
            // Recording
            commands::recording::set_recording_state,
            commands::recording::start_native_screen_recording,
            commands::recording::stop_native_screen_recording,
            // Cursor
            commands::cursor::get_cursor_telemetry,
            commands::cursor::set_cursor_scale,
            commands::cursor::get_system_cursor_assets,
            // Permissions
            commands::permissions::get_screen_recording_permission_status,
            commands::permissions::request_screen_recording_permission,
            commands::permissions::open_screen_recording_preferences,
            commands::permissions::get_accessibility_permission_status,
            commands::permissions::request_accessibility_permission,
            commands::permissions::open_accessibility_preferences,
            // Dialogs
            commands::dialogs::save_exported_video,
            commands::dialogs::open_video_file_picker,
            commands::dialogs::save_project_file,
            commands::dialogs::load_project_file,
            commands::dialogs::load_current_project_file,
            // Window management
            commands::window_mgmt::switch_to_editor,
            commands::window_mgmt::open_source_selector,
            commands::window_mgmt::hud_overlay_hide,
            commands::window_mgmt::hud_overlay_close,
            commands::window_mgmt::set_has_unsaved_changes,
            // Windows-specific
            commands::platform::is_wgc_available,
            commands::platform::mux_wgc_recording,
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let label = window.label();
                if label == "editor" {
                    // Check for unsaved changes before closing
                    let state: tauri::State<'_, Mutex<AppState>> = window.state();
                    let has_unsaved = state
                        .lock()
                        .map(|s| s.has_unsaved_changes)
                        .unwrap_or(false);
                    if has_unsaved {
                        api.prevent_close();
                        let _ = window.emit("request-save-before-close", ());
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
