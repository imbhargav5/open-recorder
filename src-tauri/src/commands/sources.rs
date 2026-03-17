use std::sync::Mutex;
use tauri::Manager;

use crate::state::{AppState, SelectedSource};

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
pub async fn get_sources() -> Result<Vec<SelectedSource>, String> {
    #[cfg(target_os = "macos")]
    {
        let sidecar_path = crate::native::sidecar::get_sidecar_path("openscreen-window-list")?;
        let output = tokio::process::Command::new(&sidecar_path)
                .output()
                .await
                .map_err(|e| e.to_string())?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let mut sources: Vec<SelectedSource> =
                serde_json::from_str(&stdout).map_err(|e| e.to_string())?;

            sources.retain(|source| !source.id.trim().is_empty() && !source.name.trim().is_empty());
            if !sources.is_empty() {
                return Ok(sources);
            }
        }

        Ok(fallback_sources())
    }

    #[cfg(not(target_os = "macos"))]
    {
        Ok(fallback_sources())
    }
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
