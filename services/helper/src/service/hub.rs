use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{BufRead, Error, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::{io, thread};
use warp::{Filter, Reply};

use super::logging::ServiceLogger;

const LISTEN_PORT: u16 = 47890;
const MAX_REQUEST_BYTES: u64 = 16 * 1024;
const HELPER_TOKEN_FILE_NAME: &str = "flclashx-helper-v1.token";
const CORE_FILE_NAME: &str = if cfg!(windows) {
    "FlClashCore.exe"
} else {
    "FlClashCore"
};
static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

fn request_id() -> u64 {
    NEXT_REQUEST_ID.fetch_add(1, Ordering::Relaxed)
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StartParams {
    pub path: String,
    pub arg: String,
    pub home_dir: Option<String>,
    pub auth_token: Option<String>,
    pub helper_token: String,
    #[serde(default, rename = "ownerInstanceId")]
    pub owner_instance_id: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StopParams {
    pub home_dir: Option<String>,
    pub helper_token: String,
    #[serde(default, rename = "ownerInstanceId")]
    pub owner_instance_id: Option<String>,
}

#[cfg(target_os = "windows")]
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct StrictBlockParams {
    pub path: String,
    pub home_dir: Option<String>,
    pub helper_token: String,
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

fn validate_port(value: &str) -> Result<u16, String> {
    let port = value
        .parse::<u16>()
        .map_err(|_| "core IPC port must be an integer from 1 to 65535".to_string())?;
    if port == 0 {
        return Err("core IPC port must be an integer from 1 to 65535".to_string());
    }
    Ok(port)
}

fn validate_auth_token(value: Option<String>) -> Result<Option<String>, String> {
    let Some(value) = value else {
        return Ok(None);
    };
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("core IPC authentication token must be 64 hexadecimal characters".to_string());
    }
    Ok(Some(value.to_ascii_lowercase()))
}

pub(crate) fn validate_home_directory(value: Option<String>) -> Result<PathBuf, String> {
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

fn constant_time_eq(left: &str, right: &str) -> bool {
    let left = left.as_bytes();
    let right = right.as_bytes();
    let mut difference = left.len() ^ right.len();
    let max_len = left.len().max(right.len());
    for index in 0..max_len {
        difference |= usize::from(
            left.get(index).copied().unwrap_or_default()
                ^ right.get(index).copied().unwrap_or_default(),
        );
    }
    difference == 0
}

pub(crate) fn validate_helper_token(home_dir: &Path, provided: &str) -> Result<(), String> {
    if provided.len() != 64 || !provided.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("invalid Helper credential".to_string());
    }
    let path = home_dir.join(HELPER_TOKEN_FILE_NAME);
    let metadata = fs::metadata(&path).map_err(|_| "invalid Helper credential".to_string())?;
    if !metadata.is_file() || metadata.len() != 64 {
        return Err("invalid Helper credential".to_string());
    }
    let expected = fs::read_to_string(path).map_err(|_| "invalid Helper credential".to_string())?;
    if !constant_time_eq(
        &provided.to_ascii_lowercase(),
        &expected.to_ascii_lowercase(),
    ) {
        return Err("invalid Helper credential".to_string());
    }
    Ok(())
}

fn allowed_hash() -> String {
    // The allow-list is immutable for the lifetime of this helper build.
    // Trusting a sibling file lets a portable, user-writable directory replace
    // both the hash and core before the SYSTEM service starts.
    env!("TOKEN").to_string()
}

static PROCESS: Lazy<Arc<Mutex<super::process_stop::ManagedCore<std::process::Child>>>> =
    Lazy::new(|| Arc::new(Mutex::new(Default::default())));

fn start(start_params: StartParams, logger: Arc<ServiceLogger>) -> impl Reply {
    let owner = start_params.owner_instance_id.clone();
    let result = start_core(start_params, logger);
    if let Some(owner) = owner {
        // A valid rejection means this request did not spawn a Core. Network
        // loss still leaves the caller uncertain and must not clear ownership.
        warp::reply::json(&serde_json::json!({
            "schemaVersion": 1,
            "ownerInstanceId": owner,
            "outcome": if result.is_empty() { "started" } else { "rejected" },
        }))
        .into_response()
    } else {
        result.into_response()
    }
}

fn start_core(start_params: StartParams, logger: Arc<ServiceLogger>) -> String {
    let request_id = request_id();
    logger.log(format!(
        "event=core_start.begin request_id={request_id} port={} helper_credential=present",
        start_params.arg,
    ));
    let install_dir = match service_directory() {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!("event=core_start.failure request_id={request_id} stage=service_directory error={error}"));
            return error;
        }
    };
    let core_path = match validate_start_path_in(Path::new(&start_params.path), &install_dir) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=core_start.reject request_id={request_id} stage=core_path error={error}"
            ));
            return error;
        }
    };
    let port = match validate_port(&start_params.arg) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=core_start.reject request_id={request_id} stage=core_port error={error}"
            ));
            return error;
        }
    };
    let auth_token = match validate_auth_token(start_params.auth_token) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=core_start.reject request_id={request_id} stage=core_auth error={error}"
            ));
            return error;
        }
    };
    let home_dir = match validate_home_directory(start_params.home_dir) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=core_start.reject request_id={request_id} stage=home_dir error={error}"
            ));
            return error;
        }
    };
    if let Err(error) = validate_helper_token(&home_dir, &start_params.helper_token) {
        logger.log(format!(
            "event=core_start.reject request_id={request_id} stage=helper_auth error={error}"
        ));
        return error;
    }
    let sha256 = sha256_file(&core_path).unwrap_or_default();
    let allowed = allowed_hash();
    if sha256 != allowed {
        logger.log(format!(
            "event=core_start.reject request_id={request_id} stage=core_hash"
        ));
        return format!("The SHA256 hash of the program requesting execution is: {}. The helper program only allows execution of applications with the SHA256 hash: {}.", sha256, allowed,);
    }
    let mut process = PROCESS.lock().unwrap();
    match process.prepare_start(
        start_params.owner_instance_id.as_deref(),
        std::time::Duration::from_secs(3),
    ) {
        Ok(true) => {}
        Ok(false) => return String::new(),
        Err(error) => {
            logger.log(format!(
                "event=core_start.failure request_id={request_id} stage=prepare error={error}"
            ));
            return error;
        }
    }
    let mut command = Command::new(core_path);
    command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .arg(port.to_string())
        // The core needs provider access before its SetHomeDir IPC call.
        .env("SAFE_PATHS", home_dir);
    if let Some(auth_token) = auth_token {
        command.arg(auth_token);
    }

    match command.spawn() {
        Ok(child) => {
            process.process = Some(child);
            if let Some(ref mut child) = process.process {
                let stdout = child.stdout.take().unwrap();
                let stderr = child.stderr.take().unwrap();
                spawn_core_output_logger(stdout, logger.clone(), "stdout");
                spawn_core_output_logger(stderr, logger.clone(), "stderr");
            }
            logger.log(format!("event=core_start.success request_id={request_id}"));
            "".to_string()
        }
        Err(e) => {
            logger.log(format!(
                "event=core_start.failure request_id={request_id} stage=spawn error={e}"
            ));
            e.to_string()
        }
    }
}

