use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    env, fs,
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Deserialize)]
struct Request {
    id: Option<u64>,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Serialize)]
struct Response {
    id: Option<u64>,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct AppPaths {
    recordings_dir: String,
    screenshots_dir: String,
    projects_dir: String,
    support_dir: String,
}

#[derive(Debug, Clone)]
struct InternalPaths {
    recordings_dir: PathBuf,
    screenshots_dir: PathBuf,
    projects_dir: PathBuf,
    support_dir: PathBuf,
    project_index: PathBuf,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectSummary {
    id: String,
    title: String,
    path: String,
    recording_path: Option<String>,
    screenshot_path: Option<String>,
    source_name: Option<String>,
    created_at: String,
    updated_at: String,
    last_opened_at: String,
    missing: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProjectDocument {
    schema_version: u32,
    title: String,
    recording_path: Option<String>,
    screenshot_path: Option<String>,
    source_name: Option<String>,
    created_at: String,
    updated_at: String,
    #[serde(default)]
    editor_state: Value,
    #[serde(default)]
    recording_session: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RecentScreenshotSummary {
    id: String,
    path: String,
    created_at: String,
    missing: bool,
}

fn main() {
    let exit_code = match run() {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    };

    std::process::exit(exit_code);
}

fn run() -> Result<(), String> {
    let args: Vec<String> = env::args().collect();
    if args.get(1).map(String::as_str) == Some("--oneshot") {
        let method = args
            .get(2)
            .ok_or_else(|| "missing method for --oneshot".to_string())?
            .to_string();
        let params = match args.get(3) {
            Some(raw) => serde_json::from_str(raw).map_err(|err| err.to_string())?,
            None => Value::Object(Default::default()),
        };
        let response = handle_request(Request {
            id: None,
            method,
            params,
        });
        println!(
            "{}",
            serde_json::to_string(&response).map_err(|err| err.to_string())?
        );
        return Ok(());
    }

    service_loop()
}

fn service_loop() -> Result<(), String> {
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = line.map_err(|err| err.to_string())?;
        if line.trim().is_empty() {
            continue;
        }

        let response = match serde_json::from_str::<Request>(&line) {
            Ok(request) => handle_request(request),
            Err(error) => Response {
                id: None,
                ok: false,
                result: None,
                error: Some(error.to_string()),
            },
        };

        writeln!(
            stdout,
            "{}",
            serde_json::to_string(&response).map_err(|err| err.to_string())?
        )
        .map_err(|err| err.to_string())?;
        stdout.flush().map_err(|err| err.to_string())?;
    }

    Ok(())
}

fn handle_request(request: Request) -> Response {
    match handle_method(&request.method, request.params) {
        Ok(result) => Response {
            id: request.id,
            ok: true,
            result: Some(result),
            error: None,
        },
        Err(error) => Response {
            id: request.id,
            ok: false,
            result: None,
            error: Some(error),
        },
    }
}

fn handle_method(method: &str, params: Value) -> Result<Value, String> {
    let paths = InternalPaths::new()?;

    match method {
        "health" => Ok(json!({
            "service": "open-recorder-service",
            "version": env!("CARGO_PKG_VERSION"),
            "platform": "macos"
        })),
        "paths" => {
            paths.ensure()?;
            Ok(serde_json::to_value(paths.public()).map_err(|err| err.to_string())?)
        }
        "prepareRecordingFile" => {
            paths.ensure()?;
            let file_name = string_param(&params, "fileName")
                .unwrap_or_else(|| format!("recording-{}.mov", unix_timestamp()));
            let output = paths.recordings_dir.join(sanitize_file_name(&file_name));
            Ok(json!({ "path": output.to_string_lossy() }))
        }
        "registerRecording" => {
            paths.ensure()?;
            let recording_path = string_param(&params, "path")
                .ok_or_else(|| "registerRecording requires path".to_string())?;
            let source_name = string_param(&params, "sourceName");
            let title = string_param(&params, "title").unwrap_or_else(|| {
                Path::new(&recording_path)
                    .file_stem()
                    .and_then(|stem| stem.to_str())
                    .unwrap_or("Recording")
                    .to_string()
            });
            let editor_state = params
                .get("editorState")
                .cloned()
                .unwrap_or_else(|| json!({ "timelineEdits": { "zoomRegions": [], "trimRegions": [], "annotationRegions": [], "clipSplitTimes": [], "clipSpeeds": {} } }));
            let recording_session = params.get("recordingSession").cloned();
            let summary = save_project_document(
                &paths,
                &title,
                Some(recording_path),
                None,
                source_name,
                editor_state,
                recording_session,
            )?;
            Ok(serde_json::to_value(summary).map_err(|err| err.to_string())?)
        }
        "registerScreenshot" => {
            paths.ensure()?;
            let screenshot_path = string_param(&params, "path")
                .ok_or_else(|| "registerScreenshot requires path".to_string())?;
            let source_name = string_param(&params, "sourceName");
            let title = string_param(&params, "title").unwrap_or_else(|| {
                Path::new(&screenshot_path)
                    .file_stem()
                    .and_then(|stem| stem.to_str())
                    .unwrap_or("Screenshot")
                    .to_string()
            });
            let editor_state = params.get("editorState").cloned().unwrap_or_else(|| {
                json!({
                    "timelineEdits": { "zoomRegions": [], "trimRegions": [], "annotationRegions": [], "clipSplitTimes": [], "clipSpeeds": {} },
                    "screenshot": {}
                })
            });
            let summary = save_project_document(
                &paths,
                &title,
                None,
                Some(screenshot_path.clone()),
                source_name,
                editor_state,
                None,
            )?;
            remember_screenshot(&paths, &screenshot_path)?;
            Ok(serde_json::to_value(summary).map_err(|err| err.to_string())?)
        }
        "saveProject" => {
            paths.ensure()?;
            let title = string_param(&params, "title").unwrap_or_else(|| "Untitled Project".into());
            let recording_path = string_param(&params, "recordingPath");
            let screenshot_path = string_param(&params, "screenshotPath");
            let source_name = string_param(&params, "sourceName");
            let editor_state = params
                .get("editorState")
                .cloned()
                .unwrap_or_else(|| json!({ "timeline": [], "annotations": [] }));
            let recording_session = params.get("recordingSession").cloned();
            let summary = save_project_document(
                &paths,
                &title,
                recording_path,
                screenshot_path,
                source_name,
                editor_state,
                recording_session,
            )?;
            Ok(serde_json::to_value(summary).map_err(|err| err.to_string())?)
        }
        "updateProject" => {
            paths.ensure()?;
            let path = string_param(&params, "path")
                .ok_or_else(|| "updateProject requires path".to_string())?;
            let editor_state = params.get("editorState").cloned();
            let recording_session = params.get("recordingSession").cloned();
            let summary = update_project_document(
                &paths,
                Path::new(&path),
                string_param(&params, "title"),
                string_param(&params, "recordingPath"),
                string_param(&params, "screenshotPath"),
                string_param(&params, "sourceName"),
                editor_state,
                recording_session,
            )?;
            Ok(serde_json::to_value(summary).map_err(|err| err.to_string())?)
        }
        "listProjects" => {
            paths.ensure()?;
            let projects = read_index(&paths)?
                .into_iter()
                .map(|mut item| {
                    item.missing = project_is_missing(&item);
                    item
                })
                .collect::<Vec<_>>();
            Ok(serde_json::to_value(projects).map_err(|err| err.to_string())?)
        }
        "loadProject" => {
            let path = string_param(&params, "path")
                .ok_or_else(|| "loadProject requires path".to_string())?;
            let data = fs::read_to_string(path).map_err(|err| err.to_string())?;
            serde_json::from_str(&data).map_err(|err| err.to_string())
        }
        "forgetProject" => {
            let path = string_param(&params, "path")
                .ok_or_else(|| "forgetProject requires path".to_string())?;
            let mut projects = read_index(&paths)?;
            projects.retain(|project| project.path != path);
            write_index(&paths, &projects)?;
            Ok(json!({ "removed": true }))
        }
        "rememberScreenshot" => {
            paths.ensure()?;
            let path = string_param(&params, "path")
                .ok_or_else(|| "rememberScreenshot requires path".to_string())?;
            remember_screenshot(&paths, &path)?;
            Ok(json!({ "path": path }))
        }
        "listScreenshots" => {
            paths.ensure()?;
            let screenshots = read_screenshot_index(&paths)?
                .into_iter()
                .map(|mut item| {
                    item.missing = !Path::new(&item.path).exists();
                    item
                })
                .collect::<Vec<_>>();
            Ok(serde_json::to_value(screenshots).map_err(|err| err.to_string())?)
        }
        "exportRecording" => {
            let source = string_param(&params, "sourcePath")
                .ok_or_else(|| "exportRecording requires sourcePath".to_string())?;
            let target = string_param(&params, "targetPath")
                .ok_or_else(|| "exportRecording requires targetPath".to_string())?;
            if let Some(parent) = Path::new(&target).parent() {
                fs::create_dir_all(parent).map_err(|err| err.to_string())?;
            }
            fs::copy(&source, &target).map_err(|err| err.to_string())?;
            Ok(json!({ "path": target }))
        }
        _ => Err(format!("unknown method: {method}")),
    }
}

impl InternalPaths {
    fn new() -> Result<Self, String> {
        let home = env::var_os("HOME")
            .map(PathBuf::from)
            .ok_or_else(|| "HOME is not set".to_string())?;
        let support_dir = home
            .join("Library")
            .join("Application Support")
            .join("Open Recorder");
        let projects_dir = support_dir.join("Projects");

        Ok(Self {
            recordings_dir: home.join("Movies").join("Open Recorder"),
            screenshots_dir: home.join("Pictures").join("Open Recorder"),
            project_index: projects_dir.join("index.json"),
            projects_dir,
            support_dir,
        })
    }

    fn ensure(&self) -> Result<(), String> {
        fs::create_dir_all(&self.recordings_dir).map_err(|err| err.to_string())?;
        fs::create_dir_all(&self.screenshots_dir).map_err(|err| err.to_string())?;
        fs::create_dir_all(&self.projects_dir).map_err(|err| err.to_string())?;
        fs::create_dir_all(&self.support_dir).map_err(|err| err.to_string())?;
        if !self.project_index.exists() {
            write_index(self, &[])?;
        }
        Ok(())
    }

    fn public(&self) -> AppPaths {
        AppPaths {
            recordings_dir: self.recordings_dir.to_string_lossy().to_string(),
            screenshots_dir: self.screenshots_dir.to_string_lossy().to_string(),
            projects_dir: self.projects_dir.to_string_lossy().to_string(),
            support_dir: self.support_dir.to_string_lossy().to_string(),
        }
    }
}

fn save_project_document(
    paths: &InternalPaths,
    title: &str,
    recording_path: Option<String>,
    screenshot_path: Option<String>,
    source_name: Option<String>,
    editor_state: Value,
    recording_session: Option<Value>,
) -> Result<ProjectSummary, String> {
    let now = timestamp_string();
    let id = format!("project-{}", unix_timestamp_millis());
    let file_name = format!(
        "{}-{}.openrecorder",
        sanitize_file_name(title),
        unix_timestamp()
    );
    let project_path = paths.projects_dir.join(file_name);
    let document = ProjectDocument {
        schema_version: 2,
        title: title.to_string(),
        recording_path: recording_path.clone(),
        screenshot_path: screenshot_path.clone(),
        source_name: source_name.clone(),
        created_at: now.clone(),
        updated_at: now.clone(),
        editor_state,
        recording_session,
    };

    write_json_pretty(
        &project_path,
        &serde_json::to_value(&document).map_err(|err| err.to_string())?,
    )?;

    let summary = ProjectSummary {
        id,
        title: title.to_string(),
        path: project_path.to_string_lossy().to_string(),
        recording_path,
        screenshot_path,
        source_name,
        created_at: now.clone(),
        updated_at: now.clone(),
        last_opened_at: now,
        missing: false,
    };

    let mut projects = read_index(paths)?;
    projects.retain(|project| project.path != summary.path);
    projects.insert(0, summary.clone());
    write_index(paths, &projects)?;

    Ok(summary)
}

fn update_project_document(
    paths: &InternalPaths,
    project_path: &Path,
    title: Option<String>,
    recording_path: Option<String>,
    screenshot_path: Option<String>,
    source_name: Option<String>,
    editor_state: Option<Value>,
    recording_session: Option<Value>,
) -> Result<ProjectSummary, String> {
    let data = fs::read_to_string(project_path).map_err(|err| err.to_string())?;
    let existing_document: ProjectDocument =
        serde_json::from_str(&data).map_err(|err| err.to_string())?;
    let now = timestamp_string();
    let project_path_string = project_path.to_string_lossy().to_string();

    let title = title.unwrap_or_else(|| existing_document.title.clone());
    let recording_path = recording_path.or_else(|| existing_document.recording_path.clone());
    let screenshot_path = screenshot_path.or_else(|| existing_document.screenshot_path.clone());
    let source_name = source_name.or_else(|| existing_document.source_name.clone());
    let editor_state = editor_state.unwrap_or_else(|| existing_document.editor_state.clone());
    let recording_session = recording_session.or(existing_document.recording_session);

    let document = ProjectDocument {
        schema_version: existing_document.schema_version.max(2),
        title: title.clone(),
        recording_path: recording_path.clone(),
        screenshot_path: screenshot_path.clone(),
        source_name: source_name.clone(),
        created_at: existing_document.created_at.clone(),
        updated_at: now.clone(),
        editor_state,
        recording_session,
    };

    write_json_pretty(
        project_path,
        &serde_json::to_value(&document).map_err(|err| err.to_string())?,
    )?;

    let mut projects = read_index(paths)?;
    let existing_summary = projects
        .iter()
        .find(|project| project.path == project_path_string)
        .cloned();
    projects.retain(|project| project.path != project_path_string);

    let summary = ProjectSummary {
        id: existing_summary
            .as_ref()
            .map(|project| project.id.clone())
            .unwrap_or_else(|| format!("project-{}", unix_timestamp_millis())),
        title,
        path: project_path_string,
        recording_path: recording_path.clone(),
        screenshot_path: screenshot_path.clone(),
        source_name,
        created_at: existing_summary
            .as_ref()
            .map(|project| project.created_at.clone())
            .unwrap_or(existing_document.created_at),
        updated_at: now.clone(),
        last_opened_at: existing_summary
            .map(|project| project.last_opened_at)
            .unwrap_or(now),
        missing: recording_path
            .as_ref()
            .or(screenshot_path.as_ref())
            .map(|path| !Path::new(path).exists())
            .unwrap_or(false),
    };

    projects.insert(0, summary.clone());
    write_index(paths, &projects)?;

    Ok(summary)
}

fn read_index(paths: &InternalPaths) -> Result<Vec<ProjectSummary>, String> {
    if !paths.project_index.exists() {
        return Ok(Vec::new());
    }
    let data = fs::read_to_string(&paths.project_index).map_err(|err| err.to_string())?;
    if data.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str(&data).map_err(|err| err.to_string())
}

fn write_index(paths: &InternalPaths, projects: &[ProjectSummary]) -> Result<(), String> {
    write_json_pretty(
        &paths.project_index,
        &serde_json::to_value(projects).map_err(|err| err.to_string())?,
    )
}

fn project_is_missing(project: &ProjectSummary) -> bool {
    let project_file_missing = !Path::new(&project.path).exists();
    let media_file_missing = project
        .recording_path
        .as_ref()
        .or(project.screenshot_path.as_ref())
        .map(|path| !Path::new(path).exists())
        .unwrap_or(false);
    project_file_missing || media_file_missing
}

fn screenshot_index_path(paths: &InternalPaths) -> PathBuf {
    paths.support_dir.join("screenshots.json")
}

fn remember_screenshot(
    paths: &InternalPaths,
    screenshot_path: &str,
) -> Result<RecentScreenshotSummary, String> {
    let now = timestamp_string();
    let summary = RecentScreenshotSummary {
        id: format!("screenshot-{}", unix_timestamp_millis()),
        path: screenshot_path.to_string(),
        created_at: now,
        missing: !Path::new(screenshot_path).exists(),
    };
    let mut screenshots = read_screenshot_index(paths)?;
    screenshots.retain(|screenshot| screenshot.path != screenshot_path);
    screenshots.insert(0, summary.clone());
    screenshots.truncate(100);
    write_screenshot_index(paths, &screenshots)?;
    Ok(summary)
}

fn read_screenshot_index(paths: &InternalPaths) -> Result<Vec<RecentScreenshotSummary>, String> {
    let index_path = screenshot_index_path(paths);
    let values = read_json_array(&index_path)?;
    let mut screenshots = values
        .into_iter()
        .filter_map(|value| {
            let path = value.get("path")?.as_str()?.to_string();
            let created_at = value
                .get("createdAt")
                .and_then(Value::as_str)
                .unwrap_or("0")
                .to_string();
            Some(RecentScreenshotSummary {
                id: format!(
                    "screenshot-{created_at}-{path}",
                    path = sanitize_file_name(&path)
                ),
                path,
                created_at,
                missing: false,
            })
        })
        .collect::<Vec<_>>();
    screenshots.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(screenshots)
}

fn write_screenshot_index(
    paths: &InternalPaths,
    screenshots: &[RecentScreenshotSummary],
) -> Result<(), String> {
    let values = screenshots
        .iter()
        .map(|screenshot| json!({ "path": screenshot.path, "createdAt": screenshot.created_at }))
        .collect::<Vec<_>>();
    write_json_pretty(&screenshot_index_path(paths), &Value::Array(values))
}

fn read_json_array(path: &Path) -> Result<Vec<Value>, String> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let data = fs::read_to_string(path).map_err(|err| err.to_string())?;
    if data.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str(&data).map_err(|err| err.to_string())
}

fn write_json_pretty(path: &Path, value: &Value) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let data = serde_json::to_vec_pretty(value).map_err(|err| err.to_string())?;
    let tmp_path = path.with_extension(format!(
        "{}.tmp-{}-{}",
        path.extension()
            .and_then(|extension| extension.to_str())
            .unwrap_or("json"),
        std::process::id(),
        unix_timestamp_millis()
    ));
    fs::write(&tmp_path, data).map_err(|err| err.to_string())?;
    fs::rename(&tmp_path, path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        err.to_string()
    })
}

