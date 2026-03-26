mod app_paths;
mod commands;
mod input;
mod menu;
mod native;
pub mod state;
mod tray;

use state::AppState;
use std::sync::Mutex;
use tauri::{Emitter, Manager};

/// HUD overlay dimensions (logical pixels).
const HUD_WIDTH: f64 = 780.0;
const HUD_HEIGHT: f64 = 155.0;
/// Bottom margin (logical pixels) between the HUD and the screen edge.
const HUD_BOTTOM_MARGIN: f64 = 5.0;

/// Compute the physical pixel position for the HUD overlay so it sits at the
/// bottom-center of the monitor.
///
/// Parameters:
///   - `monitor_width`/`monitor_height`: physical pixel dimensions
///   - `monitor_x`/`monitor_y`: physical pixel offset (for multi-monitor)
///   - `scale`: the monitor's scale factor (e.g. 2.0 for Retina)
///
/// Returns `(physical_x, physical_y)` as `i32`.
fn compute_hud_position(
    monitor_width: u32,
    monitor_height: u32,
    monitor_x: i32,
    monitor_y: i32,
    scale: f64,
) -> (i32, i32) {
    let logical_x =
        monitor_x as f64 + (monitor_width as f64 / scale - HUD_WIDTH) / 2.0;
    let logical_y =
        monitor_y as f64 + (monitor_height as f64 / scale - HUD_HEIGHT) - HUD_BOTTOM_MARGIN;
    ((logical_x * scale) as i32, (logical_y * scale) as i32)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(Mutex::new(AppState::default()))
        .setup(|app| {
            tray::setup_tray(app)?;
            menu::setup_menu(app)?;

            // Position HUD overlay at bottom-center of the primary monitor
            if let Some(window) = app.get_webview_window("hud-overlay") {
                if let Some(monitor) = window.primary_monitor()? {
                    let size = monitor.size();
                    let pos = monitor.position();
                    let (px, py) = compute_hud_position(
                        size.width,
                        size.height,
                        pos.x,
                        pos.y,
                        monitor.scale_factor(),
                    );
                    window.set_position(tauri::PhysicalPosition::new(px, py))?;
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
            commands::files::prepare_recording_file,
            commands::files::append_recording_data,
            commands::files::replace_recording_data,
            commands::files::delete_recording_file,
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
            commands::sources::flash_selected_screen,
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
            commands::permissions::get_microphone_permission_status,
            commands::permissions::request_microphone_permission,
            commands::permissions::get_camera_permission_status,
            commands::permissions::request_camera_permission,
            commands::permissions::open_microphone_preferences,
            commands::permissions::open_camera_preferences,
            // Dialogs
            commands::dialogs::save_exported_video,
            commands::dialogs::save_screenshot_file,
            commands::dialogs::open_video_file_picker,
            commands::dialogs::save_project_file,
            commands::dialogs::load_project_file,
            commands::dialogs::load_current_project_file,
            // Window management
            commands::window_mgmt::switch_to_editor,
            commands::window_mgmt::switch_to_image_editor,
            commands::window_mgmt::open_source_selector,
            commands::window_mgmt::hud_overlay_show,
            commands::window_mgmt::hud_overlay_hide,
            commands::window_mgmt::hud_overlay_close,
            commands::window_mgmt::start_hud_overlay_drag,
            commands::window_mgmt::set_has_unsaved_changes,
            // Screenshot
            commands::screenshot::take_screenshot,
            commands::screenshot::get_current_screenshot_path,
            commands::screenshot::set_current_screenshot_path,
            // Windows-specific
            commands::platform::is_wgc_available,
            commands::platform::mux_wgc_recording,
        ])
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                let label = window.label().to_string();
                if commands::window_mgmt::is_editor_window_label(&label) {
                    let state: tauri::State<'_, Mutex<AppState>> = window.state();
                    let has_unsaved = state
                        .lock()
                        .map(|s| s.unsaved_editor_windows.contains(&label))
                        .unwrap_or(false);
                    if has_unsaved {
                        api.prevent_close();
                        let _ = window.emit("request-save-before-close", ());
                    }
                }
            }
            tauri::WindowEvent::Destroyed => {
                let label = window.label().to_string();
                if commands::window_mgmt::is_editor_window_label(&label) {
                    let state: tauri::State<'_, Mutex<AppState>> = window.state();
                    let lock_result = state.lock();
                    if let Ok(mut s) = lock_result {
                        s.unsaved_editor_windows.remove(&label);
                        s.has_unsaved_changes = !s.unsaved_editor_windows.is_empty();
                    }
                }
            }
            _ => {}
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== HUD constants ====================

    #[test]
    fn test_hud_dimensions_are_positive() {
        assert!(HUD_WIDTH > 0.0);
        assert!(HUD_HEIGHT > 0.0);
    }

    #[test]
    fn test_hud_bottom_margin_is_non_negative() {
        assert!(HUD_BOTTOM_MARGIN >= 0.0);
    }

    // ==================== compute_hud_position ====================

    #[test]
    fn test_hud_position_1080p_1x() {
        // 1920×1080 at 1.0 scale, origin (0,0)
        let (px, py) = compute_hud_position(1920, 1080, 0, 0, 1.0);
        // Logical x = (1920/1.0 - 780) / 2 = 570
        // Physical x = 570 * 1.0 = 570
        assert_eq!(px, 570);
        // Logical y = (1080/1.0 - 155) - 5 = 920
        // Physical y = 920 * 1.0 = 920
        assert_eq!(py, 920);
    }

    #[test]
    fn test_hud_position_retina_2x() {
        // 2560×1600 physical at 2.0 scale (1280×800 logical), origin (0,0)
        let (px, py) = compute_hud_position(2560, 1600, 0, 0, 2.0);
        // Logical x = (2560/2.0 - 780) / 2 = (1280 - 780) / 2 = 250
        // Physical x = 250 * 2.0 = 500
        assert_eq!(px, 500);
        // Logical y = (1600/2.0 - 155) - 5 = 640
        // Physical y = 640 * 2.0 = 1280
        assert_eq!(py, 1280);
    }

    #[test]
    fn test_hud_position_125_scale() {
        // 1920×1080 at 1.25 scale (1536×864 logical)
        let (px, py) = compute_hud_position(1920, 1080, 0, 0, 1.25);
        // Logical x = (1920/1.25 - 780) / 2 = (1536 - 780) / 2 = 378
        // Physical x = 378 * 1.25 = 472.5 → 472
        assert_eq!(px, 472);
        // Logical y = (1080/1.25 - 155) - 5 = (864 - 155) - 5 = 704
        // Physical y = 704 * 1.25 = 880
        assert_eq!(py, 880);
    }

    #[test]
    fn test_hud_position_with_monitor_offset() {
        // Multi-monitor: second monitor at physical offset (1920, 0)
        let (px, py) = compute_hud_position(1920, 1080, 1920, 0, 1.0);
        // Logical x = 1920 + (1920 - 780)/2 = 1920 + 570 = 2490
        assert_eq!(px, 2490);
        // y unchanged from single monitor
        assert_eq!(py, 920);
    }

    #[test]
    fn test_hud_position_with_negative_monitor_offset() {
        // Monitor to the left of primary: offset (-1920, 0)
        let (px, py) = compute_hud_position(1920, 1080, -1920, 0, 1.0);
        // Logical x = -1920 + 570 = -1350
        assert_eq!(px, -1350);
        assert_eq!(py, 920);
    }

    #[test]
    fn test_hud_position_small_monitor_goes_negative() {
        // Monitor narrower than HUD width (600px wide)
        let (px, py) = compute_hud_position(600, 400, 0, 0, 1.0);
        // Logical x = (600 - 780) / 2 = -90
        assert_eq!(px, -90);
        // Logical y = (400 - 155) - 5 = 240
        assert_eq!(py, 240);
    }

    #[test]
    fn test_hud_position_3x_scale() {
        // 4K at 3.0 scale (e.g. very high DPI)
        let (px, py) = compute_hud_position(3840, 2160, 0, 0, 3.0);
        // Logical x = (3840/3.0 - 780) / 2 = (1280 - 780) / 2 = 250
        // Physical x = 250 * 3.0 = 750
        assert_eq!(px, 750);
        // Logical y = (2160/3.0 - 155) - 5 = (720 - 155) - 5 = 560
        // Physical y = 560 * 3.0 = 1680
        assert_eq!(py, 1680);
    }

    #[test]
    fn test_hud_is_horizontally_centered() {
        // Verify the HUD center aligns with the monitor center
        let (px, _) = compute_hud_position(1920, 1080, 0, 0, 1.0);
        let hud_center = px as f64 + HUD_WIDTH / 2.0;
        let monitor_center = 1920.0 / 2.0;
        assert!(
            (hud_center - monitor_center).abs() < 1.0,
            "HUD center ({}) should be close to monitor center ({})",
            hud_center,
            monitor_center
        );
    }
}