pub(crate) fn stop_process(logger: &Arc<ServiceLogger>) -> String {
    stop_process_owned(logger, None)
}

fn stop_process_owned(logger: &Arc<ServiceLogger>, owner: Option<&str>) -> String {
    let mut process = PROCESS.lock().unwrap();
    logger.log("stopping Core process");
    match process.stop(owner, std::time::Duration::from_secs(3)) {
        Ok(()) => String::new(),
        Err(error) => {
            logger.log(format!("Core stop failed: {error}"));
            error
        }
    }
}

fn spawn_core_output_logger<R>(reader: R, logger: Arc<ServiceLogger>, channel: &'static str)
where
    R: Read + Send + 'static,
{
    thread::spawn(move || {
        let reader = io::BufReader::new(reader);
        for line in reader.lines() {
            match line {
                Ok(output) => logger.log(format!("Core {channel}: {output}")),
                Err(error) => {
                    logger.log(format!("Core {channel} read error: {error}"));
                    break;
                }
            }
        }
    });
}

fn stop(stop_params: StopParams, logger: Arc<ServiceLogger>) -> impl Reply {
    let owner = stop_params.owner_instance_id.clone();
    let result = stop_core(stop_params, logger);
    if let Some(owner) = owner {
        warp::reply::json(&serde_json::json!({
            "schemaVersion": 1,
            "ownerInstanceId": owner,
            "outcome": if result.is_empty() { "stopped" } else { "unconfirmed" },
        }))
        .into_response()
    } else {
        result.into_response()
    }
}

fn stop_core(stop_params: StopParams, logger: Arc<ServiceLogger>) -> String {
    let request_id = request_id();
    let home_dir = match validate_home_directory(stop_params.home_dir) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=core_stop.reject request_id={request_id} stage=home_dir error={error}"
            ));
            return error;
        }
    };
    if let Err(error) = validate_helper_token(&home_dir, &stop_params.helper_token) {
        logger.log(format!(
            "event=core_stop.reject request_id={request_id} stage=helper_auth error={error}"
        ));
        return error;
    }
    let result = stop_process_owned(&logger, stop_params.owner_instance_id.as_deref());
    logger.log(format!(
        "event=core_stop.{} request_id={request_id}",
        if result.is_empty() {
            "success"
        } else {
            "failure"
        }
    ));
    result
}

