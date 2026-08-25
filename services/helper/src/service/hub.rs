use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, Error, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::{io, thread};
use warp::{Filter, Reply};

const LISTEN_PORT: u16 = 47890;
const MAX_REQUEST_BYTES: u64 = 16 * 1024;
const CORE_FILE_NAME: &str = if cfg!(windows) {
    "FlClashCore.exe"
} else {
    "FlClashCore"
};
const PENDING_CORE_FILE_NAME: &str = if cfg!(windows) {
    "FlClashCore.exe.pending"
} else {
    "FlClashCore.pending"
};
const BACKUP_CORE_FILE_NAME: &str = if cfg!(windows) {
    "FlClashCore.exe.backup"
} else {
    "FlClashCore.backup"
};

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
    pub home_dir: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct ReplaceParams {
    pub pending: String,
    pub target: String,
}

fn sha256_file(path: impl AsRef<Path>) -> Result<String, Error> {
    let mut file = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 4096];

    loop {
        let bytes_read = file.read(&mut buffer)?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

fn service_directory() -> Result<PathBuf, String> {
    let executable = std::env::current_exe()
        .map_err(|error| format!("unable to resolve helper executable: {error}"))?;
    let parent = executable
        .parent()
        .ok_or_else(|| "helper executable has no parent directory".to_string())?;
    parent
        .canonicalize()
        .map_err(|error| format!("unable to resolve helper directory: {error}"))
}

fn allowed_hash_path() -> Option<PathBuf> {
    Some(service_directory().ok()?.join("allowed_core.sha256"))
}

fn validate_exact_existing_path(
    requested: &Path,
    expected: &Path,
    description: &str,
) -> Result<PathBuf, String> {
    let requested = requested
        .canonicalize()
        .map_err(|error| format!("invalid {description} path: {error}"))?;
    let expected = expected
        .canonicalize()
        .map_err(|error| format!("expected {description} is unavailable: {error}"))?;
    if requested != expected {
        return Err(format!("{description} path is not allowed"));
    }
    Ok(expected)
}

fn validate_start_path_in(requested: &Path, install_dir: &Path) -> Result<PathBuf, String> {
    validate_exact_existing_path(
        requested,
        &install_dir.join(CORE_FILE_NAME),
        "core executable",
    )
}

fn validate_replace_paths_in(
    pending: &Path,
    target: &Path,
    install_dir: &Path,
) -> Result<(PathBuf, PathBuf), String> {
    let pending = validate_exact_existing_path(
        pending,
        &install_dir.join(PENDING_CORE_FILE_NAME),
        "pending core",
    )?;
    let target =
        validate_exact_existing_path(target, &install_dir.join(CORE_FILE_NAME), "core target")?;
    Ok((pending, target))
}

fn validate_port(value: &str) -> Result<u16, String> {
    let port = value
        .parse::<u16>()
        .map_err(|_| "core IPC port must be an integer from 1 to 65535".to_string())?;
    if port == 0 {
        return Err("core IPC port must be an integer from 1 to 65535".to_string());
    }
    Ok(port)
}

fn validate_home_directory(value: Option<String>) -> Result<PathBuf, String> {
    let value = value.ok_or_else(|| "core home directory is required".to_string())?;
    let canonical = Path::new(&value)
        .canonicalize()
        .map_err(|error| format!("invalid core home directory: {error}"))?;
    if !canonical.is_dir() {
        return Err("core home directory is not a directory".to_string());
    }

    // path_provider on Windows resolves application support to this fixed
    // suffix. Requiring it prevents an unauthenticated local caller from using
    // the SYSTEM core as a write primitive against arbitrary directories.
    let suffix = ["appdata", "roaming", "com.follow", "clashx"];
    let components = canonical
        .components()
        .map(|component| component.as_os_str().to_string_lossy().to_lowercase())
        .collect::<Vec<_>>();
    if components.len() < suffix.len() || components[components.len() - suffix.len()..] != suffix {
        return Err("core home directory is outside the application data directory".to_string());
    }
    Ok(canonical)
}

/// Core updates delivered by the app rewrite this file (admin-writable only in
/// per-machine installs); the compiled-in TOKEN covers fresh installs.
fn allowed_hash() -> String {
    if let Some(path) = allowed_hash_path() {
        if let Ok(content) = std::fs::read_to_string(&path) {
            let hash = content.trim().to_lowercase();
            if hash.len() == 64 && hash.chars().all(|c| c.is_ascii_hexdigit()) {
                return hash;
            }
        }
    }
    env!("TOKEN").to_string()
}

static LOGS: Lazy<Arc<Mutex<VecDeque<String>>>> =
    Lazy::new(|| Arc::new(Mutex::new(VecDeque::with_capacity(100))));
static PROCESS: Lazy<Arc<Mutex<Option<std::process::Child>>>> =
    Lazy::new(|| Arc::new(Mutex::new(None)));

fn start(start_params: StartParams) -> impl Reply {
    let install_dir = match service_directory() {
        Ok(value) => value,
        Err(error) => return error,
    };
    let core_path = match validate_start_path_in(Path::new(&start_params.path), &install_dir) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let port = match validate_port(&start_params.arg) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let home_dir = match validate_home_directory(start_params.home_dir) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let sha256 = sha256_file(&core_path).unwrap_or_default();
    let allowed = allowed_hash();
    if sha256 != allowed {
        return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256, allowed,);
    }
    stop();
    let mut process = PROCESS.lock().unwrap();
    let mut command = Command::new(core_path);
    command
        .stderr(Stdio::piped())
        .arg(port.to_string())
        // The core needs provider access before its SetHomeDir IPC call.
        .env("SAFE_PATHS", home_dir);

    match command.spawn() {
        Ok(child) => {
            *process = Some(child);
            if let Some(ref mut child) = *process {
                let stderr = child.stderr.take().unwrap();
                let reader = io::BufReader::new(stderr);
                thread::spawn(move || {
                    for line in reader.lines() {
                        match line {
                            Ok(output) => {
                                log_message(output);
                            }
                            Err(_) => {
                                break;
                            }
                        }
                    }
                });
            }
            "".to_string()
        }
        Err(e) => {
            log_message(e.to_string());
            e.to_string()
        }
    }
}

