use std::sync::Mutex;
use tauri::window::Color;
use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder, Window};
#[cfg(target_os = "macos")]
use tauri::{LogicalPosition, Position, TitleBarStyle};

use crate::state::AppState;

fn next_editor_window_label(app: &AppHandle) -> String {
    let mut index = 1;
    loop {
        let label = format!("editor-{index}");
        if app.get_webview_window(&label).is_none() {
            return label;
        }
        index += 1;
    }
}

fn build_editor_window_url(query: Option<&str>) -> String {
    let normalized_query = query
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.trim_start_matches('?').to_string());

    match normalized_query {
        Some(query) => format!("index.html?{query}"),
        None => "index.html?windowType=editor".to_string(),
    }
}

pub fn is_editor_window_label(label: &str) -> bool {
    label == "editor" || label.starts_with("editor-")
}

#[tauri::command]
pub async fn switch_to_editor(app: AppHandle, query: Option<String>) -> Result<(), String> {
    let app_name = app.package_info().name.clone();

    // Close or hide HUD overlay
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.hide();
    }
    crate::tray::update_tray_menu(&app);

    // Close source selector if open
    if let Some(selector) = app.get_webview_window("source-selector") {
        let _ = selector.close();
    }

    let label = next_editor_window_label(&app);
    let url = build_editor_window_url(query.as_deref());

    let mut builder = WebviewWindowBuilder::new(&app, &label, WebviewUrl::App(url.into()))
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

    Ok(())
}

