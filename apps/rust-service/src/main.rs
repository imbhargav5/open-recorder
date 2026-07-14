use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::HashSet,
    env, fs,
    io::{self, BufRead, Write},
    os::fd::AsRawFd,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

static UNIQUE_SUFFIX_COUNTER: AtomicU64 = AtomicU64::new(0);

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

struct DirectoryLock {
    file: fs::File,
}

impl DirectoryLock {
    fn acquire(path: PathBuf) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        let file = fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&path)
            .map_err(|error| error.to_string())?;
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            let result = unsafe { flock(file.as_raw_fd(), LOCK_EXCLUSIVE | LOCK_NONBLOCKING) };
            if result == 0 {
                return Ok(Self { file });
            }
            let error = io::Error::last_os_error();
            if error.kind() != io::ErrorKind::WouldBlock {
                return Err(error.to_string());
            }
            if Instant::now() >= deadline {
                return Err(format!(
                    "timed out waiting for index lock {}",
                    path.to_string_lossy()
                ));
            }
            thread::sleep(Duration::from_millis(10));
        }
    }
}

impl Drop for DirectoryLock {
    fn drop(&mut self) {
        let _ = unsafe { flock(self.file.as_raw_fd(), LOCK_UNLOCK) };
    }
}

const LOCK_EXCLUSIVE: i32 = 2;
const LOCK_NONBLOCKING: i32 = 4;
const LOCK_UNLOCK: i32 = 8;