/// Swap in a downloaded core update. The service runs as SYSTEM, so it can
/// write into Program Files where the unelevated app cannot (the app's own
/// rename fails with access-denied for a per-machine install). Stops the core
/// first to release the exe lock, moves pending->target, then refreshes the
/// allow-list hash so the new binary passes the /start check — all as SYSTEM,
/// no UAC prompt. Returns "" on success or an error string.
fn replace_core(params: ReplaceParams) -> impl Reply {
    let install_dir = match service_directory() {
        Ok(value) => value,
        Err(error) => return error,
    };
    let (pending, target) = match validate_replace_paths_in(
        Path::new(&params.pending),
        Path::new(&params.target),
        &install_dir,
    ) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let pending_hash = match sha256_file(&pending) {
        Ok(value) => value,
        Err(error) => return format!("unable to hash pending core: {error}"),
    };
    let hash_path = match allowed_hash_path() {
        Some(value) => value,
        None => return "unable to resolve allowed-core hash path".to_string(),
    };
    let backup = install_dir.join(BACKUP_CORE_FILE_NAME);

    stop();
    if backup.exists() {
        if let Err(error) = std::fs::remove_file(&backup) {
            return format!("unable to remove stale core backup: {error}");
        }
    }
    if let Err(error) = std::fs::rename(&target, &backup) {
        return format!("unable to create core backup: {error}");
    }
    if let Err(error) = std::fs::rename(&pending, &target) {
        let _ = std::fs::rename(&backup, &target);
        return format!("unable to activate pending core: {error}");
    }
    if let Err(error) = std::fs::write(&hash_path, pending_hash) {
        let _ = std::fs::remove_file(&target);
        let _ = std::fs::rename(&backup, &target);
        return format!("unable to update allowed-core hash: {error}");
    }
    if let Err(error) = std::fs::remove_file(&backup) {
        log_message(format!("unable to remove core backup: {error}"));
    }
    String::new()
}

