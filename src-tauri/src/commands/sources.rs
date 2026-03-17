use std::sync::Mutex;
use tauri::Manager;

use crate::state::{AppState, SelectedSource};

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThumbnailSize {
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceListOptions {
    pub types: Option<Vec<String>>,
    pub thumbnail_size: Option<ThumbnailSize>,
}

#[tauri::command]
pub fn select_source(
    app: tauri::AppHandle,
    state: tauri::State<'_, Mutex<AppState>>,
    source: SelectedSource,
) -> Result<(), String> {
    let mut s = state.lock().map_err(|e| e.to_string())?;
    s.selected_source = Some(source);

    if let Some(selector) = app.get_webview_window("source-selector") {
        let _ = selector.close();
    }

    Ok(())
}

#[tauri::command]
pub fn flash_selected_screen(source: SelectedSource) -> Result<(), String> {
    flash_selected_screen_impl(&source)
}

#[tauri::command]
pub fn get_selected_source(
    state: tauri::State<'_, Mutex<AppState>>,
) -> Result<Option<SelectedSource>, String> {
    let s = state.lock().map_err(|e| e.to_string())?;
    Ok(s.selected_source.clone())
}

#[tauri::command]
pub async fn get_sources(opts: Option<SourceListOptions>) -> Result<Vec<SelectedSource>, String> {
    #[cfg(target_os = "macos")]
    {
        let thumbnail_width = opts
            .as_ref()
            .and_then(|options| options.thumbnail_size.as_ref())
            .and_then(|size| size.width)
            .filter(|width| *width > 0)
            .unwrap_or(320);
        let thumbnail_height = opts
            .as_ref()
            .and_then(|options| options.thumbnail_size.as_ref())
            .and_then(|size| size.height)
            .filter(|height| *height > 0)
            .unwrap_or(180);

        let sidecar_path = crate::native::sidecar::get_sidecar_path("openscreen-window-list")?;
        let output = tokio::process::Command::new(&sidecar_path)
            .arg("--thumbnail-width")
            .arg(thumbnail_width.to_string())
            .arg("--thumbnail-height")
            .arg(thumbnail_height.to_string())
            .output()
            .await
            .map_err(|e| e.to_string())?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let mut sources: Vec<SelectedSource> =
                serde_json::from_str(&stdout).map_err(|e| e.to_string())?;

            sources.retain(|source| !source.id.trim().is_empty() && !source.name.trim().is_empty());
            apply_source_filters(&mut sources, opts.as_ref());
            if !sources.is_empty() {
                return Ok(sources);
            }
        }

        let mut sources = fallback_sources();
        apply_source_filters(&mut sources, opts.as_ref());
        Ok(sources)
    }

    #[cfg(not(target_os = "macos"))]
    {
        let mut sources = fallback_sources();
        apply_source_filters(&mut sources, opts.as_ref());
        Ok(sources)
    }
}

fn apply_source_filters(sources: &mut Vec<SelectedSource>, opts: Option<&SourceListOptions>) {
    let Some(options) = opts else {
        return;
    };

    let Some(types) = &options.types else {
        return;
    };

    if types.is_empty() {
        return;
    }

    sources.retain(|source| {
        let source_type = source.source_type.as_deref().or_else(|| {
            if source.id.starts_with("window:") {
                Some("window")
            } else if source.id.starts_with("screen:") {
                Some("screen")
            } else {
                None
            }
        });

        source_type
            .map(|kind| types.iter().any(|allowed| allowed == kind))
            .unwrap_or(true)
    });
}

fn fallback_sources() -> Vec<SelectedSource> {
    vec![SelectedSource {
        id: "screen:0:0".to_string(),
        name: "Main Display".to_string(),
        source_type: Some("screen".to_string()),
        thumbnail: None,
        display_id: Some("0".to_string()),
        app_icon: None,
        original_name: None,
        app_name: None,
        window_title: None,
        window_id: None,
    }]
}

#[cfg(target_os = "macos")]
fn flash_selected_screen_impl(source: &SelectedSource) -> Result<(), String> {
    let source_type = source.source_type.as_deref().unwrap_or_else(|| {
        if source.id.starts_with("screen:") {
            "screen"
        } else {
            ""
        }
    });

    if source_type != "screen" {
        return Ok(());
    }

    let Some(display_id) = source
        .display_id
        .clone()
        .or_else(|| parse_display_id_from_source_id(&source.id))
    else {
        return Ok(());
    };

    let sidecar_path =
        crate::native::sidecar::get_sidecar_path("openscreen-screen-selection-flash")?;

    std::process::Command::new(sidecar_path)
        .arg("--display-id")
        .arg(display_id)
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("Failed to flash selected screen: {}", error))
}

#[cfg(not(target_os = "macos"))]
fn flash_selected_screen_impl(_source: &SelectedSource) -> Result<(), String> {
    Ok(())
}

#[cfg(target_os = "macos")]
fn parse_display_id_from_source_id(source_id: &str) -> Option<String> {
    source_id
        .strip_prefix("screen:")
        .and_then(|value| value.split(':').next())
        .map(ToOwned::to_owned)
}
