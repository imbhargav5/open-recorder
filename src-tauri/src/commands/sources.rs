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
        let source_type = source
            .source_type
            .as_deref()
            .or_else(|| {
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
