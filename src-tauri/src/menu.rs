use tauri::{
    menu::{MenuBuilder, MenuItemBuilder, SubmenuBuilder},
    Emitter, Manager,
};

pub fn setup_menu(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    // App menu (macOS application menu — appears under the app name in the top bar)
    let app_name = app.package_info().name.clone();
    let check_updates =
        MenuItemBuilder::with_id("menu-check-updates", "Check for Updates...").build(app)?;

    let app_menu = SubmenuBuilder::new(app, &app_name)
        .about(None)
        .separator()
        .item(&check_updates)
        .separator()
        .services()
        .separator()
        .hide()
        .hide_others()
        .show_all()
        .separator()
        .quit()
        .build()?;

    // File menu
    let open_video =
        MenuItemBuilder::with_id("menu-open-video-file", "Open Video File...").build(app)?;
    let load_project = MenuItemBuilder::with_id("menu-load-project", "Open Project...")
        .accelerator("CmdOrCtrl+O")
        .build(app)?;
    let save_project = MenuItemBuilder::with_id("menu-save-project", "Save Project")
        .accelerator("CmdOrCtrl+S")
        .build(app)?;
    let save_project_as = MenuItemBuilder::with_id("menu-save-project-as", "Save Project As...")
        .accelerator("CmdOrCtrl+Shift+S")
        .build(app)?;

    let file_menu = SubmenuBuilder::new(app, "File")
        .item(&open_video)
        .item(&load_project)
        .separator()
        .item(&save_project)
        .item(&save_project_as)
        .separator()
        .close_window()
        .build()?;

    // Edit menu
    let edit_menu = SubmenuBuilder::new(app, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;

    // View menu
    let view_menu = SubmenuBuilder::new(app, "View").fullscreen().build()?;

    // Window menu
    let window_menu = SubmenuBuilder::new(app, "Window").minimize().build()?;

    // Help menu
    let help_menu = SubmenuBuilder::new(app, "Help").build()?;

    let menu = MenuBuilder::new(app)
        .item(&app_menu)
        .item(&file_menu)
        .item(&edit_menu)
        .item(&view_menu)
        .item(&window_menu)
        .item(&help_menu)
        .build()?;

    app.set_menu(menu)?;

    // Handle menu events
    app.on_menu_event(move |app, event| match event.id().as_ref() {
        "menu-open-video-file" => {
            let _ = app.emit("menu-open-video-file", ());
        }
        "menu-load-project" => {
            let _ = app.emit("menu-load-project", ());
        }
        "menu-save-project" => {
            let _ = app.emit("menu-save-project", ());
        }
        "menu-save-project-as" => {
            let _ = app.emit("menu-save-project-as", ());
        }
        "menu-check-updates" => {
            let focused_window = app.webview_windows().into_iter().find_map(|(_, window)| {
                let label = window.label().to_string();
                let can_handle_updates = label == "editor" || label == "image-editor";

                match (can_handle_updates, window.is_focused()) {
                    (true, Ok(true)) => Some(window),
                    _ => None,
                }
            });

            if let Some(window) = focused_window {
                let _ = window.emit("menu-check-updates", ());
            } else if let Some(window) = app.get_webview_window("editor") {
                let _ = window.emit("menu-check-updates", ());
            } else if let Some(window) = app.get_webview_window("image-editor") {
                let _ = window.emit("menu-check-updates", ());
            } else {
                let _ = app.emit("menu-check-updates", ());
            }
        }
        _ => {}
    });

    Ok(())
}
