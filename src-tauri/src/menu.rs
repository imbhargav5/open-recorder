use tauri::{
    menu::{MenuBuilder, MenuItemBuilder, SubmenuBuilder},
    Emitter,
};

pub fn setup_menu(app: &tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    // File menu
    let load_project = MenuItemBuilder::with_id("menu-load-project", "Open Project...")
        .accelerator("CmdOrCtrl+O")
        .build(app)?;
    let save_project = MenuItemBuilder::with_id("menu-save-project", "Save Project")
        .accelerator("CmdOrCtrl+S")
        .build(app)?;
    let save_project_as =
        MenuItemBuilder::with_id("menu-save-project-as", "Save Project As...")
            .accelerator("CmdOrCtrl+Shift+S")
            .build(app)?;

    let file_menu = SubmenuBuilder::new(app, "File")
        .item(&load_project)
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
    let view_menu = SubmenuBuilder::new(app, "View")
        .fullscreen()
        .build()?;

    // Window menu
    let window_menu = SubmenuBuilder::new(app, "Window")
        .minimize()
        .build()?;

    let menu = MenuBuilder::new(app)
        .item(&file_menu)
        .item(&edit_menu)
        .item(&view_menu)
        .item(&window_menu)
        .build()?;

    app.set_menu(menu)?;

    // Handle menu events
    app.on_menu_event(move |app, event| {
        match event.id().as_ref() {
            "menu-load-project" => {
                let _ = app.emit("menu-load-project", ());
            }
            "menu-save-project" => {
                let _ = app.emit("menu-save-project", ());
            }
            "menu-save-project-as" => {
                let _ = app.emit("menu-save-project-as", ());
            }
            _ => {}
        }
    });

    Ok(())
}