fn string_param(params: &Value, key: &str) -> Option<String> {
    params.get(key)?.as_str().map(ToString::to_string)
}

fn sanitize_file_name(value: &str) -> String {
    let mut sanitized = value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' || ch == '.' {
                ch
            } else {
                '-'
            }
        })
        .collect::<String>();

    while sanitized.contains("--") {
        sanitized = sanitized.replace("--", "-");
    }

    let sanitized = sanitized.trim_matches('-').trim_matches('.');
    if sanitized.is_empty() {
        "open-recorder-file".to_string()
    } else {
        sanitized.to_string()
    }
}

fn timestamp_string() -> String {
    unix_timestamp().to_string()
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn unix_timestamp_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_file_names_for_project_files() {
        assert_eq!(
            sanitize_file_name("Product Demo: Screen/Window.mov"),
            "Product-Demo-Screen-Window.mov"
        );
        assert_eq!(
            sanitize_file_name("Clip\tTitle\nFinal.mov"),
            "Clip-Title-Final.mov"
        );
        assert_eq!(sanitize_file_name("..."), "open-recorder-file");
    }

    #[test]
    fn extracts_string_params_from_json_values() {
        let params = json!({ "path": "/tmp/demo.mov", "count": 2 });

        assert_eq!(
            string_param(&params, "path"),
            Some("/tmp/demo.mov".to_string())
        );
        assert_eq!(string_param(&params, "count"), None);
        assert_eq!(string_param(&params, "missing"), None);
    }

    #[test]
    fn update_project_updates_existing_file_and_preserves_created_at() {
        let paths = test_paths("update-existing");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("demo.openrecorder");
        let recording_path = paths
            .recordings_dir
            .join("demo.mp4")
            .to_string_lossy()
            .to_string();
        let document = json!({
            "schemaVersion": 2,
            "title": "Demo",
            "recordingPath": recording_path,
            "sourceName": "Display 1",
            "createdAt": "100",
            "updatedAt": "100",
            "editorState": { "timelineEdits": { "zoomRegions": [] } }
        });
        write_json_pretty(&project_path, &document).unwrap();
        let summary = ProjectSummary {
            id: "project-existing".to_string(),
            title: "Demo".to_string(),
            path: project_path.to_string_lossy().to_string(),
            recording_path: Some(recording_path.clone()),
            screenshot_path: None,
            source_name: Some("Display 1".to_string()),
            created_at: "100".to_string(),
            updated_at: "100".to_string(),
            last_opened_at: "150".to_string(),
            missing: false,
        };
        write_index(&paths, &[summary]).unwrap();

        let updated = update_project_document(
            &paths,
            &project_path,
            Some("Demo Edited".to_string()),
            Some(recording_path.clone()),
            None,
            Some("Display 1".to_string()),
            Some(json!({ "timelineEdits": { "clipSplitTimes": [1.25] } })),
            None,
        )
        .unwrap();

        let saved: ProjectDocument =
            serde_json::from_str(&fs::read_to_string(&project_path).unwrap()).unwrap();
        assert_eq!(updated.id, "project-existing");
        assert_eq!(updated.title, "Demo Edited");
        assert_eq!(updated.created_at, "100");
        assert_eq!(updated.last_opened_at, "150");
        assert_eq!(saved.title, "Demo Edited");
        assert_eq!(saved.created_at, "100");
        assert_ne!(saved.updated_at, "100");
        assert_eq!(
            saved.editor_state["timelineEdits"]["clipSplitTimes"][0],
            1.25
        );
    }

    #[test]
    fn update_project_does_not_duplicate_index_entries() {
        let paths = test_paths("update-no-duplicates");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("demo.openrecorder");
        let recording_path = paths
            .recordings_dir
            .join("demo.mp4")
            .to_string_lossy()
            .to_string();
        write_json_pretty(
            &project_path,
            &json!({
                "schemaVersion": 2,
                "title": "Demo",
                "recordingPath": recording_path,
                "sourceName": "Display 1",
                "createdAt": "100",
                "updatedAt": "100",
                "editorState": {}
            }),
        )
        .unwrap();

        for index in 0..2 {
            update_project_document(
                &paths,
                &project_path,
                Some(format!("Demo {index}")),
                Some(recording_path.clone()),
                None,
                Some("Display 1".to_string()),
                Some(json!({ "timelineEdits": { "clipSplitTimes": [index] } })),
                None,
            )
            .unwrap();
        }

        let projects = read_index(&paths).unwrap();
        let matching = projects
            .iter()
            .filter(|project| project.path == project_path.to_string_lossy())
            .count();
        assert_eq!(matching, 1);
        assert_eq!(projects[0].title, "Demo 1");
    }

    #[test]
    fn project_is_missing_when_project_document_is_missing() {
        let paths = test_paths("missing-project-document");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("demo.openrecorder");
        let recording_path = paths.recordings_dir.join("demo.mp4");
        fs::write(&recording_path, b"recording").unwrap();

        let summary = ProjectSummary {
            id: "project-existing".to_string(),
            title: "Demo".to_string(),
            path: project_path.to_string_lossy().to_string(),
            recording_path: Some(recording_path.to_string_lossy().to_string()),
            screenshot_path: None,
            source_name: Some("Display 1".to_string()),
            created_at: "100".to_string(),
            updated_at: "100".to_string(),
            last_opened_at: "150".to_string(),
            missing: false,
        };

        assert!(project_is_missing(&summary));
    }

    #[test]
    fn saves_screenshot_projects_and_recent_screenshot_index() {
        let paths = test_paths("screenshot-project");
        paths.ensure().unwrap();
        let screenshot_path = paths
            .screenshots_dir
            .join("shot.png")
            .to_string_lossy()
            .to_string();

        let summary = save_project_document(
            &paths,
            "Shot",
            None,
            Some(screenshot_path.clone()),
            Some("Display 1".to_string()),
            json!({ "screenshot": { "padding": 72 } }),
            None,
        )
        .unwrap();
        remember_screenshot(&paths, &screenshot_path).unwrap();

        let saved: ProjectDocument =
            serde_json::from_str(&fs::read_to_string(&summary.path).unwrap()).unwrap();
        let recent = read_screenshot_index(&paths).unwrap();
        assert_eq!(summary.recording_path, None);
        assert_eq!(summary.screenshot_path, Some(screenshot_path.clone()));
        assert_eq!(saved.screenshot_path, Some(screenshot_path.clone()));
        assert_eq!(saved.editor_state["screenshot"]["padding"], 72);
        assert_eq!(recent[0].path, screenshot_path);
    }

    #[test]
    fn missing_recent_screenshot_index_reads_as_empty() {
        let paths = test_paths("missing-screenshot-index");

        let recent = read_screenshot_index(&paths).unwrap();

        assert!(recent.is_empty());
    }

    #[test]
    fn recent_screenshot_index_keeps_the_latest_one_hundred_items() {
        let paths = test_paths("screenshot-index-limit");
        paths.ensure().unwrap();

        for index in 0..105 {
            remember_screenshot(&paths, &format!("/tmp/shot-{index}.png")).unwrap();
        }

        let recent = read_screenshot_index(&paths).unwrap();
        assert_eq!(recent.len(), 100);
        assert_eq!(recent[0].path, "/tmp/shot-104.png");
        assert_eq!(recent[99].path, "/tmp/shot-5.png");
    }

    #[test]
    fn saves_and_preserves_recording_session_metadata() {
        let paths = test_paths("recording-session");
        paths.ensure().unwrap();
        let recording_path = paths
            .recordings_dir
            .join("demo.mp4")
            .to_string_lossy()
            .to_string();
        let session = json!({
            "screenVideoPath": recording_path,
            "facecamVideoPath": "/tmp/demo.facecam.mov",
            "facecamOffsetMs": -375,
            "sourceName": "Display 1",
            "showCursorOverlay": true,
            "cursorTelemetryPath": "/tmp/demo.cursor.json"
        });

        let summary = save_project_document(
            &paths,
            "Demo",
            Some(recording_path.clone()),
            None,
            Some("Display 1".to_string()),
            json!({ "timelineEdits": { "clipSplitTimes": [] } }),
            Some(session.clone()),
        )
        .unwrap();

        let updated = update_project_document(
            &paths,
            Path::new(&summary.path),
            Some("Demo Edited".to_string()),
            Some(recording_path),
            None,
            Some("Display 1".to_string()),
            Some(json!({ "timelineEdits": { "clipSplitTimes": [1.5] } })),
            None,
        )
        .unwrap();

        let saved: ProjectDocument =
            serde_json::from_str(&fs::read_to_string(&updated.path).unwrap()).unwrap();
        assert_eq!(saved.recording_session, Some(session));
        assert_eq!(
            saved.editor_state["timelineEdits"]["clipSplitTimes"][0],
            1.5
        );
    }

    #[test]
    fn update_project_preserves_screenshot_path_and_updates_state() {
        let paths = test_paths("update-screenshot-project");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("shot.openrecorder");
        let screenshot_path = paths
            .screenshots_dir
            .join("shot.png")
            .to_string_lossy()
            .to_string();
        write_json_pretty(
            &project_path,
            &json!({
                "schemaVersion": 2,
                "title": "Shot",
                "screenshotPath": screenshot_path,
                "sourceName": "Display 1",
                "createdAt": "100",
                "updatedAt": "100",
                "editorState": { "screenshot": { "padding": 56 } }
            }),
        )
        .unwrap();

        let updated = update_project_document(
            &paths,
            &project_path,
            Some("Shot Edited".to_string()),
            None,
            Some(screenshot_path.clone()),
            Some("Display 1".to_string()),
            Some(json!({ "screenshot": { "padding": 96 } })),
            None,
        )
        .unwrap();

        let saved: ProjectDocument =
            serde_json::from_str(&fs::read_to_string(&project_path).unwrap()).unwrap();
        assert_eq!(updated.title, "Shot Edited");
        assert_eq!(updated.screenshot_path, Some(screenshot_path.clone()));
        assert_eq!(updated.recording_path, None);
        assert_eq!(saved.screenshot_path, Some(screenshot_path));
        assert_eq!(saved.editor_state["screenshot"]["padding"], 96);
    }

    fn test_paths(name: &str) -> InternalPaths {
        let root = env::temp_dir().join(format!(
            "open-recorder-service-{name}-{}",
            unix_timestamp_millis()
        ));
        InternalPaths {
            recordings_dir: root.join("Recordings"),
            screenshots_dir: root.join("Screenshots"),
            projects_dir: root.join("Projects"),
            support_dir: root.join("Support"),
            project_index: root.join("Projects").join("index.json"),
        }
    }
}