unsafe extern "C" {
    fn flock(file_descriptor: i32, operation: i32) -> i32;
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
    #[serde(default)]
    availability: ProjectAvailability,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum ProjectAvailability {
    #[default]
    Available,
    MissingProject,
    MissingMedia,
    MissingProjectAndMedia,
    Unavailable,
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
                .unwrap_or_else(default_timeline_editor_state);
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
            // Do this before creating the project. If the screenshot index is
            // unavailable, the caller can safely recover without duplicating a
            // project that was actually persisted before the error surfaced.
            remember_screenshot(&paths, &screenshot_path)?;
            let summary = save_project_document(
                &paths,
                &title,
                None,
                Some(screenshot_path.clone()),
                source_name,
                editor_state,
                None,
            )?;
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
                .unwrap_or_else(default_timeline_editor_state);
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
            let projects = read_index_recovering_orphans(&paths)?
                .into_iter()
                .map(|mut item| {
                    item.availability = project_availability(&item);
                    item.missing = item.availability != ProjectAvailability::Available;
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
            forget_project(&paths, &path)?;
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
        {
            // A fresh install can launch more than one short-lived service process at once.
            // Initialize the shared index under the same cross-process lock used for mutations
            // so a late initializer cannot replace projects written by an earlier process.
            let _index_lock = DirectoryLock::acquire(self.support_dir.join(".project-index.lock"))?;
            if !self.project_index.exists() {
                write_index(self, &[])?;
            }
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
    let _index_lock = DirectoryLock::acquire(paths.support_dir.join(".project-index.lock"))?;
    let now = timestamp_string();
    let unique_suffix = unique_suffix();
    let id = format!("project-{unique_suffix}");
    let file_name = format!(
        "{}-{}.openrecorder",
        sanitize_file_name(title),
        unique_suffix
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
    let availability = project_availability_for_paths(
        &project_path,
        recording_path.as_ref(),
        screenshot_path.as_ref(),
    );
    let missing = availability != ProjectAvailability::Available;

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
        missing,
        availability,
    };

    let index_result = (|| {
        let mut projects = read_index(paths)?;
        projects.retain(|project| project.path != summary.path);
        projects.insert(0, summary.clone());
        write_index(paths, &projects)
    })();
    if let Err(error) = index_result {
        let _ = fs::remove_file(&project_path);
        return Err(error);
    }

    Ok(summary)
}

#[allow(
    clippy::too_many_arguments,
    reason = "mirrors optional update payload fields"
)]
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
    let _index_lock = DirectoryLock::acquire(paths.support_dir.join(".project-index.lock"))?;
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

    let availability = project_availability_for_paths(
        project_path,
        recording_path.as_ref(),
        screenshot_path.as_ref(),
    );
    let missing = availability != ProjectAvailability::Available;

    // Validate and prepare the index mutation before changing the authoritative
    // project document. If the second atomic commit fails, restore the exact
    // original bytes so callers never receive a misleading partial failure.
    let mut projects = read_index(paths)?;
    let existing_summary = projects
        .iter()
        .find(|project| project.path == project_path_string)
        .cloned();
    let should_mark_as_recovered = existing_summary.is_none();
    projects.retain(|project| project.path != project_path_string);

    let summary = ProjectSummary {
        id: existing_summary
            .as_ref()
            .map(|project| project.id.clone())
            .unwrap_or_else(|| format!("project-{}", unique_suffix())),
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
        missing,
        availability,
    };

    projects.insert(0, summary.clone());
    let document_value = serde_json::to_value(&document).map_err(|err| err.to_string())?;
    let recovery_marker = recovery_marker_path(project_path);
    if should_mark_as_recovered {
        write_bytes_atomically(&recovery_marker, b"")?;
    }
    if let Err(project_error) = write_json_pretty(project_path, &document_value) {
        if should_mark_as_recovered {
            let _ = fs::remove_file(&recovery_marker);
        }
        return Err(project_error);
    }
    if let Err(index_error) = write_index(paths, &projects) {
        if should_mark_as_recovered {
            let _ = fs::remove_file(&recovery_marker);
        }
        if let Err(rollback_error) = write_bytes_atomically(project_path, data.as_bytes()) {
            return Err(format!(
                "{index_error}; restoring the original project also failed: {rollback_error}"
            ));
        }
        return Err(index_error);
    }

    Ok(summary)
}

fn forget_project(paths: &InternalPaths, path: &str) -> Result<(), String> {
    let _index_lock = DirectoryLock::acquire(paths.support_dir.join(".project-index.lock"))?;
    let original_projects = read_index(paths)?;
    let mut projects = original_projects.clone();
    projects.retain(|project| project.path != path);
    let mut forgotten_paths = read_forgotten_project_paths(paths)?;
    forgotten_paths.insert(project_path_identity(Path::new(path)));

    write_index(paths, &projects)?;
    if let Err(error) = write_forgotten_project_paths(paths, &forgotten_paths) {
        if let Err(rollback_error) = write_index(paths, &original_projects) {
            return Err(format!(
                "{error}; restoring the project index also failed: {rollback_error}"
            ));
        }
        return Err(error);
    }
    let _ = fs::remove_file(recovery_marker_path(Path::new(path)));
    Ok(())
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

fn read_index_recovering_orphans(paths: &InternalPaths) -> Result<Vec<ProjectSummary>, String> {
    let _index_lock = DirectoryLock::acquire(paths.support_dir.join(".project-index.lock"))?;
    let (mut projects, recovered_from_backup, recover_all_project_files, primary_error) =
        match read_index(paths) {
            Ok(projects) => {
                if project_index_backup_needs_sync(paths)
                    && let Ok(data) = serde_json::to_vec_pretty(&projects)
                {
                    let _ = write_bytes_atomically(&project_index_backup_path(paths), &data);
                }
                (projects, false, false, None)
            }
            Err(primary_error) => match read_index_backup(paths) {
                // A backup write can fail after the authoritative primary commit. Treat any
                // backup as a recovery hint, then reconcile it with tombstones and every valid
                // project document before repairing the primary index.
                Ok(projects) => (projects, true, true, Some(primary_error)),
                Err(_) => (Vec::new(), false, true, Some(primary_error)),
            },
        };
    let forgotten_paths = if recover_all_project_files {
        read_forgotten_project_paths(paths)?
    } else {
        HashSet::new()
    };
    let mut removed_tombstoned_backup_entry = false;
    if recovered_from_backup {
        projects.retain(|project| {
            let keep = !forgotten_paths.contains(&project_path_identity(Path::new(&project.path)));
            removed_tombstoned_backup_entry |= !keep;
            keep
        });
    }
    let mut known_paths = projects
        .iter()
        .map(|project| project.path.clone())
        .collect::<HashSet<_>>();
    let mut found_tombstoned_project = false;
    let mut recovered = Vec::new();

    for entry in fs::read_dir(&paths.projects_dir).map_err(|error| error.to_string())? {
        let entry = entry.map_err(|error| error.to_string())?;
        let candidate_path = entry.path();
        let (project_path, marker_path) = if candidate_path
            .extension()
            .and_then(|extension| extension.to_str())
            == Some("recovery")
        {
            (candidate_path.with_extension(""), Some(candidate_path))
        } else if recover_all_project_files
            && candidate_path
                .extension()
                .and_then(|extension| extension.to_str())
                == Some("openrecorder")
        {
            (candidate_path, None)
        } else {
            continue;
        };
        if project_path
            .extension()
            .and_then(|extension| extension.to_str())
            != Some("openrecorder")
        {
            continue;
        }
        if recover_all_project_files
            && marker_path.is_none()
            && forgotten_paths.contains(&project_path_identity(&project_path))
        {
            found_tombstoned_project = true;
            continue;
        }
        let project_path_string = project_path.to_string_lossy().to_string();
        if !known_paths.insert(project_path_string.clone()) {
            continue;
        }
        let Ok(data) = fs::read_to_string(&project_path) else {
            continue;
        };
        let Ok(document) = serde_json::from_str::<ProjectDocument>(&data) else {
            continue;
        };
        let availability = project_availability_for_paths(
            &project_path,
            document.recording_path.as_ref(),
            document.screenshot_path.as_ref(),
        );
        let missing = availability != ProjectAvailability::Available;
        let stable_name = project_path
            .file_stem()
            .and_then(|name| name.to_str())
            .unwrap_or("project");
        recovered.push(ProjectSummary {
            id: format!("project-recovered-{stable_name}"),
            title: document.title,
            path: project_path_string,
            recording_path: document.recording_path,
            screenshot_path: document.screenshot_path,
            source_name: document.source_name,
            created_at: document.created_at,
            updated_at: document.updated_at.clone(),
            last_opened_at: document.updated_at,
            missing,
            availability,
        });
    }

    if !recovered.is_empty() {
        recovered.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
        recovered.append(&mut projects);
        write_index(paths, &recovered)?;
        projects = recovered;
    } else if recover_all_project_files {
        if recovered_from_backup || removed_tombstoned_backup_entry || found_tombstoned_project {
            write_index(paths, &projects)?;
        } else {
            return Err(primary_error.unwrap_or_else(|| "project index is unavailable".to_string()));
        }
    }
    Ok(projects)
}

fn recovery_marker_path(project_path: &Path) -> PathBuf {
    let mut marker_path = project_path.as_os_str().to_os_string();
    marker_path.push(".recovery");
    PathBuf::from(marker_path)
}

fn write_index(paths: &InternalPaths, projects: &[ProjectSummary]) -> Result<(), String> {
    let data = serde_json::to_vec_pretty(projects).map_err(|error| error.to_string())?;
    write_bytes_atomically(&paths.project_index, &data)?;
    // The primary commit is authoritative. Keep a same-generation recovery copy,
    // but do not report failure after the primary index has already committed.
    let _ = write_bytes_atomically(&project_index_backup_path(paths), &data);
    Ok(())
}

fn read_index_backup(paths: &InternalPaths) -> Result<Vec<ProjectSummary>, String> {
    let backup_path = project_index_backup_path(paths);
    if !backup_path.exists() {
        return Err("project index backup is missing".to_string());
    }
    let data = fs::read_to_string(backup_path).map_err(|error| error.to_string())?;
    serde_json::from_str(&data).map_err(|error| error.to_string())
}

fn project_index_backup_path(paths: &InternalPaths) -> PathBuf {
    paths.projects_dir.join("index.backup.json")
}

fn project_index_backup_needs_sync(paths: &InternalPaths) -> bool {
    let Ok(primary) = fs::metadata(&paths.project_index) else {
        return false;
    };
    let Ok(backup) = fs::metadata(project_index_backup_path(paths)) else {
        return true;
    };
    if primary.len() != backup.len() {
        return true;
    }
    match (primary.modified(), backup.modified()) {
        (Ok(primary_modified), Ok(backup_modified)) => primary_modified > backup_modified,
        _ => false,
    }
}

fn forgotten_project_paths_path(paths: &InternalPaths) -> PathBuf {
    paths.support_dir.join("forgotten-projects.json")
}

fn read_forgotten_project_paths(paths: &InternalPaths) -> Result<HashSet<String>, String> {
    let path = forgotten_project_paths_path(paths);
    if !path.exists() {
        return Ok(HashSet::new());
    }
    let data = fs::read_to_string(path).map_err(|error| error.to_string())?;
    let paths = serde_json::from_str::<Vec<String>>(&data).map_err(|error| error.to_string())?;
    Ok(paths.into_iter().collect())
}

fn write_forgotten_project_paths(
    paths: &InternalPaths,
    forgotten_paths: &HashSet<String>,
) -> Result<(), String> {
    let mut values = forgotten_paths.iter().cloned().collect::<Vec<_>>();
    values.sort();
    let data = serde_json::to_vec_pretty(&values).map_err(|error| error.to_string())?;
    write_bytes_atomically(&forgotten_project_paths_path(paths), &data)
}

fn project_path_identity(path: &Path) -> String {
    fs::canonicalize(path)
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .to_string()
}

#[cfg(test)]
fn project_is_missing(project: &ProjectSummary) -> bool {
    project_availability(project) != ProjectAvailability::Available
}

fn project_availability(project: &ProjectSummary) -> ProjectAvailability {
    project_availability_for_paths(
        Path::new(&project.path),
        project.recording_path.as_ref(),
        project.screenshot_path.as_ref(),
    )
}

fn project_availability_for_paths(
    project_path: &Path,
    recording_path: Option<&String>,
    screenshot_path: Option<&String>,
) -> ProjectAvailability {
    let project_file = project_file_state(project_path);
    let media_file = project_media_state(recording_path, screenshot_path);
    if project_file == FileState::Unusable || media_file == FileState::Unusable {
        return ProjectAvailability::Unavailable;
    }
    match (
        project_file == FileState::Missing,
        media_file == FileState::Missing,
    ) {
        (false, false) => ProjectAvailability::Available,
        (true, false) => ProjectAvailability::MissingProject,
        (false, true) => ProjectAvailability::MissingMedia,
        (true, true) => ProjectAvailability::MissingProjectAndMedia,
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum FileState {
    Available,
    Missing,
    Unusable,
}

fn project_file_state(project_path: &Path) -> FileState {
    let Ok(metadata) = fs::metadata(project_path) else {
        return FileState::Missing;
    };
    if !metadata.is_file() {
        return FileState::Unusable;
    }
    let Ok(data) = fs::read_to_string(project_path) else {
        return FileState::Unusable;
    };
    if serde_json::from_str::<ProjectDocument>(&data).is_err() {
        return FileState::Unusable;
    }
    FileState::Available
}

fn project_media_state(
    recording_path: Option<&String>,
    screenshot_path: Option<&String>,
) -> FileState {
    let media_paths = recording_path
        .into_iter()
        .chain(screenshot_path)
        .collect::<Vec<_>>();
    if media_paths.is_empty() {
        return FileState::Unusable;
    }
    let mut state = FileState::Available;
    for path in media_paths {
        match fs::metadata(path) {
            Err(_) => state = FileState::Missing,
            Ok(metadata) if !metadata.is_file() => return FileState::Unusable,
            Ok(_) if fs::File::open(path).is_err() => return FileState::Unusable,
            Ok(_) => {}
        }
    }
    state
}

fn screenshot_index_path(paths: &InternalPaths) -> PathBuf {
    paths.support_dir.join("screenshots.json")
}

fn remember_screenshot(
    paths: &InternalPaths,
    screenshot_path: &str,
) -> Result<RecentScreenshotSummary, String> {
    let _index_lock = DirectoryLock::acquire(paths.support_dir.join(".screenshot-index.lock"))?;
    let now = timestamp_string();
    let summary = RecentScreenshotSummary {
        id: format!("screenshot-{}", unique_suffix()),
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
    screenshots
        .sort_by_key(|screenshot| std::cmp::Reverse(created_at_sort_key(&screenshot.created_at)));
    Ok(screenshots)
}

fn created_at_sort_key(created_at: &str) -> u64 {
    created_at.parse::<u64>().unwrap_or(0)
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
    let data = serde_json::to_vec_pretty(value).map_err(|err| err.to_string())?;
    write_bytes_atomically(path, &data)
}

fn write_bytes_atomically(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let tmp_path = path.with_extension(format!(
        "{}.tmp-{}",
        path.extension()
            .and_then(|extension| extension.to_str())
            .unwrap_or("json"),
        unique_suffix()
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

fn default_timeline_editor_state() -> Value {
    json!({
        "timelineEdits": {
            "zoomRegions": [],
            "trimRegions": [],
            "annotationRegions": [],
            "clipSplitTimes": [],
            "clipSpeeds": {}
        }
    })
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

fn unique_suffix() -> String {
    format!(
        "{}-{}-{}",
        unix_timestamp_millis(),
        std::process::id(),
        UNIQUE_SUFFIX_COUNTER.fetch_add(1, Ordering::Relaxed)
    )
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
    fn index_file_lock_excludes_contenders_and_releases_with_its_owner() {
        let paths = test_paths("advisory-index-lock");
        fs::create_dir_all(&paths.support_dir).unwrap();
        let lock_path = paths.support_dir.join(".project-index.lock");
        let first_owner = DirectoryLock::acquire(lock_path.clone()).unwrap();
        let acquired = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let acquired_by_contender = acquired.clone();
        let contender = thread::spawn(move || {
            let _second_owner = DirectoryLock::acquire(lock_path).unwrap();
            acquired_by_contender.store(true, Ordering::SeqCst);
        });

        thread::sleep(Duration::from_millis(50));
        assert!(!acquired.load(Ordering::SeqCst));
        drop(first_owner);
        contender.join().unwrap();
        assert!(acquired.load(Ordering::SeqCst));
    }

    #[test]
    fn default_timeline_editor_state_matches_project_editor_schema() {
        assert_eq!(
            default_timeline_editor_state(),
            json!({
                "timelineEdits": {
                    "zoomRegions": [],
                    "trimRegions": [],
                    "annotationRegions": [],
                    "clipSplitTimes": [],
                    "clipSpeeds": {}
                }
            })
        );
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
            availability: ProjectAvailability::Available,
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
    fn update_project_does_not_mutate_document_when_index_is_invalid() {
        let paths = test_paths("update-invalid-index");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("demo.openrecorder");
        let recording_path = paths.recordings_dir.join("demo.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let original = json!({
            "schemaVersion": 2,
            "title": "Before",
            "recordingPath": recording_path,
            "sourceName": "Display",
            "createdAt": "100",
            "updatedAt": "100",
            "editorState": { "timelineEdits": {} }
        });
        write_json_pretty(&project_path, &original).unwrap();
        fs::write(&paths.project_index, b"not valid json").unwrap();

        let result = update_project_document(
            &paths,
            &project_path,
            Some("After".to_string()),
            None,
            None,
            None,
            None,
            None,
        );

        assert!(result.is_err());
        let persisted: Value =
            serde_json::from_str(&fs::read_to_string(project_path).unwrap()).unwrap();
        assert_eq!(persisted, original);
    }

    #[test]
    fn update_project_marks_an_explicitly_readopted_document_for_future_recovery() {
        let paths = test_paths("update-readopts-forgotten-project");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("readopted.openrecorder");
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        write_json_pretty(
            &project_path,
            &json!({
                "schemaVersion": 2,
                "title": "Readopted",
                "recordingPath": recording_path,
                "sourceName": "Display",
                "createdAt": "100",
                "updatedAt": "100",
                "editorState": { "timelineEdits": {} }
            }),
        )
        .unwrap();
        write_forgotten_project_paths(
            &paths,
            &HashSet::from([project_path_identity(&project_path)]),
        )
        .unwrap();

        update_project_document(
            &paths,
            &project_path,
            Some("Readopted Again".to_string()),
            None,
            None,
            None,
            None,
            None,
        )
        .unwrap();
        assert!(recovery_marker_path(&project_path).exists());
        fs::write(&paths.project_index, b"corrupt primary").unwrap();
        fs::write(project_index_backup_path(&paths), b"corrupt backup").unwrap();

        let salvaged = read_index_recovering_orphans(&paths).unwrap();
        assert_eq!(salvaged.len(), 1);
        assert_eq!(salvaged[0].title, "Readopted Again");
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
            availability: ProjectAvailability::Available,
        };

        assert!(project_is_missing(&summary));
    }

    #[test]
    fn concurrent_project_registration_preserves_every_entry_and_unique_id() {
        let paths = test_paths("concurrent-project-registration");
        paths.ensure().unwrap();
        let project_count = 24;
        let handles = (0..project_count)
            .map(|index| {
                let paths = paths.clone();
                thread::spawn(move || {
                    let recording_path =
                        paths.recordings_dir.join(format!("recording-{index}.mp4"));
                    fs::write(&recording_path, b"recording").unwrap();
                    save_project_document(
                        &paths,
                        &format!("Recording {index}"),
                        Some(recording_path.to_string_lossy().to_string()),
                        None,
                        Some("Display".to_string()),
                        default_timeline_editor_state(),
                        None,
                    )
                    .unwrap()
                })
            })
            .collect::<Vec<_>>();

        let summaries = handles
            .into_iter()
            .map(|handle| handle.join().unwrap())
            .collect::<Vec<_>>();
        let indexed = read_index(&paths).unwrap();
        let unique_ids = summaries
            .iter()
            .map(|summary| summary.id.as_str())
            .collect::<std::collections::HashSet<_>>();
        let unique_paths = indexed
            .iter()
            .map(|summary| summary.path.as_str())
            .collect::<std::collections::HashSet<_>>();

        assert_eq!(indexed.len(), project_count);
        assert_eq!(unique_ids.len(), project_count);
        assert_eq!(unique_paths.len(), project_count);
    }

    #[test]
    fn failed_index_update_removes_the_new_project_document() {
        let paths = test_paths("failed-index-update-cleanup");
        paths.ensure().unwrap();
        fs::remove_file(&paths.project_index).unwrap();
        fs::create_dir(&paths.project_index).unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();

        let result = save_project_document(
            &paths,
            "Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        );

        assert!(result.is_err());
        let project_files = fs::read_dir(&paths.projects_dir)
            .unwrap()
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension().and_then(|extension| extension.to_str()) == Some("openrecorder")
            })
            .collect::<Vec<_>>();
        assert!(project_files.is_empty());
    }

    #[test]
    fn list_projects_recovers_an_unindexed_project_file_without_duplication() {
        let paths = test_paths("recover-unindexed-project");
        paths.ensure().unwrap();
        let recording_path = paths.recordings_dir.join("recovered.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let project_path = paths.projects_dir.join("recovered-local.openrecorder");
        write_json_pretty(
            &project_path,
            &json!({
                "schemaVersion": 2,
                "title": "Recovered Recording",
                "recordingPath": recording_path,
                "sourceName": "Display 1",
                "createdAt": "2026-07-11T00:00:00Z",
                "updatedAt": "2026-07-11T01:00:00Z",
                "editorState": { "timelineEdits": {} }
            }),
        )
        .unwrap();
        let recovery_marker = recovery_marker_path(&project_path);
        fs::write(&recovery_marker, b"").unwrap();
        fs::write(&paths.project_index, b"malformed index").unwrap();

        let first = read_index_recovering_orphans(&paths).unwrap();
        let second = read_index_recovering_orphans(&paths).unwrap();

        assert_eq!(first.len(), 1);
        assert_eq!(first[0].title, "Recovered Recording");
        assert_eq!(first[0].path, project_path.to_string_lossy());
        assert_eq!(first[0].availability, ProjectAvailability::Available);
        assert_eq!(second.len(), 1);
        assert_eq!(read_index(&paths).unwrap().len(), 1);
        assert!(recovery_marker.exists());
    }

    #[test]
    fn list_projects_does_not_readd_an_unmarked_forgotten_project() {
        let paths = test_paths("preserve-forgotten-project");
        paths.ensure().unwrap();
        let project_path = paths
            .projects_dir
            .join("intentionally-forgotten.openrecorder");
        write_json_pretty(
            &project_path,
            &json!({
                "schemaVersion": 2,
                "title": "Forgotten Recording",
                "recordingPath": null,
                "sourceName": null,
                "createdAt": "100",
                "updatedAt": "100",
                "editorState": { "timelineEdits": {} }
            }),
        )
        .unwrap();

        let projects = read_index_recovering_orphans(&paths).unwrap();

        assert!(projects.is_empty());
        assert!(project_path.exists());
    }

    #[test]
    fn catastrophic_index_salvage_honors_forgotten_project_tombstones() {
        let paths = test_paths("salvage-forgotten-project");
        paths.ensure().unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let saved = save_project_document(
            &paths,
            "Forgotten Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        )
        .unwrap();
        let project_path = PathBuf::from(&saved.path);
        fs::write(recovery_marker_path(&project_path), b"").unwrap();
        forget_project(&paths, &saved.path).unwrap();
        assert!(!recovery_marker_path(&project_path).exists());
        fs::write(&paths.project_index, b"corrupt primary").unwrap();
        fs::write(project_index_backup_path(&paths), b"corrupt backup").unwrap();

        let projects = read_index_recovering_orphans(&paths).unwrap();

        assert!(projects.is_empty());
        assert!(project_path.exists());
        assert!(read_index(&paths).unwrap().is_empty());
    }

    #[test]
    fn stale_backup_recovery_finds_projects_added_after_the_backup_commit() {
        let paths = test_paths("recover-project-added-after-stale-backup");
        paths.ensure().unwrap();
        let stale_backup = fs::read(project_index_backup_path(&paths)).unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let saved = save_project_document(
            &paths,
            "New Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        )
        .unwrap();
        fs::write(project_index_backup_path(&paths), stale_backup).unwrap();
        fs::write(&paths.project_index, b"corrupt primary").unwrap();

        let recovered = read_index_recovering_orphans(&paths).unwrap();

        assert_eq!(recovered.len(), 1);
        assert_eq!(recovered[0].path, saved.path);
        assert_eq!(read_index(&paths).unwrap().len(), 1);
    }

    #[test]
    fn stale_backup_recovery_does_not_restore_a_forgotten_project() {
        let paths = test_paths("stale-backup-preserves-forget");
        paths.ensure().unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let saved = save_project_document(
            &paths,
            "Forgotten Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        )
        .unwrap();
        let project_path = PathBuf::from(&saved.path);
        let stale_backup = fs::read(project_index_backup_path(&paths)).unwrap();
        forget_project(&paths, &saved.path).unwrap();
        fs::write(project_index_backup_path(&paths), stale_backup).unwrap();
        fs::write(&paths.project_index, b"corrupt primary").unwrap();

        let recovered = read_index_recovering_orphans(&paths).unwrap();

        assert!(recovered.is_empty());
        assert!(project_path.exists());
        assert!(read_index(&paths).unwrap().is_empty());
    }

    #[test]
    fn forget_project_does_not_change_index_when_tombstones_are_invalid() {
        let paths = test_paths("forget-invalid-tombstones");
        paths.ensure().unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let saved = save_project_document(
            &paths,
            "Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        )
        .unwrap();
        fs::write(forgotten_project_paths_path(&paths), b"not json").unwrap();

        let result = forget_project(&paths, &saved.path);

        assert!(result.is_err());
        let indexed = read_index(&paths).unwrap();
        assert_eq!(indexed.len(), 1);
        assert_eq!(indexed[0].id, saved.id);
    }

    #[test]
    fn list_projects_repairs_a_corrupt_primary_index_from_current_backup() {
        let paths = test_paths("repair-index-from-backup");
        paths.ensure().unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let saved = save_project_document(
            &paths,
            "Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        )
        .unwrap();
        fs::remove_file(project_index_backup_path(&paths)).unwrap();
        let seeded = read_index_recovering_orphans(&paths).unwrap();
        assert_eq!(seeded.len(), 1);
        assert!(project_index_backup_path(&paths).exists());
        fs::write(&paths.project_index, b"corrupt primary").unwrap();

        let recovered = read_index_recovering_orphans(&paths).unwrap();

        assert_eq!(recovered.len(), 1);
        assert_eq!(recovered[0].id, saved.id);
        assert_eq!(read_index(&paths).unwrap().len(), 1);
    }

    #[test]
    fn list_projects_salvages_valid_documents_when_primary_and_backup_are_unavailable() {
        let paths = test_paths("salvage-index-without-backup");
        paths.ensure().unwrap();
        let recording_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&recording_path, b"recording").unwrap();
        let saved = save_project_document(
            &paths,
            "Recording",
            Some(recording_path.to_string_lossy().to_string()),
            None,
            Some("Display".to_string()),
            default_timeline_editor_state(),
            None,
        )
        .unwrap();
        fs::remove_file(project_index_backup_path(&paths)).unwrap();
        fs::write(&paths.project_index, b"corrupt primary").unwrap();

        let salvaged = read_index_recovering_orphans(&paths).unwrap();

        assert_eq!(salvaged.len(), 1);
        assert_eq!(salvaged[0].path, saved.path);
        assert_eq!(read_index(&paths).unwrap().len(), 1);
    }

    #[test]
    fn legacy_project_summary_without_availability_still_decodes() {
        let summary: ProjectSummary = serde_json::from_value(json!({
            "id": "project-legacy",
            "title": "Legacy",
            "path": "/tmp/legacy.openrecorder",
            "recordingPath": "/tmp/legacy.mp4",
            "screenshotPath": null,
            "sourceName": null,
            "createdAt": "100",
            "updatedAt": "100",
            "lastOpenedAt": "100",
            "missing": true
        }))
        .unwrap();

        assert!(summary.missing);
        assert_eq!(summary.availability, ProjectAvailability::Available);
    }

    #[test]
    fn project_availability_distinguishes_missing_project_and_media() {
        let paths = test_paths("project-availability");
        paths.ensure().unwrap();
        let missing_project = paths.projects_dir.join("missing.openrecorder");
        let missing_media = paths.recordings_dir.join("missing.mp4");

        assert_eq!(
            project_availability_for_paths(
                &missing_project,
                Some(&missing_media.to_string_lossy().to_string()),
                None
            ),
            ProjectAvailability::MissingProjectAndMedia
        );

        write_json_pretty(
            &missing_project,
            &json!({
                "schemaVersion": 2,
                "title": "Missing Media",
                "recordingPath": missing_media,
                "sourceName": null,
                "createdAt": "100",
                "updatedAt": "100",
                "editorState": { "timelineEdits": {} }
            }),
        )
        .unwrap();
        assert_eq!(
            project_availability_for_paths(
                &missing_project,
                Some(&missing_media.to_string_lossy().to_string()),
                None
            ),
            ProjectAvailability::MissingMedia
        );
    }

    #[test]
    fn project_availability_rejects_corrupt_projects_directories_and_missing_media_metadata() {
        let paths = test_paths("project-unavailable");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("project.openrecorder");
        let media_path = paths.recordings_dir.join("recording.mp4");
        fs::write(&media_path, b"recording").unwrap();
        fs::write(&project_path, b"not json").unwrap();
        assert_eq!(
            project_availability_for_paths(
                &project_path,
                Some(&media_path.to_string_lossy().to_string()),
                None
            ),
            ProjectAvailability::Unavailable
        );

        write_json_pretty(
            &project_path,
            &json!({
                "schemaVersion": 2,
                "title": "Recording",
                "recordingPath": media_path,
                "sourceName": null,
                "createdAt": "100",
                "updatedAt": "100",
                "editorState": { "timelineEdits": {} }
            }),
        )
        .unwrap();
        assert_eq!(
            project_availability_for_paths(&project_path, None, None),
            ProjectAvailability::Unavailable
        );

        fs::remove_file(&media_path).unwrap();
        fs::create_dir(&media_path).unwrap();
        assert_eq!(
            project_availability_for_paths(
                &project_path,
                Some(&media_path.to_string_lossy().to_string()),
                None
            ),
            ProjectAvailability::Unavailable
        );
    }

    #[test]
    fn project_is_missing_when_screenshot_file_is_missing() {
        let paths = test_paths("missing-screenshot-file");
        paths.ensure().unwrap();
        let project_path = paths.projects_dir.join("shot.openrecorder");
        let recording_path = paths.recordings_dir.join("shot.mov");
        fs::write(&project_path, b"{}").unwrap();
        fs::write(&recording_path, b"recording").unwrap();

        let summary = ProjectSummary {
            id: "project-existing".to_string(),
            title: "Shot".to_string(),
            path: project_path.to_string_lossy().to_string(),
            recording_path: Some(recording_path.to_string_lossy().to_string()),
            screenshot_path: Some(
                paths
                    .screenshots_dir
                    .join("missing.png")
                    .to_string_lossy()
                    .to_string(),
            ),
            source_name: Some("Display 1".to_string()),
            created_at: "100".to_string(),
            updated_at: "100".to_string(),
            last_opened_at: "150".to_string(),
            missing: false,
            availability: ProjectAvailability::Available,
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
    fn recent_screenshot_index_skips_entries_without_paths() {
        let paths = test_paths("screenshot-index-malformed-entry");
        paths.ensure().unwrap();
        write_json_pretty(
            &screenshot_index_path(&paths),
            &json!([
                { "createdAt": "200" },
                { "path": "/tmp/shot.png", "createdAt": "100" }
            ]),
        )
        .unwrap();

        let recent = read_screenshot_index(&paths).unwrap();

        assert_eq!(recent.len(), 1);
        assert_eq!(recent[0].path, "/tmp/shot.png");
        assert_eq!(recent[0].created_at, "100");
    }

    #[test]
    fn recent_screenshot_index_reads_items_newest_first_with_stable_ids() {
        let paths = test_paths("screenshot-index-sorted-ids");
        paths.ensure().unwrap();
        write_json_pretty(
            &screenshot_index_path(&paths),
            &json!([
                { "path": "/tmp/older shot.png", "createdAt": "100" },
                { "path": "/tmp/newer:shot.png", "createdAt": "200" }
            ]),
        )
        .unwrap();

        let recent = read_screenshot_index(&paths).unwrap();

        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].path, "/tmp/newer:shot.png");
        assert_eq!(recent[0].created_at, "200");
        assert_eq!(recent[0].id, "screenshot-200-tmp-newer-shot.png");
        assert_eq!(recent[1].path, "/tmp/older shot.png");
        assert_eq!(recent[1].created_at, "100");
        assert_eq!(recent[1].id, "screenshot-100-tmp-older-shot.png");
    }

    #[test]
    fn recent_screenshot_index_sorts_numeric_timestamps() {
        let paths = test_paths("screenshot-index-numeric-sort");
        paths.ensure().unwrap();
        write_json_pretty(
            &screenshot_index_path(&paths),
            &json!([
                { "path": "/tmp/older.png", "createdAt": "9" },
                { "path": "/tmp/newer.png", "createdAt": "10" }
            ]),
        )
        .unwrap();

        let recent = read_screenshot_index(&paths).unwrap();

        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].path, "/tmp/newer.png");
        assert_eq!(recent[1].path, "/tmp/older.png");
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
        let root =
            env::temp_dir().join(format!("open-recorder-service-{name}-{}", unique_suffix()));
        InternalPaths {
            recordings_dir: root.join("Recordings"),
            screenshots_dir: root.join("Screenshots"),
            projects_dir: root.join("Projects"),
            support_dir: root.join("Support"),
            project_index: root.join("Projects").join("index.json"),
        }
    }
}
