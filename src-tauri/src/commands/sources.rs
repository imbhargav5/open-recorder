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
    pub with_thumbnails: Option<bool>,
    pub timeout_ms: Option<u64>,
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
        let (wants_screens, wants_windows) = requested_source_kinds(opts.as_ref());
        let with_thumbnails = opts
            .as_ref()
            .and_then(|options| options.with_thumbnails)
            .unwrap_or(false);
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

        let mut sources = Vec::new();

        if with_thumbnails {
            match crate::native::sidecar::get_sidecar_path("openscreen-window-list") {
                Ok(sidecar_path) => {
                    let timeout_duration = Duration::from_millis(
                        opts.as_ref()
                            .and_then(|options| options.timeout_ms)
                            .unwrap_or(if wants_windows { 8000 } else { 4000 }),
                    );
                    match fetch_macos_sources_via_sidecar(
                        &sidecar_path,
                        wants_screens,
                        wants_windows,
                        thumbnail_width,
                        thumbnail_height,
                        false,
                        timeout_duration,
                    )
                    .await
                    {
                        Ok(sidecar_sources) => {
                            let (screen_sources, window_sources) =
                                partition_sources_by_kind(sidecar_sources);
                            if wants_screens {
                                if screen_sources.is_empty() {
                                    sources.extend(fallback_macos_sources()?);
                                } else {
                                    sources.extend(screen_sources);
                                }
                            }

                            if wants_windows {
                                cache_window_sources(&state, &window_sources)?;
                                sources.extend(window_sources);
                            }
                        }
                        Err(e) => {
                            eprintln!("[get_sources] Sidecar thumbnail fetch failed: {}", e);
                            if wants_screens {
                                sources.extend(fallback_macos_sources()?);
                            }
                            if wants_windows {
                                sources.extend(cached_window_sources(&state)?);
                            }
                        }
                    };
                }
                Err(e) => {
                    eprintln!("[get_sources] Sidecar not found for thumbnails: {}", e);
                    if wants_screens {
                        sources.extend(fallback_macos_sources()?);
                    }
                    if wants_windows {
                        sources.extend(cached_window_sources(&state)?);
                    }
                }
            }
        } else {
            if wants_screens {
                sources.extend(fallback_macos_sources()?);
            }

            if wants_windows {
                let sidecar_path =
                    crate::native::sidecar::get_sidecar_path("openscreen-window-list")?;
                match fetch_macos_sources_via_sidecar(
                    &sidecar_path,
                    false,
                    true,
                    thumbnail_width,
                    thumbnail_height,
                    true,
                    Duration::from_millis(1500),
                )
                .await
                {
                    Ok(sidecar_sources) => {
                        let (_, window_sources) = partition_sources_by_kind(sidecar_sources);
                        cache_window_sources(&state, &window_sources)?;
                        sources.extend(window_sources);
                    }
                    Err(_) => {
                        sources.extend(cached_window_sources(&state)?);
                    }
                };
            }
        }

        if sources.is_empty() {
            sources = fallback_sources();
        }

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
    wants_screens: bool,
    wants_windows: bool,
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

    command
        .arg("--types")
        .arg(requested_types_argument(wants_screens, wants_windows));

    if no_thumbnails {
        command.arg("--no-thumbnails");
    }

    let output = timeout(timeout_duration, command.output())
        .await
        .map_err(|_| "Timed out waiting for macOS source helper".to_string())?
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
    sources.retain(|source| source_matches_requested_kind(source, wants_screens, wants_windows));
    sources.retain(|source| !source.id.trim().is_empty() && !source.name.trim().is_empty());
    Ok(sources)
}

fn source_matches_requested_kind(
    source: &SelectedSource,
    wants_screens: bool,
    wants_windows: bool,
) -> bool {
    match source.source_type.as_deref().or_else(|| {
        if source.id.starts_with("screen:") {
            Some("screen")
        } else if source.id.starts_with("window:") {
            Some("window")
        } else {
            None
        }
    }) {
        Some("screen") => wants_screens,
        Some("window") => wants_windows,
        _ => false,
    }
}

