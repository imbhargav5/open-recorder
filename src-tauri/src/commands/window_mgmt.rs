use std::sync::Mutex;
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};
#[cfg(target_os = "macos")]
use tauri::{LogicalPosition, Position, TitleBarStyle};
use tauri::window::Color;

use crate::state::AppState;

#[tauri::command]
pub async fn switch_to_editor(app: AppHandle) -> Result<(), String> {
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
        .title("Open Recorder")
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
pub fn set_has_unsaved_changes(
    state: tauri::State<'_, Mutex<AppState>>,
    has_changes: bool,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.has_unsaved_changes = has_changes;
    Ok(())
}
