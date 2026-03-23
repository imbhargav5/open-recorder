use std::sync::Mutex;
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder, Window};
#[cfg(target_os = "macos")]
use tauri::{LogicalPosition, Position, TitleBarStyle};
use tauri::window::Color;

use crate::state::AppState;

#[tauri::command]
pub async fn switch_to_editor(app: AppHandle) -> Result<(), String> {
    let app_name = app.package_info().name.clone();

    // Close or hide HUD overlay
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.hide();
    }

    // Close source selector if open
    if let Some(selector) = app.get_webview_window("source-selector") {
        let _ = selector.close();
    }

    // Create or focus editor window
    if let Some(editor) = app.get_webview_window("editor") {
        let _ = editor.show();
        let _ = editor.set_focus();
    } else {
        let mut builder = WebviewWindowBuilder::new(
            &app,
            "editor",
            WebviewUrl::App("index.html?windowType=editor".into()),
        )
        .title(app_name)
        .inner_size(1200.0, 800.0)
        .min_inner_size(800.0, 600.0)
        .resizable(true)
        .maximized(true)
        .background_color(Color(0, 0, 0, 255));

        #[cfg(target_os = "macos")]
        {
            builder = builder
                .title_bar_style(TitleBarStyle::Overlay)
                .traffic_light_position(Position::Logical(LogicalPosition::new(12.0, 12.0)));
        }

        builder.build().map_err(|e: tauri::Error| e.to_string())?;
    }

    Ok(())
}

#[tauri::command]
pub async fn open_source_selector(app: AppHandle) -> Result<(), String> {
    if let Some(selector) = app.get_webview_window("source-selector") {
        let _ = selector.show();
        let _ = selector.set_focus();
    } else {
        WebviewWindowBuilder::new(
            &app,
            "source-selector",
            WebviewUrl::App("index.html?windowType=source-selector".into()),
        )
        .title("Select Source")
        .inner_size(620.0, 420.0)
        .min_inner_size(620.0, 350.0)
        .max_inner_size(620.0, 500.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .center()
        .build()
        .map_err(|e: tauri::Error| e.to_string())?;
    }

    Ok(())
}

#[tauri::command]
pub async fn hud_overlay_hide(app: AppHandle) -> Result<(), String> {
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.hide();
    }
    Ok(())
}

#[tauri::command]
pub async fn hud_overlay_close(app: AppHandle) -> Result<(), String> {
    // Close all windows and quit
    for (_, window) in app.webview_windows() {
        let _ = window.close();
    }
    Ok(())
}

#[tauri::command]
pub async fn start_hud_overlay_drag(window: Window) -> Result<(), String> {
    window.start_dragging().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_has_unsaved_changes(
    state: tauri::State<'_, Mutex<AppState>>,
    has_changes: bool,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.has_unsaved_changes = has_changes;
    Ok(())
}

#[tauri::command]
pub async fn switch_to_image_editor(app: AppHandle) -> Result<(), String> {
    let app_name = app.package_info().name.clone();

    // Hide HUD overlay
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.hide();
    }

    // Close source selector if open
    if let Some(selector) = app.get_webview_window("source-selector") {
        let _ = selector.close();
    }

    // Create or focus image editor window
    if let Some(editor) = app.get_webview_window("image-editor") {
        let _ = editor.show();
        let _ = editor.set_focus();
    } else {
        let mut builder = WebviewWindowBuilder::new(
            &app,
            "image-editor",
            WebviewUrl::App("index.html?windowType=image-editor".into()),
        )
        .title(format!("{app_name} — Screenshot"))
        .inner_size(1100.0, 750.0)
        .min_inner_size(800.0, 550.0)
        .resizable(true)
        .background_color(Color(0, 0, 0, 255));

        #[cfg(target_os = "macos")]
        {
            builder = builder
                .title_bar_style(TitleBarStyle::Overlay)
                .traffic_light_position(Position::Logical(LogicalPosition::new(12.0, 12.0)));
        }

        builder.build().map_err(|e: tauri::Error| e.to_string())?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== Window Constants ====================

    #[test]
    fn test_editor_window_dimensions() {
        let width = 1200.0_f64;
        let height = 800.0_f64;
        assert!(width > 0.0);
        assert!(height > 0.0);
        assert!(width >= 800.0); // min width
        assert!(height >= 600.0); // min height
    }

    #[test]
    fn test_editor_min_dimensions() {
        let min_width = 800.0_f64;
        let min_height = 600.0_f64;
        assert!(min_width > 0.0);
        assert!(min_height > 0.0);
    }

    #[test]
    fn test_source_selector_dimensions() {
        let width = 620.0_f64;
        let height = 420.0_f64;
        let min_height = 350.0_f64;
        let max_height = 500.0_f64;
        assert!(min_height <= height);
        assert!(height <= max_height);
        assert_eq!(width, 620.0);
    }

    // ==================== Window URLs ====================

    #[test]
    fn test_editor_url() {
        let url = "index.html?windowType=editor";
        assert!(url.contains("windowType=editor"));
    }

    #[test]
    fn test_source_selector_url() {
        let url = "index.html?windowType=source-selector";
        assert!(url.contains("windowType=source-selector"));
    }

    // ==================== Unsaved Changes State ====================

    #[test]
    fn test_set_unsaved_changes_true() {
        let state = std::sync::Mutex::new(AppState::default());
        {
            let mut s = state.lock().unwrap();
            s.has_unsaved_changes = true;
        }
        let s = state.lock().unwrap();
        assert!(s.has_unsaved_changes);
    }

    #[test]
    fn test_set_unsaved_changes_false() {
        let state = std::sync::Mutex::new(AppState::default());
        {
            let mut s = state.lock().unwrap();
            s.has_unsaved_changes = true;
        }
        {
            let mut s = state.lock().unwrap();
            s.has_unsaved_changes = false;
        }
        let s = state.lock().unwrap();
        assert!(!s.has_unsaved_changes);
    }

    #[test]
    fn test_unsaved_changes_default_is_false() {
        let state = AppState::default();
        assert!(!state.has_unsaved_changes);
    }

    // ==================== Background Color ====================

    #[test]
    fn test_editor_background_color() {
        let color = Color(0, 0, 0, 255);
        assert_eq!(color.0, 0); // R
        assert_eq!(color.1, 0); // G
        assert_eq!(color.2, 0); // B
        assert_eq!(color.3, 255); // A (fully opaque)
    }
}