#[cfg(target_os = "windows")]
fn strict_block_authorize(
    params: &StrictBlockParams,
) -> Result<(PathBuf, crate::service::wfp::BlockFilterPlan), String> {
    let home_dir = validate_home_directory(params.home_dir.clone())?;
    validate_helper_token(&home_dir, &params.helper_token)?;
    let plan = crate::service::wfp::build_block_filter_plan(&params.path)?;
    Ok((home_dir, plan))
}

#[cfg(target_os = "windows")]
fn strict_block(params: StrictBlockParams, logger: Arc<ServiceLogger>) -> impl Reply {
    let request_id = request_id();
    logger.log(format!("event=strict_block.begin request_id={request_id}"));
    let (_, plan) = match strict_block_authorize(&params) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=strict_block.reject request_id={request_id} error={error}"
            ));
            return error;
        }
    };
    match crate::service::wfp::install(&plan) {
        Ok(_) => {
            logger.log(format!(
                "event=strict_block.success request_id={request_id} target={}",
                plan.executable.display(),
            ));
            String::new()
        }
        Err(error) => {
            logger.log(format!(
                "event=strict_block.failure request_id={request_id} error={error}"
            ));
            error
        }
    }
}

#[cfg(target_os = "windows")]
fn strict_clear(params: StrictBlockParams, logger: Arc<ServiceLogger>) -> impl Reply {
    let request_id = request_id();
    logger.log(format!("event=strict_clear.begin request_id={request_id}"));
    let (_, plan) = match strict_block_authorize(&params) {
        Ok(value) => value,
        Err(error) => {
            logger.log(format!(
                "event=strict_clear.reject request_id={request_id} error={error}"
            ));
            return error;
        }
    };
    match crate::service::wfp::remove(&plan) {
        Ok(()) => {
            logger.log(format!(
                "event=strict_clear.success request_id={request_id} target={}",
                plan.executable.display(),
            ));
            String::new()
        }
        Err(error) => {
            logger.log(format!(
                "event=strict_clear.failure request_id={request_id} error={error}"
            ));
            error
        }
    }
}

#[cfg(target_os = "windows")]
fn strict_inspect(
    params: crate::service::identity::InspectStrictIdentityParams,
    logger: Arc<ServiceLogger>,
) -> warp::reply::Response {
    let request_id = request_id();
    logger.log(format!(
        "event=strict_identity.inspect.begin request_id={request_id}"
    ));
    match crate::service::identity::inspect(params) {
        Ok(identity) => {
            logger.log(format!(
                "event=strict_identity.inspect.success request_id={request_id} evidence=verified"
            ));
            warp::reply::with_status(warp::reply::json(&identity), warp::http::StatusCode::OK)
                .into_response()
        }
        Err(error) => {
            logger.log(format!(
                "event=strict_identity.inspect.reject request_id={request_id} reason=identityUnavailable detail={}",
                redact_error(&error)
            ));
            warp::reply::with_status(
                warp::reply::json(&serde_json::json!({"error": "identityUnavailable"})),
                warp::http::StatusCode::BAD_REQUEST,
            )
            .into_response()
        }
    }
}

