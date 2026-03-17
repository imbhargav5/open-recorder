use std::sync::Mutex;
use tauri::Manager;

use crate::state::{AppState, SelectedSource};

#[cfg(target_os = "macos")]
type CGDirectDisplayID = u32;
#[cfg(target_os = "macos")]
type CGError = i32;
#[cfg(target_os = "macos")]
const CG_ERROR_SUCCESS: CGError = 0;
#[cfg(target_os = "macos")]
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGMainDisplayID() -> CGDirectDisplayID;
    fn CGGetOnlineDisplayList(
        max_displays: u32,
        active_displays: *mut CGDirectDisplayID,
        display_count: *mut u32,
    ) -> CGError;
}

#[cfg(target_os = "macos")]
use std::path::Path;
#[cfg(target_os = "macos")]
use tokio::time::{Duration, timeout};

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
pub async fn get_sources(
    state: tauri::State<'_, Mutex<AppState>>,
    opts: Option<SourceListOptions>,
) -> Result<Vec<SelectedSource>, String> {
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

        match fetch_macos_sources_via_sidecar(
            &sidecar_path,
            thumbnail_width,
            thumbnail_height,
            false,
            Duration::from_secs(6),
        )
        .await
        {
            Ok(mut sources) => {
                cache_sources(&state, &sources)?;
                apply_source_filters(&mut sources, opts.as_ref());
                if !sources.is_empty() {
                    return Ok(sources);
                }
            }
            Err(error) => {
                eprintln!(
                    "Window list helper with thumbnails failed, retrying without thumbnails: {}",
                    error
                );
            }
        }

        match fetch_macos_sources_via_sidecar(
            &sidecar_path,
            thumbnail_width,
            thumbnail_height,
            true,
            Duration::from_secs(3),
        )
        .await
        {
            Ok(mut sources) => {
                cache_sources(&state, &sources)?;
                apply_source_filters(&mut sources, opts.as_ref());
                if !sources.is_empty() {
                    return Ok(sources);
                }
            }
            Err(error) => {
                eprintln!(
                    "Window list helper without thumbnails failed, using fallback sources: {}",
                    error
                );
            }
        }

        let mut cached_sources = cached_sources(&state)?;
        apply_source_filters(&mut cached_sources, opts.as_ref());
        if !cached_sources.is_empty() {
            return Ok(cached_sources);
        }

        let mut sources = fallback_macos_sources()?;
        cache_sources(&state, &sources)?;
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

#[cfg(target_os = "macos")]
async fn fetch_macos_sources_via_sidecar(
    sidecar_path: &Path,
    thumbnail_width: u32,
    thumbnail_height: u32,
    no_thumbnails: bool,
    timeout_duration: Duration,
) -> Result<Vec<SelectedSource>, String> {
    let mut command = tokio::process::Command::new(sidecar_path);
    command
        .kill_on_drop(true)
        .arg("--thumbnail-width")
        .arg(thumbnail_width.to_string())
        .arg("--thumbnail-height")
        .arg(thumbnail_height.to_string());

    if no_thumbnails {
        command.arg("--no-thumbnails");
    }

    let output = timeout(timeout_duration, command.output())
        .await
        .map_err(|_| {
            if no_thumbnails {
                "Timed out waiting for macOS source helper without thumbnails".to_string()
            } else {
                "Timed out waiting for macOS source helper with thumbnails".to_string()
            }
        })?
        .map_err(|e| e.to_string())?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!(
                "Source helper exited with code {}",
                output.status.code().unwrap_or(-1)
            )
        } else {
            stderr
        });
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut sources: Vec<SelectedSource> = serde_json::from_str(&stdout).map_err(|e| e.to_string())?;
    sources.retain(|source| !source.id.trim().is_empty() && !source.name.trim().is_empty());
    Ok(sources)
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
fn cache_sources(
    state: &tauri::State<'_, Mutex<AppState>>,
    sources: &[SelectedSource],
) -> Result<(), String> {
    let mut app_state = state.lock().map_err(|e| e.to_string())?;
    app_state.cached_sources = sources.to_vec();
    Ok(())
}

#[cfg(target_os = "macos")]
fn cached_sources(
    state: &tauri::State<'_, Mutex<AppState>>,
) -> Result<Vec<SelectedSource>, String> {
    let app_state = state.lock().map_err(|e| e.to_string())?;
    Ok(app_state.cached_sources.clone())
}

#[cfg(target_os = "macos")]
fn fallback_macos_sources() -> Result<Vec<SelectedSource>, String> {
    let mut display_count = 0_u32;
    let status = unsafe { CGGetOnlineDisplayList(0, std::ptr::null_mut(), &mut display_count) };
    if status != CG_ERROR_SUCCESS {
        return Err(format!("Failed to enumerate macOS displays: {}", status));
    }

    if display_count == 0 {
        return Ok(fallback_sources());
    }

    let mut display_ids = vec![0_u32; display_count as usize];
    let status = unsafe {
        CGGetOnlineDisplayList(
            display_count,
            display_ids.as_mut_ptr(),
            &mut display_count,
        )
    };
    if status != CG_ERROR_SUCCESS {
        return Err(format!("Failed to read macOS display list: {}", status));
    }

    let main_display_id = unsafe { CGMainDisplayID() };
    let mut screen_index = 1_usize;
    let mut sources = Vec::with_capacity(display_count as usize);

    for display_id in display_ids.into_iter().take(display_count as usize) {
        let name = if display_id == main_display_id {
            "Main Display".to_string()
        } else {
            let name = format!("Display {}", screen_index + 1);
            screen_index += 1;
            name
        };

        sources.push(SelectedSource {
            id: format!("screen:{}:0", display_id),
            name,
            source_type: Some("screen".to_string()),
            thumbnail: None,
            display_id: Some(display_id.to_string()),
            app_icon: None,
            original_name: None,
            app_name: None,
            window_title: None,
            window_id: None,
        });
    }

    if sources.is_empty() {
        Ok(fallback_sources())
    } else {
        Ok(sources)
    }
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