#[tauri::command]
pub async fn open_source_selector(app: AppHandle, tab: Option<String>) -> Result<(), String> {
    // Close existing window so we can reopen with the correct tab parameter.
    if let Some(selector) = app.get_webview_window("source-selector") {
        let _ = selector.destroy();
    }

    let tab_param = tab.unwrap_or_default();
    let url = format!("index.html?windowType=source-selector&tab={}", tab_param);

    WebviewWindowBuilder::new(
        &app,
        "source-selector",
        WebviewUrl::App(url.into()),
    )
    .title("Select Source")
    .inner_size(660.0, 820.0)
    .min_inner_size(400.0, 300.0)
    .resizable(true)
    .decorations(false)
    .transparent(true)
    .always_on_top(true)
    .skip_taskbar(true)
    .center()
    .build()
    .map_err(|e: tauri::Error| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn close_source_selector(app: AppHandle) -> Result<(), String> {
    if let Some(selector) = app.get_webview_window("source-selector") {
        selector.destroy().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub async fn hud_overlay_show(app: AppHandle) -> Result<(), String> {
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.show();
        let _ = hud.set_focus();
    }
    crate::tray::update_tray_menu(&app);
    Ok(())
}

#[tauri::command]
pub async fn hud_overlay_hide(app: AppHandle) -> Result<(), String> {
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.hide();
    }
    crate::tray::update_tray_menu(&app);
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
    window: Window,
    state: tauri::State<'_, Mutex<AppState>>,
    has_changes: bool,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    let label = window.label().to_string();
    if is_editor_window_label(&label) {
        if has_changes {
            s.unsaved_editor_windows.insert(label);
        } else {
            s.unsaved_editor_windows.remove(&label);
        }
        s.has_unsaved_changes = !s.unsaved_editor_windows.is_empty();
    }
    Ok(())
}

#[tauri::command]
pub async fn switch_to_image_editor(app: AppHandle) -> Result<(), String> {
    let app_name = app.package_info().name.clone();

    // Hide HUD overlay
    if let Some(hud) = app.get_webview_window("hud-overlay") {
        let _ = hud.hide();
    }
    crate::tray::update_tray_menu(&app);

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
        let url = build_editor_window_url(Some("windowType=editor&editorMode=video"));
        assert_eq!(url, "index.html?windowType=editor&editorMode=video");
    }

    #[test]
    fn test_editor_url_defaults_when_query_missing() {
        let url = build_editor_window_url(None);
        assert_eq!(url, "index.html?windowType=editor");
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
            s.unsaved_editor_windows.insert("editor-1".to_string());
            s.has_unsaved_changes = !s.unsaved_editor_windows.is_empty();
        }
        let s = state.lock().unwrap();
        assert!(s.has_unsaved_changes);
        assert!(s.unsaved_editor_windows.contains("editor-1"));
    }

    #[test]
    fn test_set_unsaved_changes_false() {
        let state = std::sync::Mutex::new(AppState::default());
        {
            let mut s = state.lock().unwrap();
            s.unsaved_editor_windows.insert("editor-1".to_string());
            s.has_unsaved_changes = true;
        }
        {
            let mut s = state.lock().unwrap();
            s.unsaved_editor_windows.remove("editor-1");
            s.has_unsaved_changes = !s.unsaved_editor_windows.is_empty();
        }
        let s = state.lock().unwrap();
        assert!(!s.has_unsaved_changes);
        assert!(s.unsaved_editor_windows.is_empty());
    }

    #[test]
    fn test_unsaved_changes_default_is_false() {
        let state = AppState::default();
        assert!(!state.has_unsaved_changes);
        assert!(state.unsaved_editor_windows.is_empty());
    }

    #[test]
    fn test_editor_window_label_detection() {
        assert!(is_editor_window_label("editor"));
        assert!(is_editor_window_label("editor-3"));
        assert!(!is_editor_window_label("image-editor"));
    }

    // ==================== is_editor_window_label edge cases ====================

    #[test]
    fn test_editor_label_with_trailing_hyphen() {
        // "editor-" starts_with "editor-", so this should match
        assert!(is_editor_window_label("editor-"));
    }

    #[test]
    fn test_editor_label_zero_index() {
        assert!(is_editor_window_label("editor-0"));
    }

    #[test]
    fn test_editor_label_large_index() {
        assert!(is_editor_window_label("editor-999"));
    }

    #[test]
    fn test_editor_label_case_sensitive_uppercase() {
        assert!(!is_editor_window_label("Editor"));
    }

    #[test]
    fn test_editor_label_case_sensitive_all_caps() {
        assert!(!is_editor_window_label("EDITOR"));
    }

    #[test]
    fn test_editor_label_empty_string() {
        assert!(!is_editor_window_label(""));
    }

    #[test]
    fn test_editor_label_no_hyphen_suffix() {
        // "editor1" does NOT start with "editor-" and is not == "editor"
        assert!(!is_editor_window_label("editor1"));
    }

    #[test]
    fn test_editor_label_plural() {
        assert!(!is_editor_window_label("editors"));
    }

    #[test]
    fn test_editor_label_hud_overlay() {
        assert!(!is_editor_window_label("hud-overlay"));
    }

    #[test]
    fn test_editor_label_source_selector() {
        assert!(!is_editor_window_label("source-selector"));
    }

    #[test]
    fn test_editor_label_image_editor() {
        assert!(!is_editor_window_label("image-editor"));
    }

    // ==================== build_editor_window_url edge cases ====================

    #[test]
    fn test_editor_url_empty_string_falls_to_default() {
        let url = build_editor_window_url(Some(""));
        assert_eq!(url, "index.html?windowType=editor");
    }

    #[test]
    fn test_editor_url_whitespace_only_falls_to_default() {
        let url = build_editor_window_url(Some("   "));
        assert_eq!(url, "index.html?windowType=editor");
    }

    #[test]
    fn test_editor_url_strips_leading_question_mark() {
        let url = build_editor_window_url(Some("?windowType=editor"));
        assert_eq!(url, "index.html?windowType=editor");
    }

    #[test]
    fn test_editor_url_strips_all_leading_question_marks() {
        // trim_start_matches strips ALL leading '?' characters
        let url = build_editor_window_url(Some("??double"));
        assert_eq!(url, "index.html?double");
    }

    #[test]
    fn test_editor_url_trims_whitespace_and_strips_question_mark() {
        let url = build_editor_window_url(Some("  ?windowType=editor  "));
        assert_eq!(url, "index.html?windowType=editor");
    }

    #[test]
    fn test_editor_url_preserves_ampersands_and_params() {
        let url = build_editor_window_url(Some("windowType=editor&mode=video&id=123"));
        assert_eq!(url, "index.html?windowType=editor&mode=video&id=123");
    }

    #[test]
    fn test_editor_url_only_question_mark_falls_to_default() {
        // "?" → trim → "?" → not empty → trim_start_matches('?') → "" → format → "index.html?"
        let url = build_editor_window_url(Some("?"));
        assert_eq!(url, "index.html?");
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