/// Keep privileged identity errors useful for diagnostics without allowing
/// user-selected paths or certificate details to leak into the service log.
/// The underlying error is intentionally reduced to a stable, bounded reason.
fn redact_error(error: &str) -> &'static str {
    if error.contains("credential") || error.contains("home directory") {
        "authorizationRejected"
    } else if error.contains("identity inspection") || error.contains("executable") {
        "identityUnavailable"
    } else {
        "requestRejected"
    }
}

fn metadata_routes() -> impl Filter<Extract = (impl Reply,), Error = warp::Rejection> + Clone {
    let ping = warp::get()
        .and(warp::path("ping"))
        .and(warp::path::end())
        .map(allowed_hash);
    // Compatibility metadata is read-only, like /ping. It is not identity
    // attestation and must never bypass the authenticated mutation routes.
    let capabilities = warp::get()
        .and(warp::path("capabilities"))
        .and(warp::path::end())
        .map(|| {
            warp::reply::json(&serde_json::json!({
                "schemaVersion": 1,
                "stopAcknowledgesExit": true,
                "ownedStop": true,
                "allowedCoreSha256": allowed_hash(),
            }))
        });
    ping.or(capabilities)
}

fn control_routes(
    logger: Arc<ServiceLogger>,
) -> impl Filter<Extract = (impl Reply,), Error = warp::Rejection> + Clone {
    let start_logger = logger.clone();
    let api_start = warp::post()
        .and(warp::path("start"))
        .and(warp::path::end())
        .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
        .and(warp::body::json())
        .map(move |start_params: StartParams| start(start_params, start_logger.clone()));

    let stop_logger = logger.clone();
    let api_stop = warp::post()
        .and(warp::path("stop"))
        .and(warp::path::end())
        .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
        .and(warp::body::json())
        .map(move |stop_params: StopParams| stop(stop_params, stop_logger.clone()));

    api_start.or(api_stop)
}

