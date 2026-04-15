use tauri::{
    image::Image,
    menu::{MenuBuilder, MenuItemBuilder},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager,
};

use crate::state::AppState;

#[cfg(any(test, not(target_os = "macos")))]
fn into_owned_tray_image(image: Image<'_>) -> Image<'static> {
    image.to_owned()
}

fn is_hud_visible<M: Manager<tauri::Wry>>(manager: &M) -> bool {
    manager
        .get_webview_window("hud-overlay")
        .and_then(|window| window.is_visible().ok())
        .unwrap_or(false)
}

fn is_recording_active(app: &AppHandle) -> bool {
    app.state::<std::sync::Mutex<AppState>>()
        .lock()
        .map(|state| state.native_screen_recording_active)
        .unwrap_or(false)
}

fn should_enable_new_recording(recording: bool, hud_visible: bool) -> bool {
    !recording && !hud_visible
}

fn build_tray_menu<M: Manager<tauri::Wry>>(
    manager: &M,
    recording: bool,
    hud_visible: bool,
) -> tauri::Result<tauri::menu::Menu<tauri::Wry>> {
    let open_item = MenuItemBuilder::with_id("open", "Open").build(manager)?;
    let new_recording_item = MenuItemBuilder::with_id("new-recording", "New Recording")
        .enabled(should_enable_new_recording(recording, hud_visible))
        .build(manager)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(manager)?;

    let mut menu = MenuBuilder::new(manager)
        .item(&open_item)
        .item(&new_recording_item);

    if recording {
        let stop_item = MenuItemBuilder::with_id("stop", "Stop Recording").build(manager)?;
        menu = menu.item(&stop_item);
    }

    menu.separator().item(&quit_item).build()
}

pub fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let menu = build_tray_menu(app, is_recording_active(&app.handle()), is_hud_visible(app))?;

    TrayIconBuilder::with_id("main")
        .icon(tray_icon_image(app)?)
        .icon_as_template(false)
        .menu(&menu)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => {
                if let Some(window) = app.get_webview_window("hud-overlay") {
                    let _ = window.show();
                    let _ = window.set_focus();
                } else if let Some(window) =
                    app.webview_windows().into_iter().find_map(|(_, window)| {
                        crate::commands::window_mgmt::is_editor_window_label(window.label())
                            .then_some(window)
                    })
                {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
                update_tray_menu(app);
            }
            "new-recording" => {
                if should_enable_new_recording(is_recording_active(app), is_hud_visible(app)) {
                    let _ = app.emit("new-recording-from-tray", ());
                }
            }
            "stop" => {
                let _ = app.emit("stop-recording-from-tray", ());
            }
            "quit" => {
                app.exit(0);
            }
            _ => {}
        })
        .build(app)?;

    Ok(())
}

#[cfg(target_os = "macos")]
fn tray_icon_image<R: tauri::Runtime>(_app: &tauri::App<R>) -> Result<Image<'static>, Box<dyn std::error::Error>> {
    Ok(Image::new_owned(
        include_bytes!("../icons/tray-icon.rgba.bin").to_vec(),
        793,
        863,
    ))
}

#[cfg(not(target_os = "macos"))]
fn tray_icon_image<R: tauri::Runtime>(app: &tauri::App<R>) -> Result<Image<'static>, Box<dyn std::error::Error>> {
    app.default_window_icon()
        .cloned()
        .map(into_owned_tray_image)
        .ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::NotFound,
                "default window icon is not configured",
            )
            .into()
        })
}

pub fn update_tray_menu(app: &AppHandle) {
    if let Some(tray) = app.tray_by_id("main") {
        let recording = is_recording_active(app);
        let hud_visible = is_hud_visible(app);

        if let Ok(menu) = build_tray_menu(app, recording, hud_visible) {
            let _ = tray.set_menu(Some(menu));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_borrowed_images_into_owned_images() {
        let rgba = [0_u8, 1, 2, 3, 4, 5, 6, 7];
        let image = Image::new(&rgba, 1, 2);

        let owned = into_owned_tray_image(image);

        assert_eq!(owned.width(), 1);
        assert_eq!(owned.height(), 2);
        assert_eq!(owned.rgba(), &rgba);
        assert!(format!("{owned:?}").contains("Cow::Owned"));
    }

    #[cfg(not(target_os = "macos"))]
    #[test]
    fn non_macos_tray_icon_uses_an_owned_default_window_icon() {
        let app = tauri::test::mock_builder()
            .build(tauri::generate_context!())
            .expect("mock app should build");

        let default_icon = app
            .default_window_icon()
            .expect("mock app should expose a default window icon")
            .clone();
        let tray_icon = tray_icon_image(&app).expect("tray icon should resolve from the app icon");

        assert_eq!(tray_icon.width(), default_icon.width());
        assert_eq!(tray_icon.height(), default_icon.height());
        assert_eq!(tray_icon.rgba(), default_icon.rgba());
        assert!(format!("{tray_icon:?}").contains("Cow::Owned"));
    }

    #[test]
    fn enables_new_recording_only_when_idle_and_hud_hidden() {
        assert!(should_enable_new_recording(false, false));
        assert!(!should_enable_new_recording(true, false));
        assert!(!should_enable_new_recording(false, true));
        assert!(!should_enable_new_recording(true, true));
    }
}