fn stop() -> impl Reply {
    let mut process = PROCESS.lock().unwrap();
    if let Some(mut child) = process.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    *process = None;
    "".to_string()
}

fn log_message(message: String) {
    let mut log_buffer = LOGS.lock().unwrap();
    if log_buffer.len() == 100 {
        log_buffer.pop_front();
    }
    log_buffer.push_back(format!("{}\n", message));
}

fn get_logs() -> impl Reply {
    let log_buffer = LOGS.lock().unwrap();
    let value = log_buffer
        .iter()
        .cloned()
        .collect::<Vec<String>>()
        .join("\n");
    warp::reply::with_header(value, "Content-Type", "text/plain")
}

pub async fn run_service() -> anyhow::Result<()> {
    let api_ping = warp::get()
        .and(warp::path("ping"))
        .and(warp::path::end())
        .map(allowed_hash);

    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::path::end())
        .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
        .and(warp::body::json())
        .map(|start_params: StartParams| start(start_params));

    let api_stop = warp::post()
        .and(warp::path("stop"))
        .and(warp::path::end())
        .map(|| stop());

    let api_replace = warp::post()
        .and(warp::path("replace_core"))
        .and(warp::path::end())
        .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
        .and(warp::body::json())
        .map(|params: ReplaceParams| replace_core(params));

    let api_logs = warp::get()
        .and(warp::path("logs"))
        .and(warp::path::end())
        .map(|| get_logs());

    warp::serve(
        api_ping
            .or(api_start)
            .or(api_stop)
            .or(api_replace)
            .or(api_logs),
    )
    .run(([127, 0, 0, 1], LISTEN_PORT))
    .await;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDir(std::path::PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "flclashx-helper-test-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(&path).expect("create temp directory");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn start_rejects_any_executable_outside_the_service_directory() {
        let install = TempDir::new();
        let outside = TempDir::new();
        let expected = install.path().join(CORE_FILE_NAME);
        let untrusted = outside.path().join(CORE_FILE_NAME);
        fs::write(&expected, b"trusted").expect("write expected core");
        fs::write(&untrusted, b"untrusted").expect("write outside core");

        assert!(validate_start_path_in(&expected, install.path()).is_ok());
        assert!(validate_start_path_in(&untrusted, install.path()).is_err());
    }

    #[test]
    fn replacement_accepts_only_the_fixed_pending_and_target_paths() {
        let install = TempDir::new();
        let outside = TempDir::new();
        let pending = install.path().join(PENDING_CORE_FILE_NAME);
        let target = install.path().join(CORE_FILE_NAME);
        fs::write(&pending, b"update").expect("write pending core");
        fs::write(&target, b"current").expect("write current core");

        assert!(validate_replace_paths_in(&pending, &target, install.path()).is_ok());
        assert!(validate_replace_paths_in(
            &outside.path().join(PENDING_CORE_FILE_NAME),
            &target,
            install.path(),
        )
        .is_err());
        assert!(validate_replace_paths_in(
            &pending,
            &outside.path().join(CORE_FILE_NAME),
            install.path(),
        )
        .is_err());
    }

    #[test]
    fn start_port_must_be_a_valid_tcp_port() {
        assert_eq!(validate_port("7890").expect("valid port"), 7890);
        assert!(validate_port("0").is_err());
        assert!(validate_port("65536").is_err());
        assert!(validate_port("--config=/tmp/evil").is_err());
    }

    #[test]
    fn home_directory_requires_the_application_support_suffix() {
        let root = TempDir::new();
        let app_home = root
            .path()
            .join("AppData")
            .join("Roaming")
            .join("com.follow")
            .join("clashx");
        let arbitrary = root.path().join("arbitrary");
        fs::create_dir_all(&app_home).expect("create application home");
        fs::create_dir_all(&arbitrary).expect("create arbitrary directory");

        assert!(validate_home_directory(Some(app_home.to_string_lossy().into())).is_ok());
        assert!(validate_home_directory(Some(arbitrary.to_string_lossy().into())).is_err());
        assert!(validate_home_directory(None).is_err());
    }
}