pub async fn run_service() -> anyhow::Result<()> {
    let logger = ServiceLogger::new_default();
    logger.log("event=helper.starting");
    #[cfg(target_os = "windows")]
    match crate::service::wfp::recover_persistent_filters() {
        Ok(count) => logger.log(format!(
            "event=strict_recovery.complete recovered_targets={count}"
        )),
        Err(error) => logger.log(format!("event=strict_recovery.failure error={error}")),
    }
    let api_metadata = metadata_routes();

    let api_control = control_routes(logger.clone());

    #[cfg(target_os = "windows")]
    let routes = {
        let inspect_logger = logger.clone();
        let api_inspect = warp::post()
            .and(warp::path("strict"))
            .and(warp::path("inspect"))
            .and(warp::path::end())
            .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
            .and(warp::body::json())
            .map(
                move |params: crate::service::identity::InspectStrictIdentityParams| {
                    strict_inspect(params, inspect_logger.clone())
                },
            );
        let block_logger = logger.clone();
        let api_block = warp::post()
            .and(warp::path("strict"))
            .and(warp::path("block"))
            .and(warp::path::end())
            .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
            .and(warp::body::json())
            .map(move |params: StrictBlockParams| strict_block(params, block_logger.clone()));
        let clear_logger = logger.clone();
        let api_clear = warp::post()
            .and(warp::path("strict"))
            .and(warp::path("clear"))
            .and(warp::path::end())
            .and(warp::body::content_length_limit(MAX_REQUEST_BYTES))
            .and(warp::body::json())
            .map(move |params: StrictBlockParams| strict_clear(params, clear_logger.clone()));
        api_metadata
            .or(api_control)
            .or(api_inspect)
            .or(api_block)
            .or(api_clear)
    };

    #[cfg(not(target_os = "windows"))]
    let routes = api_metadata.or(api_control);

    warp::serve(routes).run(([127, 0, 0, 1], LISTEN_PORT)).await;

    logger.log("event=helper.stopped");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[tokio::test]
    async fn metadata_routes_report_exit_acknowledgement_and_keep_legacy_ping() {
        let routes = metadata_routes();
        let capabilities = warp::test::request()
            .method("GET")
            .path("/capabilities")
            .reply(&routes)
            .await;
        assert_eq!(capabilities.status(), warp::http::StatusCode::OK);
        let body: serde_json::Value = serde_json::from_slice(capabilities.body()).unwrap();
        assert_eq!(body["schemaVersion"], 1);
        assert_eq!(body["stopAcknowledgesExit"], true);
        assert_eq!(body["ownedStop"], true);
        assert_eq!(body["allowedCoreSha256"], allowed_hash());
        assert_eq!(body.as_object().unwrap().len(), 4);

        let ping = warp::test::request().path("/ping").reply(&routes).await;
        assert_eq!(ping.status(), warp::http::StatusCode::OK);
        assert_eq!(ping.body(), allowed_hash().as_bytes());
        for path in ["/capabilities/extra", "/start", "/stop"] {
            assert_ne!(
                warp::test::request()
                    .path(path)
                    .reply(&routes)
                    .await
                    .status(),
                warp::http::StatusCode::OK
            );
        }
        assert_eq!(
            warp::test::request()
                .method("POST")
                .path("/capabilities")
                .reply(&routes)
                .await
                .status(),
            warp::http::StatusCode::METHOD_NOT_ALLOWED
        );
    }

    #[tokio::test]
    async fn owned_http_routes_reject_lost_session_and_invalid_start_without_spawning() {
        let routes = control_routes(ServiceLogger::discard_for_test());
        let root = TempDir::new();
        let app_home = root.path().join("AppData/Roaming/com.follow/clashx");
        fs::create_dir_all(&app_home).unwrap();
        let token = "a".repeat(64);
        fs::write(app_home.join(HELPER_TOKEN_FILE_NAME), &token).unwrap();
        let owner = format!("{}-1", "b".repeat(64));
        let body =
            serde_json::json!({"home_dir":app_home,"helper_token":token,"ownerInstanceId":owner});
        let stopped = warp::test::request()
            .method("POST")
            .path("/stop")
            .json(&body)
            .reply(&routes)
            .await;
        let stopped: serde_json::Value = serde_json::from_slice(stopped.body()).unwrap();
        assert_eq!(stopped["schemaVersion"], 1);
        assert_eq!(stopped["ownerInstanceId"], owner);
        assert_eq!(stopped["outcome"], "unconfirmed");
        assert!(PROCESS.lock().unwrap().process.is_none());

        let invalid_start = serde_json::json!({"path":root.path().join("never-execute.exe"),"arg":"0","home_dir":app_home,"helper_token":token,"ownerInstanceId":owner});
        let started = warp::test::request()
            .method("POST")
            .path("/start")
            .json(&invalid_start)
            .reply(&routes)
            .await;
        let started: serde_json::Value = serde_json::from_slice(started.body()).unwrap();
        assert_eq!(started["ownerInstanceId"], owner);
        assert_eq!(started["outcome"], "rejected");
        assert!(PROCESS.lock().unwrap().process.is_none());
        let missing_auth = warp::test::request()
            .method("POST")
            .path("/stop")
            .json(&serde_json::json!({"ownerInstanceId":owner}))
            .reply(&routes)
            .await;
        assert_ne!(missing_auth.status(), warp::http::StatusCode::OK);
    }

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
    fn start_port_must_be_a_valid_tcp_port() {
        assert_eq!(validate_port("7890").expect("valid port"), 7890);
        assert!(validate_port("0").is_err());
        assert!(validate_port("65536").is_err());
        assert!(validate_port("--config=/tmp/evil").is_err());
    }

    #[test]
    fn optional_core_auth_token_is_strictly_bounded() {
        assert!(validate_auth_token(None).unwrap().is_none());
        assert_eq!(
            validate_auth_token(Some("A".repeat(64))).unwrap(),
            Some("a".repeat(64))
        );
        assert!(validate_auth_token(Some("a".repeat(63))).is_err());
        assert!(validate_auth_token(Some("g".repeat(64))).is_err());
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

    #[test]
    fn helper_control_requires_the_per_user_credential() {
        let root = TempDir::new();
        let app_home = root
            .path()
            .join("AppData")
            .join("Roaming")
            .join("com.follow")
            .join("clashx");
        fs::create_dir_all(&app_home).expect("create application home");
        let token = "a".repeat(64);
        fs::write(app_home.join(HELPER_TOKEN_FILE_NAME), &token).expect("write token");

        assert!(validate_helper_token(&app_home, &token).is_ok());
        assert!(validate_helper_token(&app_home, &"b".repeat(64)).is_err());
        assert!(validate_helper_token(&app_home, "short").is_err());
    }
}
