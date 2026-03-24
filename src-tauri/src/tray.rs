use tauri::{
    image::Image,
    menu::{MenuBuilder, MenuItemBuilder},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager,
};

pub fn setup_tray(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let open_item = MenuItemBuilder::with_id("open", "Open").build(app)?;
    let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(app)?;

    let menu = MenuBuilder::new(app)
        .item(&open_item)
        .separator()
        .item(&quit_item)
        .build()?;

    TrayIconBuilder::with_id("main")
        .icon(tray_icon_image(app)?)
        .icon_as_template(false)
        .menu(&menu)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => {
                if let Some(window) = app.get_webview_window("hud-overlay") {
                    let _ = window.show();
                    let _ = window.set_focus();
                } else if let Some(window) = app.get_webview_window("editor") {
                    let _ = window.show();
                    let _ = window.set_focus();
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
fn tray_icon_image(_app: &tauri::App) -> Result<Image<'static>, Box<dyn std::error::Error>> {
    Ok(Image::new_owned(
        include_bytes!("../icons/tray-icon.rgba.bin").to_vec(),
        793,
        863,
    ))
}

#[cfg(not(target_os = "macos"))]
fn tray_icon_image(app: &tauri::App) -> Result<Image<'static>, Box<dyn std::error::Error>> {
    app.default_window_icon().cloned().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "default window icon is not configured",
        )
        .into()
    })
}

pub fn update_tray_menu(app: &AppHandle, recording: bool) {
    // Rebuild tray menu based on recording state
    if let Some(tray) = app.tray_by_id("main") {
        if recording {
            if let Ok(stop_item) = MenuItemBuilder::with_id("stop", "Stop Recording").build(app) {
                if let Ok(quit_item) = MenuItemBuilder::with_id("quit", "Quit").build(app) {
                    if let Ok(menu) = MenuBuilder::new(app)
                        .item(&stop_item)
                        .separator()
                        .item(&quit_item)
                        .build()
                    {
                        let _ = tray.set_menu(Some(menu));
                    }
                }
            }
        } else {
            if let Ok(open_item) = MenuItemBuilder::with_id("open", "Open").build(app) {
                if let Ok(quit_item) = MenuItemBuilder::with_id("quit", "Quit").build(app) {
                    if let Ok(menu) = MenuBuilder::new(app)
                        .item(&open_item)
                        .separator()
                        .item(&quit_item)
                        .build()
                    {
                        let _ = tray.set_menu(Some(menu));
                    }
                }
            }
        }
    }
}
