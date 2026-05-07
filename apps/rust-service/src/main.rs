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
    source_name: Option<String>,
    created_at: String,
    updated_at: String,
    #[serde(default)]
    editor_state: Value,
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
            let summary = save_project_document(
                &paths,
                &title,
                Some(recording_path),
                source_name,
                json!({ "timeline": [], "annotations": [], "exportPreset": "source" }),
            )?;
            Ok(serde_json::to_value(summary).map_err(|err| err.to_string())?)
        }
        "saveProject" => {
            paths.ensure()?;
            let title = string_param(&params, "title").unwrap_or_else(|| "Untitled Project".into());
            let recording_path = string_param(&params, "recordingPath");
            let source_name = string_param(&params, "sourceName");
            let editor_state = params
                .get("editorState")
                .cloned()
                .unwrap_or_else(|| json!({ "timeline": [], "annotations": [] }));
            let summary =
                save_project_document(&paths, &title, recording_path, source_name, editor_state)?;
            Ok(serde_json::to_value(summary).map_err(|err| err.to_string())?)
        }
        "listProjects" => {
            paths.ensure()?;
            let projects = read_index(&paths)?
                .into_iter()
                .map(|mut item| {
                    item.missing = item
                        .recording_path
                        .as_ref()
                        .map(|path| !Path::new(path).exists())
                        .unwrap_or(false);
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
            let index_path = paths.support_dir.join("screenshots.json");
            let mut screenshots = read_json_array(&index_path)?;
            screenshots.push(json!({ "path": path, "createdAt": timestamp_string() }));
            write_json_pretty(&index_path, &Value::Array(screenshots))?;
            Ok(json!({ "path": path }))
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
    source_name: Option<String>,
    editor_state: Value,
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
        source_name: source_name.clone(),
        created_at: now.clone(),
        updated_at: now.clone(),
        editor_state,
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
    fs::write(path, data).map_err(|err| err.to_string())
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
}