fn requested_types_argument(wants_screens: bool, wants_windows: bool) -> String {
    match (wants_screens, wants_windows) {
        (true, true) => "screen,window".to_string(),
        (true, false) => "screen".to_string(),
        (false, true) => "window".to_string(),
        (false, false) => "screen,window".to_string(),
    }
}

fn partition_sources_by_kind(
    sources: Vec<SelectedSource>,
) -> (Vec<SelectedSource>, Vec<SelectedSource>) {
    let mut screen_sources = Vec::new();
    let mut window_sources = Vec::new();

    for source in sources {
        if source_matches_requested_kind(&source, true, false) {
            screen_sources.push(source);
        } else if source_matches_requested_kind(&source, false, true) {
            window_sources.push(source);
        }
    }

    (screen_sources, window_sources)
}

fn requested_source_kinds(opts: Option<&SourceListOptions>) -> (bool, bool) {
    let Some(types) = opts.and_then(|options| options.types.as_ref()) else {
        return (true, true);
    };

    if types.is_empty() {
        return (true, true);
    }

    let wants_screens = types.iter().any(|kind| kind == "screen");
    let wants_windows = types.iter().any(|kind| kind == "window");
    (wants_screens, wants_windows)
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
fn cache_window_sources(
    state: &tauri::State<'_, Mutex<AppState>>,
    sources: &[SelectedSource],
) -> Result<(), String> {
    let mut app_state = state.lock().map_err(|e| e.to_string())?;
    app_state.cached_window_sources = sources.to_vec();
    Ok(())
}

#[cfg(target_os = "macos")]
fn cached_window_sources(
    state: &tauri::State<'_, Mutex<AppState>>,
) -> Result<Vec<SelectedSource>, String> {
    let app_state = state.lock().map_err(|e| e.to_string())?;
    Ok(app_state.cached_window_sources.clone())
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

#[cfg(test)]
mod tests {
    use super::*;

    // ==================== Helper: make a SelectedSource ====================

    fn make_source(id: &str, name: &str, source_type: Option<&str>) -> SelectedSource {
        SelectedSource {
            id: id.to_string(),
            name: name.to_string(),
            source_type: source_type.map(ToString::to_string),
            thumbnail: None,
            display_id: None,
            app_icon: None,
            original_name: None,
            app_name: None,
            window_title: None,
            window_id: None,
        }
    }

    // ==================== source_matches_requested_kind ====================

    #[test]
    fn test_source_matches_screen_with_explicit_type_wants_screens() {
        let source = make_source("screen:0:0", "Display", Some("screen"));
        assert!(source_matches_requested_kind(&source, true, false));
    }

    #[test]
    fn test_source_matches_screen_with_explicit_type_wants_windows() {
        let source = make_source("screen:0:0", "Display", Some("screen"));
        assert!(!source_matches_requested_kind(&source, false, true));
    }

    #[test]
    fn test_source_matches_window_with_explicit_type_wants_windows() {
        let source = make_source("window:1:0", "Terminal", Some("window"));
        assert!(source_matches_requested_kind(&source, false, true));
    }

    #[test]
    fn test_source_matches_window_with_explicit_type_wants_screens() {
        let source = make_source("window:1:0", "Terminal", Some("window"));
        assert!(!source_matches_requested_kind(&source, true, false));
    }

    #[test]
    fn test_source_matches_infers_screen_from_id_prefix() {
        let source = make_source("screen:42:0", "Display", None);
        assert!(source_matches_requested_kind(&source, true, false));
        assert!(!source_matches_requested_kind(&source, false, true));
    }

    #[test]
    fn test_source_matches_infers_window_from_id_prefix() {
        let source = make_source("window:99:0", "App", None);
        assert!(source_matches_requested_kind(&source, false, true));
        assert!(!source_matches_requested_kind(&source, true, false));
    }

    #[test]
    fn test_source_matches_unknown_type_returns_false() {
        let source = make_source("other:0:0", "Unknown", None);
        assert!(!source_matches_requested_kind(&source, true, true));
    }

    #[test]
    fn test_source_matches_explicit_type_overrides_prefix() {
        // source_type says "window" but id prefix says "screen:"
        let source = make_source("screen:0:0", "Weird", Some("window"));
        assert!(source_matches_requested_kind(&source, false, true));
        assert!(!source_matches_requested_kind(&source, true, false));
    }

    #[test]
    fn test_source_matches_both_wanted() {
        let screen = make_source("screen:0:0", "Display", Some("screen"));
        let window = make_source("window:1:0", "App", Some("window"));
        assert!(source_matches_requested_kind(&screen, true, true));
        assert!(source_matches_requested_kind(&window, true, true));
    }

    // ==================== requested_types_argument ====================

    #[test]
    fn test_requested_types_both() {
        assert_eq!(requested_types_argument(true, true), "screen,window");
    }

    #[test]
    fn test_requested_types_screens_only() {
        assert_eq!(requested_types_argument(true, false), "screen");
    }

    #[test]
    fn test_requested_types_windows_only() {
        assert_eq!(requested_types_argument(false, true), "window");
    }

    #[test]
    fn test_requested_types_neither_defaults_to_both() {
        assert_eq!(requested_types_argument(false, false), "screen,window");
    }

    // ==================== partition_sources_by_kind ====================

    #[test]
    fn test_partition_empty_list() {
        let (screens, windows) = partition_sources_by_kind(vec![]);
        assert!(screens.is_empty());
        assert!(windows.is_empty());
    }

    #[test]
    fn test_partition_only_screens() {
        let sources = vec![
            make_source("screen:0:0", "Display 1", Some("screen")),
            make_source("screen:1:0", "Display 2", Some("screen")),
        ];
        let (screens, windows) = partition_sources_by_kind(sources);
        assert_eq!(screens.len(), 2);
        assert!(windows.is_empty());
    }

    #[test]
    fn test_partition_only_windows() {
        let sources = vec![
            make_source("window:1:0", "App 1", Some("window")),
            make_source("window:2:0", "App 2", Some("window")),
        ];
        let (screens, windows) = partition_sources_by_kind(sources);
        assert!(screens.is_empty());
        assert_eq!(windows.len(), 2);
    }

    #[test]
    fn test_partition_mixed_sources() {
        let sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("window:1:0", "Terminal", Some("window")),
            make_source("screen:1:0", "Display 2", Some("screen")),
            make_source("window:2:0", "Browser", Some("window")),
        ];
        let (screens, windows) = partition_sources_by_kind(sources);
        assert_eq!(screens.len(), 2);
        assert_eq!(windows.len(), 2);
        assert_eq!(screens[0].name, "Display");
        assert_eq!(windows[0].name, "Terminal");
    }

    #[test]
    fn test_partition_unknown_type_dropped() {
        let sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("other:0:0", "Unknown", Some("other")),
        ];
        let (screens, windows) = partition_sources_by_kind(sources);
        assert_eq!(screens.len(), 1);
        assert!(windows.is_empty());
    }

    // ==================== requested_source_kinds ====================

    #[test]
    fn test_requested_source_kinds_none_opts() {
        let (screens, windows) = requested_source_kinds(None);
        assert!(screens);
        assert!(windows);
    }

    #[test]
    fn test_requested_source_kinds_empty_types() {
        let opts = SourceListOptions {
            types: Some(vec![]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        let (screens, windows) = requested_source_kinds(Some(&opts));
        assert!(screens);
        assert!(windows);
    }

    #[test]
    fn test_requested_source_kinds_no_types_field() {
        let opts = SourceListOptions {
            types: None,
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        let (screens, windows) = requested_source_kinds(Some(&opts));
        assert!(screens);
        assert!(windows);
    }

    #[test]
    fn test_requested_source_kinds_screen_only() {
        let opts = SourceListOptions {
            types: Some(vec!["screen".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        let (screens, windows) = requested_source_kinds(Some(&opts));
        assert!(screens);
        assert!(!windows);
    }

    #[test]
    fn test_requested_source_kinds_window_only() {
        let opts = SourceListOptions {
            types: Some(vec!["window".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        let (screens, windows) = requested_source_kinds(Some(&opts));
        assert!(!screens);
        assert!(windows);
    }

    #[test]
    fn test_requested_source_kinds_both() {
        let opts = SourceListOptions {
            types: Some(vec!["screen".to_string(), "window".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        let (screens, windows) = requested_source_kinds(Some(&opts));
        assert!(screens);
        assert!(windows);
    }

    #[test]
    fn test_requested_source_kinds_unknown_type() {
        let opts = SourceListOptions {
            types: Some(vec!["other".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        let (screens, windows) = requested_source_kinds(Some(&opts));
        assert!(!screens);
        assert!(!windows);
    }

    // ==================== apply_source_filters ====================

    #[test]
    fn test_apply_source_filters_no_opts_preserves_all() {
        let mut sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("window:1:0", "App", Some("window")),
        ];
        apply_source_filters(&mut sources, None);
        assert_eq!(sources.len(), 2);
    }

    #[test]
    fn test_apply_source_filters_no_types_preserves_all() {
        let mut sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("window:1:0", "App", Some("window")),
        ];
        let opts = SourceListOptions {
            types: None,
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        apply_source_filters(&mut sources, Some(&opts));
        assert_eq!(sources.len(), 2);
    }

    #[test]
    fn test_apply_source_filters_empty_types_preserves_all() {
        let mut sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("window:1:0", "App", Some("window")),
        ];
        let opts = SourceListOptions {
            types: Some(vec![]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        apply_source_filters(&mut sources, Some(&opts));
        assert_eq!(sources.len(), 2);
    }

    #[test]
    fn test_apply_source_filters_screen_only() {
        let mut sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("window:1:0", "App", Some("window")),
            make_source("screen:1:0", "Display 2", Some("screen")),
        ];
        let opts = SourceListOptions {
            types: Some(vec!["screen".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        apply_source_filters(&mut sources, Some(&opts));
        assert_eq!(sources.len(), 2);
        assert!(sources.iter().all(|s| s.source_type.as_deref() == Some("screen")));
    }

    #[test]
    fn test_apply_source_filters_window_only() {
        let mut sources = vec![
            make_source("screen:0:0", "Display", Some("screen")),
            make_source("window:1:0", "App", Some("window")),
        ];
        let opts = SourceListOptions {
            types: Some(vec!["window".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        apply_source_filters(&mut sources, Some(&opts));
        assert_eq!(sources.len(), 1);
        assert_eq!(sources[0].source_type.as_deref(), Some("window"));
    }

    #[test]
    fn test_apply_source_filters_infers_type_from_id_prefix() {
        let mut sources = vec![
            make_source("screen:0:0", "Display", None), // No explicit type
            make_source("window:1:0", "App", None),     // No explicit type
        ];
        let opts = SourceListOptions {
            types: Some(vec!["screen".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        apply_source_filters(&mut sources, Some(&opts));
        assert_eq!(sources.len(), 1);
        assert_eq!(sources[0].id, "screen:0:0");
    }

    #[test]
    fn test_apply_source_filters_unknown_type_kept_when_filtering() {
        // Sources with unknown type (can't be inferred) are kept (unwrap_or(true))
        let mut sources = vec![
            make_source("other:0:0", "Unknown", None),
            make_source("screen:0:0", "Display", Some("screen")),
        ];
        let opts = SourceListOptions {
            types: Some(vec!["screen".to_string()]),
            thumbnail_size: None,
            with_thumbnails: None,
            timeout_ms: None,
        };
        apply_source_filters(&mut sources, Some(&opts));
        // "other:0:0" has no recognizable type, so unwrap_or(true) keeps it
        assert_eq!(sources.len(), 2);
    }

    // ==================== fallback_sources ====================

    #[test]
    fn test_fallback_sources_returns_one_source() {
        let sources = fallback_sources();
        assert_eq!(sources.len(), 1);
    }

    #[test]
    fn test_fallback_sources_is_screen_type() {
        let sources = fallback_sources();
        assert_eq!(sources[0].source_type.as_deref(), Some("screen"));
    }

    #[test]
    fn test_fallback_sources_has_main_display_name() {
        let sources = fallback_sources();
        assert_eq!(sources[0].name, "Main Display");
    }

    #[test]
    fn test_fallback_sources_id_format() {
        let sources = fallback_sources();
        assert!(sources[0].id.starts_with("screen:"));
    }

    #[test]
    fn test_fallback_sources_has_display_id() {
        let sources = fallback_sources();
        assert!(sources[0].display_id.is_some());
    }

    // ==================== ThumbnailSize deserialization ====================

    #[test]
    fn test_thumbnail_size_deserialize_both() {
        let json = r#"{"width":320,"height":180}"#;
        let size: ThumbnailSize = serde_json::from_str(json).unwrap();
        assert_eq!(size.width, Some(320));
        assert_eq!(size.height, Some(180));
    }

    #[test]
    fn test_thumbnail_size_deserialize_partial() {
        let json = r#"{"width":320}"#;
        let size: ThumbnailSize = serde_json::from_str(json).unwrap();
        assert_eq!(size.width, Some(320));
        assert!(size.height.is_none());
    }

    #[test]
    fn test_thumbnail_size_deserialize_empty() {
        let json = r#"{}"#;
        let size: ThumbnailSize = serde_json::from_str(json).unwrap();
        assert!(size.width.is_none());
        assert!(size.height.is_none());
    }

    // ==================== SourceListOptions deserialization ====================

    #[test]
    fn test_source_list_options_deserialize_full() {
        let json = r#"{"types":["screen","window"],"thumbnailSize":{"width":320,"height":180},"withThumbnails":true,"timeoutMs":5000}"#;
        let opts: SourceListOptions = serde_json::from_str(json).unwrap();
        assert_eq!(opts.types.as_ref().unwrap().len(), 2);
        assert_eq!(opts.with_thumbnails, Some(true));
        assert_eq!(opts.timeout_ms, Some(5000));
    }

    #[test]
    fn test_source_list_options_deserialize_empty() {
        let json = r#"{}"#;
        let opts: SourceListOptions = serde_json::from_str(json).unwrap();
        assert!(opts.types.is_none());
        assert!(opts.thumbnail_size.is_none());
        assert!(opts.with_thumbnails.is_none());
        assert!(opts.timeout_ms.is_none());
    }

    // ==================== parse_display_id_from_source_id (macOS) ====================

    #[cfg(target_os = "macos")]
    mod macos_tests {
        use super::*;

        #[test]
        fn test_parse_display_id_valid_screen_id() {
            let result = parse_display_id_from_source_id("screen:42:0");
            assert_eq!(result.as_deref(), Some("42"));
        }

        #[test]
        fn test_parse_display_id_main_display() {
            let result = parse_display_id_from_source_id("screen:0:0");
            assert_eq!(result.as_deref(), Some("0"));
        }

        #[test]
        fn test_parse_display_id_large_id() {
            let result = parse_display_id_from_source_id("screen:4294967295:0");
            assert_eq!(result.as_deref(), Some("4294967295"));
        }

        #[test]
        fn test_parse_display_id_window_id_returns_none() {
            let result = parse_display_id_from_source_id("window:123:0");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_display_id_empty_string_returns_none() {
            let result = parse_display_id_from_source_id("");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_display_id_no_prefix_returns_none() {
            let result = parse_display_id_from_source_id("42:0");
            assert!(result.is_none());
        }

        #[test]
        fn test_parse_display_id_no_colon_after_prefix() {
            let result = parse_display_id_from_source_id("screen:");
            // strip_prefix returns "", split(':').next() returns Some("")
            assert_eq!(result.as_deref(), Some(""));
        }
    }
}
