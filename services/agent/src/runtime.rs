use std::collections::HashSet;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Value};
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use tokio::process::{Child, Command};
use tokio::sync::{mpsc, oneshot, Mutex, Notify, RwLock};
use tokio::time::{timeout, Instant};

#[cfg(windows)]
use crate::broker::WindowsStrictBrokerSession;
use crate::config::AgentConfig;
use crate::endpoint::{load_or_create_helper_token, random_token, EndpointGuard};
use crate::journal::ReplayJournal;
use crate::logging::AgentLogger;
use crate::protocol::{
    authenticate, parse_control, AgentCommand, StrictPolicyStatus, MAX_AUTH_LINE_BYTES,
    MAX_MESSAGE_LINE_BYTES, PROTOCOL_VERSION,
};
#[cfg(windows)]
use crate::strict_flow::{StrictOrchestrationAction, StrictPolicyOrchestrator};
#[cfg(windows)]
use flclash_strict_contract::{StrictPolicyBundle, StrictState, MAX_STRICT_CHILDREN};

const CHANNEL_CAPACITY: usize = 256;
const CORE_CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const CORE_REPLAY_TIMEOUT: Duration = Duration::from_secs(30);
const HELPER_RESPONSE_LIMIT: usize = 64 * 1024;
const MAX_CRASH_RETRIES: u32 = 5;
const MAX_STRICT_BLOCKS: usize = 128;

#[cfg(windows)]
struct StrictRuntime {
    orchestrator: Mutex<StrictPolicyOrchestrator>,
    broker: std::sync::Mutex<Option<WindowsStrictBrokerSession>>,
    pending_core_id: Mutex<Option<String>>,
    policy: RwLock<StrictPolicyBundle>,
    retry: Mutex<crate::strict_retry::StrictRecoveryRetry>,
    retry_at: Mutex<Option<Instant>>,
}

#[cfg(windows)]
impl StrictRuntime {
    fn new(policy: StrictPolicyBundle) -> Self {
        Self {
            orchestrator: Mutex::new(StrictPolicyOrchestrator::default()),
            broker: std::sync::Mutex::new(None),
            pending_core_id: Mutex::new(None),
            policy: RwLock::new(policy),
            retry: Mutex::new(crate::strict_retry::StrictRecoveryRetry::default()),
            retry_at: Mutex::new(None),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CoreStatus {
    Starting,
    Ready,
    Stopped,
    Failed,
}

impl CoreStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Starting => "starting",
            Self::Ready => "ready",
            Self::Stopped => "stopped",
            Self::Failed => "failed",
        }
    }
}

struct UiSession {
    id: u64,
    output: mpsc::Sender<UiOutput>,
    cancel: Arc<SessionCancel>,
}

struct SessionCancel {
    cancelled: AtomicBool,
    notify: Notify,
}

impl SessionCancel {
    fn cancel(&self) {
        self.cancelled.store(true, Ordering::Release);
        self.notify.notify_one();
    }
}

struct UiOutput {
    line: String,
    delivered: Option<oneshot::Sender<()>>,
}

impl UiOutput {
    fn new(line: String) -> Self {
        Self {
            line,
            delivered: None,
        }
    }
}

struct Shared {
    ui: Mutex<Option<UiSession>>,
    core: Mutex<Option<mpsc::Sender<String>>>,
    journal: Mutex<ReplayJournal>,
    #[cfg(target_os = "macos")]
    mac_strict_replay: Mutex<crate::mac_strict_replay::MacStrictReplay>,
    #[cfg(target_os = "macos")]
    mac_strict_account: String,
    logger: Arc<AgentLogger>,
    status: RwLock<CoreStatus>,
    // The Agent does not implement a platform capture backend. Keeping an
    // explicit disabled status in every lifecycle envelope prevents consumers
    // from interpreting a healthy Core as proof that strict capture is armed.
    strict_policy: RwLock<StrictPolicyStatus>,
    generation: AtomicU64,
    next_session: AtomicU64,
    shutting_down: AtomicBool,
    shutdown: Notify,
    supervisor: mpsc::Sender<SupervisorCommand>,
    privileged_backend: bool,
    helper_port: Option<u16>,
    helper_token: Option<String>,
    home_dir: PathBuf,
    strict_blocks: Mutex<HashSet<String>>,
    #[cfg(windows)]
    strict_runtime: Mutex<Option<Arc<StrictRuntime>>>,
    #[cfg(windows)]
    strict_store: Mutex<Option<crate::strict_store::StrictIntentStore>>,
}

enum SupervisorCommand {
    Restart(oneshot::Sender<bool>),
    Stop(oneshot::Sender<bool>),
    Shutdown(oneshot::Sender<bool>),
}

enum SessionEnd {
    Restart,
    Stopped,
    Crashed,
    ShutdownRequested,
    Shutdown,
}

fn resolve_supervisor_command(command: Option<SupervisorCommand>) -> SessionEnd {
    match command {
        Some(SupervisorCommand::Restart(reply)) => {
            let _ = reply.send(true);
            SessionEnd::Restart
        }
        Some(SupervisorCommand::Stop(reply)) => {
            let _ = reply.send(true);
            SessionEnd::Stopped
        }
        Some(SupervisorCommand::Shutdown(reply)) => {
            let _ = reply.send(true);
            SessionEnd::ShutdownRequested
        }
        None => SessionEnd::Shutdown,
    }
}

async fn apply_supervisor_end(
    end: SessionEnd,
    should_start: &mut bool,
    shared: &Arc<Shared>,
) -> bool {
    match end {
        SessionEnd::Restart => *should_start = true,
        SessionEnd::Stopped => *should_start = false,
        SessionEnd::ShutdownRequested => {
            // The UI handler signals shutdown after the command result is
            // written to the socket. Fall back to a bounded forced shutdown
            // if that client disappears before acknowledging delivery.
            let fallback_shared = shared.clone();
            tokio::spawn(async move {
                tokio::time::sleep(Duration::from_secs(2)).await;
                signal_shutdown(&fallback_shared);
            });
            return true;
        }
        SessionEnd::Shutdown => {
            signal_shutdown(shared);
            return true;
        }
        SessionEnd::Crashed => unreachable!("crash is not a supervisor command"),
    }
    false
}

fn signal_shutdown(shared: &Shared) {
    shared.shutting_down.store(true, Ordering::Release);
    shared.shutdown.notify_waiters();
}

async fn set_strict_policy(
    shared: &Arc<Shared>,
    state: crate::protocol::StrictPolicyState,
    failure_reason: Option<crate::protocol::StrictPolicyFailureReason>,
) {
    let mut status = shared.strict_policy.write().await;
    status.generation = status.generation.saturating_add(1);
    status.state = state;
    status.failure_reason = failure_reason;
    drop(status);
    publish_strict_status(shared).await;
}

async fn publish_strict_status(shared: &Arc<Shared>) {
    let state = *shared.status.read().await;
    let envelope = json!({"_agent": {
        "type": "coreState", "protocol": PROTOCOL_VERSION,
        "coreState": state.as_str(),
        "generation": shared.generation.load(Ordering::Acquire),
        "privilegedBackend": shared.privileged_backend,
        "strictPolicy": strict_policy_json(shared).await,
    }});
    forward_to_ui(shared, envelope.to_string()).await;
}

async fn apply_strict_block(shared: &Arc<Shared>, path: Option<String>) -> bool {
    let Some(path) = path else {
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::InvalidPolicy),
        )
        .await;
        shared
            .logger
            .log("strict block rejected: target path is missing");
        return false;
    };
    let (Some(helper_port), Some(helper_token)) =
        (shared.helper_port, shared.helper_token.as_deref())
    else {
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
        )
        .await;
        shared
            .logger
            .log("strict block rejected: privileged Helper is unavailable");
        return false;
    };
    set_strict_policy(shared, crate::protocol::StrictPolicyState::Preparing, None).await;
    let target_key = strict_target_key(&path);
    let target_limit_reached = {
        let blocks = shared.strict_blocks.lock().await;
        !blocks.contains(&target_key) && blocks.len() >= MAX_STRICT_BLOCKS
    };
    if target_limit_reached {
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::InvalidPolicy),
        )
        .await;
        shared
            .logger
            .log("strict block rejected: target limit reached");
        return false;
    }
    let result = helper_request(
        helper_port,
        "/strict/block",
        Some(json!({
            "path": path,
            "home_dir": shared.home_dir.to_string_lossy().to_string(),
            "helper_token": helper_token,
        })),
    )
    .await;
    match result {
        Ok(()) => {
            // This command deliberately requests the fail-closed route. It is
            // not an armed proxy redirect and must remain visible as blocking.
            set_strict_policy(shared, crate::protocol::StrictPolicyState::Blocking, None).await;
            shared.strict_blocks.lock().await.insert(target_key);
            shared.logger.log("strict block installed through Helper");
            true
        }
        Err(error) => {
            set_strict_policy(
                shared,
                crate::protocol::StrictPolicyState::Blocking,
                Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
            )
            .await;
            shared
                .logger
                .log(format!("strict block install failed: {error:#}"));
            false
        }
    }
}

async fn clear_strict_block(shared: &Arc<Shared>, path: Option<String>) -> bool {
    let Some(path) = path else {
        shared
            .logger
            .log("strict clear rejected: target path is missing");
        return false;
    };
    let (Some(helper_port), Some(helper_token)) =
        (shared.helper_port, shared.helper_token.as_deref())
    else {
        shared
            .logger
            .log("strict clear rejected: privileged Helper is unavailable");
        return false;
    };
    let target_key = strict_target_key(&path);
    let result = helper_request(
        helper_port,
        "/strict/clear",
        Some(json!({
            "path": path,
            "home_dir": shared.home_dir.to_string_lossy().to_string(),
            "helper_token": helper_token,
        })),
    )
    .await;
    match result {
        Ok(()) => {
            let no_remaining_blocks = {
                let mut blocks = shared.strict_blocks.lock().await;
                blocks.remove(&target_key);
                blocks.is_empty()
            };
            let state = if no_remaining_blocks {
                crate::protocol::StrictPolicyState::Disabled
            } else {
                crate::protocol::StrictPolicyState::Blocking
            };
            set_strict_policy(shared, state, None).await;
            shared.logger.log("strict block removed through Helper");
            true
        }
        Err(error) => {
            set_strict_policy(
                shared,
                crate::protocol::StrictPolicyState::Blocking,
                Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
            )
            .await;
            shared
                .logger
                .log(format!("strict block removal failed: {error:#}"));
            false
        }
    }
}

#[cfg(windows)]
async fn inspect_strict_identity(shared: &Arc<Shared>, path: Option<String>) -> Result<Value> {
    let path = path.context("strict identity target path is missing")?;
    let (Some(helper_port), Some(helper_token)) =
        (shared.helper_port, shared.helper_token.as_deref())
    else {
        bail!("privileged Helper is unavailable")
    };
    if path.len() > 1024 || path.is_empty() {
        bail!("strict identity target path is invalid")
    }
    let response = helper_request_json(
        helper_port,
        "/strict/inspect",
        json!({
            "path": path,
            "home_dir": shared.home_dir.to_string_lossy(),
            "helper_token": helper_token,
        }),
    )
    .await?;
    let object = response
        .as_object()
        .context("Helper returned a non-object identity")?;
    for field in [
        "canonicalPath",
        "wfpAppIdSha256",
        "publisherCertificateSha256",
    ] {
        let value = object
            .get(field)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .with_context(|| format!("Helper identity field {field} is missing"))?;
        if value.len() > 1024 {
            bail!("Helper identity field {field} is oversized")
        }
    }
    let publisher = object
        .get("publisherCertificateSha256")
        .and_then(Value::as_str)
        .context("Helper identity publisher is missing")?;
    let children = object
        .get("verifiedChildren")
        .and_then(Value::as_array)
        .context("Helper identity children are missing")?;
    if children.len() > MAX_STRICT_CHILDREN {
        bail!("Helper identity children exceed the strict family limit")
    }
    for child in children {
        let child = child
            .as_object()
            .context("Helper returned an invalid strict identity child")?;
        let child_path = child
            .get("canonicalPath")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty() && value.len() <= 1024)
            .context("Helper strict child path is invalid")?;
        let child_app_id = child
            .get("wfpAppIdSha256")
            .and_then(Value::as_str)
            .context("Helper strict child app identity is missing")?;
        let child_publisher = child
            .get("publisherCertificateSha256")
            .and_then(Value::as_str)
            .context("Helper strict child publisher is missing")?;
        if child_path.contains(['\0', '\r', '\n'])
            || child_app_id.len() != 64
            || !child_app_id.bytes().all(|byte| byte.is_ascii_hexdigit())
            || child_publisher.len() != 64
            || !child_publisher.bytes().all(|byte| byte.is_ascii_hexdigit())
            || !child_publisher.eq_ignore_ascii_case(publisher)
        {
            bail!("Helper returned an unverified strict identity child")
        }
    }
    Ok(response)
}

#[cfg(not(windows))]
async fn inspect_strict_identity(_shared: &Arc<Shared>, _path: Option<String>) -> Result<Value> {
    bail!("strict identity inspection is unavailable on this platform")
}

/// Starts the complete strict policy transaction.  The operation is
/// deliberately asynchronous at the Agent boundary: Broker pipe I/O runs on
/// a blocking worker while Core ingress responses are consumed by the Core
/// supervisor loop below.  This keeps connection/log streaming responsive.
#[cfg(windows)]
async fn apply_strict_policy(shared: &Arc<Shared>, raw: Option<Value>) -> bool {
    let Some(raw) = raw else {
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::InvalidPolicy),
        )
        .await;
        shared.logger.log("strict policy rejected: payload missing");
        return false;
    };
    let policy: StrictPolicyBundle = match serde_json::from_value(raw) {
        Ok(policy) => policy,
        Err(error) => {
            set_strict_policy(
                shared,
                crate::protocol::StrictPolicyState::Blocking,
                Some(crate::protocol::StrictPolicyFailureReason::InvalidPolicy),
            )
            .await;
            shared
                .logger
                .log(format!("strict policy rejected: invalid payload ({error})"));
            return false;
        }
    };
    if let Err(error) = policy.validate() {
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::InvalidPolicy),
        )
        .await;
        shared.logger.log(format!(
            "strict policy rejected: validation failed ({error})"
        ));
        return false;
    }
    if !shared.privileged_backend {
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
        )
        .await;
        shared
            .logger
            .log("strict policy rejected: privileged backend is disabled");
        return false;
    }

    if shared.strict_runtime.lock().await.is_some() {
        shared.logger.log("strict apply rejected: a policy is already active");
        return false;
    }
    if let Err(error) = persist_strict_intent(shared, true, &policy).await {
        shared.logger.log(format!("strict intent persistence failed: {error:#}"));
        set_strict_policy(shared, crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable)).await;
        return false;
    }
    let runtime = Arc::new(StrictRuntime::new(policy.clone()));
    let action = {
        let mut orchestrator = runtime.orchestrator.lock().await;
        match orchestrator.begin(policy) {
            Ok(action) => action,
            Err(error) => {
                shared
                    .logger
                    .log(format!("strict policy begin failed: {error:#}"));
                return false;
            }
        }
    };
    {
        let mut current = shared.strict_runtime.lock().await;
        if current.is_some() {
            shared
                .logger
                .log("strict policy rejected: transition already active");
            return false;
        }
        *current = Some(runtime.clone());
    }
    set_strict_policy(shared, crate::protocol::StrictPolicyState::Preparing, None).await;
    drive_strict_action(shared, runtime, action).await
}

#[cfg(windows)]
async fn persist_strict_intent(shared: &Arc<Shared>, enabled: bool, policy: &StrictPolicyBundle) -> Result<()> {
    let store = shared.strict_store.lock().await;
    store.as_ref().context("protected strict intent storage is unavailable")?.save(enabled, policy)
}

#[cfg(windows)]
async fn restore_strict_intent(shared: &Arc<Shared>, intent: crate::strict_store::StoredStrictIntent) {
    if intent.enabled {
        let raw = serde_json::to_value(&intent.policy).ok();
        let _ = apply_strict_policy(shared, raw).await;
        return;
    }
    let runtime = Arc::new(StrictRuntime::new(intent.policy.clone()));
    let action = runtime.orchestrator.lock().await.restore_disable(intent.policy);
    if let Ok(action) = action {
        *shared.strict_runtime.lock().await = Some(runtime.clone());
        let _ = drive_strict_action(shared, runtime, action).await;
    } else {
        shared.logger.log("persisted strict disable intent could not be restored");
        set_strict_policy(shared, crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::InvalidPolicy)).await;
    }
}

#[cfg(windows)]
async fn migrate_strict_policy(shared: &Arc<Shared>, path: Option<String>, raw: Option<Value>) -> bool {
    let Some(runtime) = shared.strict_runtime.lock().await.clone() else { return false; };
    let Some(raw) = raw else { return false; };
    let Some(path) = path else { return false; };
    let Some(revision) = raw.get("revision").and_then(Value::as_u64) else { return false; };
    let Some(replacement) = raw.get("replacement") else { return false; };
    let mut replacement: flclash_strict_contract::StrictIdentity = match serde_json::from_value(replacement.clone()) {
        Ok(identity) => identity,
        Err(_) => return false,
    };
    let mut policy = runtime.policy.read().await.clone();
    let previous_policy = policy.clone();
    let Some(entry) = policy.entries.iter_mut().find(|entry|
        entry.identity.canonical_path.eq_ignore_ascii_case(&path)) else { return false; };
    replacement.identity_id = entry.identity.identity_id.clone();
    let previous_root = flclash_strict_contract::StrictChildIdentity {
        canonical_path: entry.identity.canonical_path.clone(),
        wfp_app_id_sha256: entry.identity.wfp_app_id_sha256.clone(),
        publisher_certificate_sha256: entry.identity.publisher_certificate_sha256.clone(),
    };
    for previous in std::iter::once(previous_root).chain(entry.identity.verified_children.clone()) {
        if !previous.canonical_path.eq_ignore_ascii_case(&replacement.canonical_path)
            && !replacement.verified_children.iter().any(|child|
                child.canonical_path.eq_ignore_ascii_case(&previous.canonical_path)) {
            replacement.verified_children.push(previous);
        }
    }
    entry.identity = replacement;
    policy.revision = revision;
    let action = {
        let mut orchestrator = runtime.orchestrator.lock().await;
        let mut previous = runtime.policy.write().await;
        if flclash_strict_contract::validate_identity_migration(&previous, &policy).is_err() {
            shared.logger.log("strict identity migration rejected: invalid continuity");
            return false;
        }
        if !orchestrator.can_replace_or_disable() { return false; }
        if let Err(error) = persist_strict_intent(shared, true, &policy).await {
            shared.logger.log(format!("strict migration intent persistence failed: {error:#}"));
            return false;
        }
        match orchestrator.begin_migration(policy.clone()) {
            Ok(action) => { *previous = policy; action }
            Err(error) => {
                shared.logger.log(format!("strict identity migration cannot begin: {error:#}"));
                return false;
            }
        }
    };
    set_strict_policy(shared, crate::protocol::StrictPolicyState::Preparing, None).await;
    let accepted = drive_strict_action(shared, runtime.clone(), action).await;
    if !accepted {
        // A rejected signer must not strand the Agent on an unaccepted new
        // revision. Restore only after authenticated status proves the Broker
        // still owns the original policy; an uncertain/new revision stays blocked.
        let mut orchestrator = runtime.orchestrator.lock().await;
        let worker_runtime = runtime.clone();
        let status = tokio::task::spawn_blocking(move || {
            let mut broker = worker_runtime.broker.lock()
                .map_err(|_| anyhow!("strict Broker session lock poisoned"))?;
            if broker.is_none() { *broker = Some(WindowsStrictBrokerSession::activate()?); }
            broker.as_mut().context("strict Broker session missing")?
                .request(flclash_strict_contract::BrokerCommand::Status {})
        }).await;
        if let Ok(Ok(proof)) = status {
            if proof.revision == previous_policy.revision
                && previous_policy.canonical_digest().is_ok_and(|digest|
                    digest.eq_ignore_ascii_case(&proof.policy_digest)) {
                let mut restored = StrictPolicyOrchestrator::default();
                if let Ok(prepare) = restored.begin(previous_policy.clone()) {
                    if persist_strict_intent(shared, true, &previous_policy).await.is_err() {
                        shared.logger.log("strict original intent could not be persisted; policy stays blocked");
                        return false;
                    }
                    *orchestrator = restored;
                    *runtime.policy.write().await = previous_policy;
                    drop(orchestrator);
                    let _ = drive_strict_action(shared, runtime, prepare).await;
                    return false;
                }
            }
        }
    }
    accepted
}

#[cfg(not(windows))]
async fn migrate_strict_policy(_shared: &Arc<Shared>, _path: Option<String>, _raw: Option<Value>) -> bool { false }

#[cfg(not(windows))]
async fn apply_strict_policy(shared: &Arc<Shared>, _raw: Option<Value>) -> bool {
    set_strict_policy(
        shared,
        crate::protocol::StrictPolicyState::Blocking,
        Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
    )
    .await;
    shared
        .logger
        .log("strict policy unavailable: Windows Broker is not supported on this platform");
    false
}

#[cfg(windows)]
async fn clear_strict_policy(shared: &Arc<Shared>) -> bool {
    let Some(runtime) = shared.strict_runtime.lock().await.clone() else {
        return false;
    };
    let action = {
        let mut orchestrator = runtime.orchestrator.lock().await;
        if !orchestrator.can_replace_or_disable() { return false; }
        let policy = runtime.policy.read().await.clone();
        if let Err(error) = persist_strict_intent(shared, false, &policy).await {
            shared.logger.log(format!("strict disable intent persistence failed: {error:#}"));
            return false;
        }
        match orchestrator.disable() {
            Ok(action) => action,
            Err(error) => {
                shared
                    .logger
                    .log(format!("strict policy disable rejected: {error:#}"));
                return false;
            }
        }
    };
    set_strict_policy(shared, crate::protocol::StrictPolicyState::Preparing, None).await;
    drive_strict_action(shared, runtime, action).await
}

#[cfg(not(windows))]
async fn clear_strict_policy(shared: &Arc<Shared>) -> bool {
    shared
        .logger
        .log("strict policy disable unavailable on this platform");
    false
}

#[cfg(windows)]
async fn drive_strict_action(
    shared: &Arc<Shared>,
    runtime: Arc<StrictRuntime>,
    action: StrictOrchestrationAction,
) -> bool {
    match action {
        StrictOrchestrationAction::Settled(status) => {
            let state = match status.state {
                StrictState::Disabled => crate::protocol::StrictPolicyState::Disabled,
                StrictState::Preparing => crate::protocol::StrictPolicyState::Preparing,
                StrictState::Blocking => crate::protocol::StrictPolicyState::Blocking,
                StrictState::Armed => crate::protocol::StrictPolicyState::Armed,
                StrictState::Recovering => crate::protocol::StrictPolicyState::Recovering,
            };
            set_strict_policy(shared, state, None).await;
            if status.state == StrictState::Armed {
                runtime.retry.lock().await.reset();
                *runtime.retry_at.lock().await = None;
            }
            if status.state == StrictState::Disabled {
                *shared.strict_runtime.lock().await = None;
            }
            true
        }
        StrictOrchestrationAction::Core(core_action) => {
            let Some(core) = shared.core.lock().await.clone() else {
                shared.logger.log("strict policy Core ingress unavailable");
                // Startup restore can precede Core readiness. Update the
                // controller as well as the UI state so the supervisor sees
                // a recoverable failure and reconciles guards before replay.
                runtime.orchestrator.lock().await.broker_lost(runtime.policy.read().await.revision);
                set_strict_policy(
                    shared,
                    crate::protocol::StrictPolicyState::Blocking,
                    Some(crate::protocol::StrictPolicyFailureReason::CoreUnavailable),
                )
                .await;
                return false;
            };
            *runtime.pending_core_id.lock().await = Some(core_action.id().to_owned());
            if core.send(core_action.line().to_owned()).await.is_err() {
                *runtime.pending_core_id.lock().await = None;
                shared.logger.log("strict policy Core ingress send failed");
                runtime.orchestrator.lock().await.broker_lost(runtime.policy.read().await.revision);
                set_strict_policy(
                    shared,
                    crate::protocol::StrictPolicyState::Blocking,
                    Some(crate::protocol::StrictPolicyFailureReason::CoreUnavailable),
                )
                .await;
                return false;
            }
            true
        }
        StrictOrchestrationAction::Broker(command) => {
            let runtime_for_worker = runtime.clone();
            let result = tokio::task::spawn_blocking(move || {
                let mut broker = runtime_for_worker
                    .broker
                    .lock()
                    .map_err(|_| anyhow!("strict Broker session lock poisoned"))?;
                if broker.is_none() {
                    *broker = Some(WindowsStrictBrokerSession::activate()?);
                }
                let disabling = matches!(command, flclash_strict_contract::BrokerCommand::DisablePolicy { .. });
                let mut result = broker.as_mut().context("strict Broker session missing")?.request(command);
                if disabling && result.is_err() {
                    // An earlier disable may have committed before a lost
                    // response/crash. Only an authenticated empty proof can
                    // confirm it; the orchestrator checks all cleanup fields.
                    if let Ok(proof) = broker.as_mut().context("strict Broker session missing")?
                        .request(flclash_strict_contract::BrokerCommand::Status {}) {
                        if proof.revision == 0 { result = Ok(proof); }
                    }
                }
                if result.is_err() {
                    // Discard capabilities on every transport/protocol failure.
                    // A retry performs a new authenticated activation exchange.
                    *broker = None;
                }
                result
            })
            .await;
            let proof = match result {
                Ok(Ok(proof)) => proof,
                Ok(Err(error)) => {
                    shared
                        .logger
                        .log(format!("strict Broker request failed: {error:#}"));
                    runtime.orchestrator.lock().await.broker_lost(runtime.policy.read().await.revision);
                    set_strict_policy(
                        shared,
                        crate::protocol::StrictPolicyState::Blocking,
                        Some(error.downcast_ref::<crate::broker::BrokerDiagnostic>()
                            .map(crate::broker::BrokerDiagnostic::failure_reason)
                            .unwrap_or(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable)),
                    )
                    .await;
                    return false;
                }
                Err(error) => {
                    shared
                        .logger
                        .log(format!("strict Broker worker failed: {error}"));
                    runtime.orchestrator.lock().await.broker_lost(runtime.policy.read().await.revision);
                    set_strict_policy(
                        shared,
                        crate::protocol::StrictPolicyState::Blocking,
                        Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
                    )
                    .await;
                    return false;
                }
            };
            let next = {
                let mut orchestrator = runtime.orchestrator.lock().await;
                match orchestrator.accept_broker_proof(proof) {
                    Ok(action) => action,
                    Err(error) => {
                        shared
                            .logger
                            .log(format!("strict Broker proof rejected: {error:#}"));
                        orchestrator.broker_lost(runtime.policy.read().await.revision);
                        set_strict_policy(
                            shared,
                            crate::protocol::StrictPolicyState::Blocking,
                            Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable),
                        )
                        .await;
                        return false;
                    }
                }
            };
            Box::pin(drive_strict_action(shared, runtime, next)).await
        }
    }
}

fn strict_target_key(path: &str) -> String {
    if cfg!(windows) {
        path.to_ascii_lowercase()
    } else {
        path.to_owned()
    }
}

/// A single bounded supervisor serves the active policy, including while UI
/// is detached. It never removes guards or skips the fresh Broker/Core commit.
#[cfg(windows)]
async fn supervise_strict_recovery(shared: Arc<Shared>) {
    let mut last_health_check = Instant::now();
    let mut timer = tokio::time::interval(Duration::from_secs(1));
    timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        timer.tick().await;
        if shared.shutting_down.load(Ordering::Acquire) { break; }
        if *shared.status.read().await != CoreStatus::Ready { continue; }
        let Some(runtime) = shared.strict_runtime.lock().await.clone() else { continue; };
        let mut orchestrator = runtime.orchestrator.lock().await;
        let status = orchestrator.status();
        if status.state == StrictState::Armed && last_health_check.elapsed() >= Duration::from_secs(5) {
            last_health_check = Instant::now();
            let worker_runtime = runtime.clone();
            let health = tokio::task::spawn_blocking(move || {
                let mut broker = worker_runtime.broker.lock()
                    .map_err(|_| anyhow!("strict Broker session lock poisoned"))?;
                let result = broker.as_mut().context("strict Broker session missing")?
                    .request(flclash_strict_contract::BrokerCommand::Status {});
                if result.is_err() { *broker = None; }
                result
            }).await;
            match health {
                Ok(Ok(proof)) => {
                    match orchestrator.accept_broker_proof(proof) {
                        Ok(action) => {
                            drop(orchestrator);
                            let _ = drive_strict_action(&shared, runtime, action).await;
                        }
                        Err(error) => {
                            orchestrator.broker_lost(runtime.policy.read().await.revision);
                            shared.logger.log(format!("strict health proof rejected: {error:#}"));
                        }
                    }
                }
                _ => {
                    orchestrator.broker_lost(runtime.policy.read().await.revision);
                    set_strict_policy(&shared, crate::protocol::StrictPolicyState::Blocking,
                        Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable)).await;
                    shared.logger.log("strict Broker health lost; authenticated recovery required");
                }
            }
            continue;
        }
        drop(orchestrator);
        if status.state != StrictState::Blocking { continue; }
        let mut retry_at = runtime.retry_at.lock().await;
        if retry_at.is_none() {
            let Some(decision) = runtime.retry.lock().await.schedule_failure() else { continue; };
            *retry_at = Some(Instant::now() + decision.delay);
            shared.logger.log(format!("strict recovery scheduled attempt={}", decision.attempt));
            publish_strict_status(&shared).await;
        }
        if retry_at.is_some_and(|deadline| Instant::now() < deadline) { continue; }
        *retry_at = None;
        drop(retry_at);
        runtime.retry.lock().await.started();
        set_strict_policy(&shared, crate::protocol::StrictPolicyState::Recovering, None).await;
        let action = runtime.orchestrator.lock().await.recover(runtime.policy.read().await.clone());
        match action {
            Ok(action) => { let _ = drive_strict_action(&shared, runtime, action).await; }
            Err(error) => {
                set_strict_policy(&shared, crate::protocol::StrictPolicyState::Blocking,
                    Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable)).await;
                shared.logger.log(format!("strict recovery remains blocked: {error:#}"));
            }
        }
    }
}

async fn retry_or_command(
    delay: Duration,
    commands: &mut mpsc::Receiver<SupervisorCommand>,
) -> Option<SessionEnd> {
    tokio::select! {
        _ = tokio::time::sleep(delay) => None,
        command = commands.recv() => Some(resolve_supervisor_command(command)),
    }
}

pub async fn run(config: AgentConfig) -> Result<()> {
    let logger = AgentLogger::new(&config.home);
    logger.log(format!(
        "agent starting use_helper={} helper_port={}",
        config.use_helper, config.helper_port
    ));
    let ui_listener = match TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
        .await
        .context("unable to bind UI IPC listener")
    {
        Ok(listener) => listener,
        Err(error) => {
            logger.log(format!("agent startup failed: {error:#}"));
            return Err(error);
        }
    };
    let core_listener = match TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
        .await
        .context("unable to bind Core IPC listener")
    {
        Ok(listener) => listener,
        Err(error) => {
            logger.log(format!("agent startup failed: {error:#}"));
            return Err(error);
        }
    };
    let ui_address = match ui_listener.local_addr() {
        Ok(address) => address,
        Err(error) => {
            logger.log(format!("resolve UI IPC address failed: {error}"));
            return Err(error.into());
        }
    };
    let (_endpoint_guard, endpoint) = match EndpointGuard::acquire(&config.home, ui_address) {
        Ok(endpoint) => endpoint,
        Err(error) => {
            logger.log(format!("create Agent endpoint failed: {error:#}"));
            return Err(error);
        }
    };
    let endpoint_token = endpoint.token;
    let core_token = random_token();
    let helper_token = if config.use_helper {
        match load_or_create_helper_token(&config.home) {
            Ok(token) => Some(token),
            Err(error) => {
                logger.log(format!("load Helper credential failed: {error:#}"));
                return Err(error);
            }
        }
    } else {
        None
    };
    let shared_helper_port = config.use_helper.then_some(config.helper_port);
    let shared_helper_token = helper_token.clone();
    let shared_home_dir = config.home.clone();
    let (supervisor_tx, supervisor_rx) = mpsc::channel(16);
    #[cfg(windows)]
    let (strict_store, stored_intent) = match crate::strict_store::StrictIntentStore::open(&shared_home_dir) {
        Ok(store) => match store.load() {
            Ok(intent) => (Some(store), intent),
            Err(error) => { logger.log(format!("strict stored intent rejected: {error:#}")); (None, None) }
        },
        Err(error) => { logger.log(format!("strict intent storage unavailable: {error:#}")); (None, None) }
    };
    #[cfg(target_os = "macos")]
    let mac_strict_account = {
        use sha2::{Digest, Sha256};
        let path = std::fs::canonicalize(&shared_home_dir).context("macOS Agent home is unavailable")?;
        let digest = Sha256::digest(path.as_os_str().as_encoded_bytes());
        format!("strict-ingress-{}", digest.iter().map(|byte| format!("{byte:02x}")).collect::<String>())
    };
    #[cfg(target_os = "macos")]
    let (mac_strict_replay, initial_journal) = {
        let account = mac_strict_account.clone();
        let saved = tokio::task::spawn_blocking(move || crate::mac_strict_store::load(&account))
            .await.context("macOS strict recovery load task failed")??;
        crate::mac_strict_replay::MacStrictReplay::decode_store(saved.as_deref(), &shared_home_dir)?
    };
    #[cfg(not(target_os = "macos"))]
    let initial_journal = ReplayJournal::default();
    let shared = Arc::new(Shared {
        ui: Mutex::new(None),
        core: Mutex::new(None),
        journal: Mutex::new(initial_journal),
        #[cfg(target_os = "macos")]
        mac_strict_replay: Mutex::new(mac_strict_replay),
        #[cfg(target_os = "macos")]
        mac_strict_account,
        logger: logger.clone(),
        status: RwLock::new(CoreStatus::Starting),
        strict_policy: RwLock::new(StrictPolicyStatus::disabled()),
        generation: AtomicU64::new(0),
        next_session: AtomicU64::new(1),
        shutting_down: AtomicBool::new(false),
        shutdown: Notify::new(),
        supervisor: supervisor_tx,
        privileged_backend: config.use_helper,
        helper_port: shared_helper_port,
        helper_token: shared_helper_token,
        home_dir: shared_home_dir,
        strict_blocks: Mutex::new(HashSet::new()),
        #[cfg(windows)]
        strict_runtime: Mutex::new(None),
        #[cfg(windows)]
        strict_store: Mutex::new(strict_store),
    });
    #[cfg(windows)]
    {
        let storage_available = shared.strict_store.lock().await.is_some();
        if !storage_available {
            set_strict_policy(&shared, crate::protocol::StrictPolicyState::Blocking,
                Some(crate::protocol::StrictPolicyFailureReason::BrokerUnavailable)).await;
        } else if let Some(intent) = stored_intent {
            restore_strict_intent(&shared, intent).await;
        }
    }

    #[cfg(windows)]
    let strict_recovery = tokio::spawn(supervise_strict_recovery(shared.clone()));

    let supervisor_shared = shared.clone();
    let supervisor = tokio::spawn(async move {
        supervise_core(
            config,
            core_listener,
            core_token,
            helper_token,
            supervisor_rx,
            supervisor_shared,
        )
        .await
    });

    loop {
        tokio::select! {
            accepted = ui_listener.accept() => {
                let (stream, address) = match accepted {
                    Ok(value) => value,
                    Err(error) => {
                        logger.log(format!("UI IPC accept failed: {error}"));
                        return Err(error.into());
                    }
                };
                if !address.ip().is_loopback() {
                    continue;
                }
                let handler_shared = shared.clone();
                let handler_logger = shared.logger.clone();
                let token = endpoint_token.clone();
                tokio::spawn(async move {
                    if let Err(error) = handle_ui(stream, token, handler_shared).await {
                        handler_logger.log(format!("UI session error: {error:#}"));
                    }
                });
            }
            _ = shared.shutdown.notified() => break,
        }
        if shared.shutting_down.load(Ordering::Acquire) {
            break;
        }
    }

    #[cfg(windows)]
    strict_recovery.abort();
    let result = supervisor.await.context("Core supervisor task failed")?;
    if let Err(error) = &result {
        logger.log(format!("Core supervisor failed: {error:#}"));
    }
    result
}

async fn handle_ui(stream: TcpStream, token: String, shared: Arc<Shared>) -> Result<()> {
    let mut reader = BufReader::new(stream);
    let auth = read_bounded_line(&mut reader, MAX_AUTH_LINE_BYTES)
        .await?
        .ok_or_else(|| anyhow!("UI disconnected before authentication"))?;
    if !authenticate(auth.trim_end(), &token) {
        bail!("UI authentication failed");
    }

    let stream = reader.into_inner();
    let (read_half, mut write_half) = stream.into_split();
    let (output_tx, mut output_rx) = mpsc::channel::<UiOutput>(CHANNEL_CAPACITY);
    let session_id = shared.next_session.fetch_add(1, Ordering::Relaxed);
    let session_cancel = Arc::new(SessionCancel {
        cancelled: AtomicBool::new(false),
        notify: Notify::new(),
    });
    {
        let mut current = shared.ui.lock().await;
        if let Some(previous) = current.replace(UiSession {
            id: session_id,
            output: output_tx.clone(),
            cancel: session_cancel.clone(),
        }) {
            previous.cancel.cancel();
        }
    }

    let writer = tokio::spawn(async move {
        while let Some(output) = output_rx.recv().await {
            write_half.write_all(output.line.as_bytes()).await?;
            write_half.write_all(b"\n").await?;
            write_half.flush().await?;
            if let Some(delivered) = output.delivered {
                let _ = delivered.send(());
            }
        }
        Result::<()>::Ok(())
    });

    output_tx
        .send(UiOutput::new(ready_envelope(&shared).await))
        .await?;
    send_ui_activity(&shared, true).await;

    let mut reader = BufReader::new(read_half);
    let session_result: Result<()> = async {
    loop {
        if session_cancel.cancelled.load(Ordering::Acquire) {
            break;
        }
        let line = tokio::select! {
            line = read_bounded_line(&mut reader, MAX_MESSAGE_LINE_BYTES) => line?,
            _ = session_cancel.notify.notified() => break,
        };
        let Some(line) = line else {
            break;
        };
        let line = line.trim_end();
        if line.is_empty() {
            continue;
        }
        if let Some(control) = parse_control(line) {
            let shutdown = matches!(control.command, AgentCommand::ShutdownAgent);
            let (ok, state, identity) = match control.command {
                AgentCommand::Status => (true, *shared.status.read().await, None),
                AgentCommand::RestartCore => {
                    let (ok, state) =
                        issue_supervisor_command(&shared, SupervisorCommandKind::Restart).await;
                    (ok, state, None)
                }
                AgentCommand::StopCore => {
                    let (ok, state) =
                        issue_supervisor_command(&shared, SupervisorCommandKind::Stop).await;
                    (ok, state, None)
                }
                AgentCommand::ShutdownAgent => {
                    let (ok, state) =
                        issue_supervisor_command(&shared, SupervisorCommandKind::Shutdown).await;
                    (ok, state, None)
                }
                AgentCommand::ApplyStrictBlock => (
                    apply_strict_block(&shared, control.path.clone()).await,
                    *shared.status.read().await,
                    None,
                ),
                AgentCommand::ClearStrictBlock => (
                    clear_strict_block(&shared, control.path.clone()).await,
                    *shared.status.read().await,
                    None,
                ),
                AgentCommand::ApplyStrictPolicy => (
                    apply_strict_policy(&shared, control.policy.clone()).await,
                    *shared.status.read().await,
                    None,
                ),
                AgentCommand::MigrateStrictPolicy => (
                    migrate_strict_policy(&shared, control.path.clone(), control.policy.clone()).await,
                    *shared.status.read().await,
                    None,
                ),
                AgentCommand::ClearStrictPolicy => (
                    clear_strict_policy(&shared).await,
                    *shared.status.read().await,
                    None,
                ),
                AgentCommand::InspectStrictIdentity => {
                    match inspect_strict_identity(&shared, control.path.clone()).await {
                        Ok(identity) => (true, *shared.status.read().await, Some(identity)),
                        Err(error) => {
                            shared
                                .logger
                                .log(format!("strict identity inspection failed: {error:#}"));
                            (false, *shared.status.read().await, None)
                        }
                    }
                }
            };
            let response = json!({
                "_agent": {
                    "type": "commandResult",
                    "id": control.id,
                    "ok": ok,
                    "coreState": state.as_str(),
                    "generation": shared.generation.load(Ordering::Acquire),
                    "strictPolicy": strict_policy_json(&shared).await,
                    "identity": identity,
                }
            });
            let delivered = if shutdown {
                let (tx, rx) = oneshot::channel();
                let _ = output_tx
                    .send(UiOutput {
                        line: response.to_string(),
                        delivered: Some(tx),
                    })
                    .await;
                Some(rx)
            } else {
                let _ = output_tx.send(UiOutput::new(response.to_string())).await;
                None
            };
            if shutdown {
                if let Some(delivered) = delivered {
                    let _ = timeout(Duration::from_secs(1), delivered).await;
                }
                signal_shutdown(&shared);
                break;
            }
            continue;
        }

        let action = serde_json::from_str::<Value>(line).context("invalid Core action JSON")?;
        if action.get("id").and_then(Value::as_str).is_none()
            || action.get("method").and_then(Value::as_str).is_none()
            || action.get("data").is_none()
        {
            bail!("invalid Core action envelope");
        }
        let core = shared.core.lock().await.clone();
        if let Some(core) = core {
            #[cfg(target_os = "macos")]
            shared.mac_strict_replay.lock().await.stage(&action)?;
            shared.journal.lock().await.stage(line);
            if core.send(line.to_owned()).await.is_err() {
                #[cfg(target_os = "macos")]
                shared.mac_strict_replay.lock().await.discard_pending();
                shared.journal.lock().await.discard_pending();
                bail!("Core command channel is closed");
            }
        } else {
            let response = json!({
                "_agent": {
                    "type": "coreUnavailable",
                    "id": action["id"],
                    "coreState": shared.status.read().await.as_str(),
                }
            });
            output_tx.send(UiOutput::new(response.to_string())).await?;
        }
    }
    Ok(())
    }.await;

    let owns_session = {
        let mut current = shared.ui.lock().await;
        if current
            .as_ref()
            .is_some_and(|session| session.id == session_id)
        {
            *current = None;
            true
        } else {
            false
        }
    };
    if owns_session {
        send_ui_activity(&shared, false).await;
    }
    drop(output_tx);
    writer.abort();
    session_result
}

#[derive(Clone, Copy)]
enum SupervisorCommandKind {
    Restart,
    Stop,
    Shutdown,
}

async fn issue_supervisor_command(
    shared: &Arc<Shared>,
    command: SupervisorCommandKind,
) -> (bool, CoreStatus) {
    let command_name = match command {
        SupervisorCommandKind::Restart => "restart",
        SupervisorCommandKind::Stop => "stop",
        SupervisorCommandKind::Shutdown => "shutdown",
    };
    let (tx, rx) = oneshot::channel();
    let message = match command {
        SupervisorCommandKind::Restart => SupervisorCommand::Restart(tx),
        SupervisorCommandKind::Stop => SupervisorCommand::Stop(tx),
        SupervisorCommandKind::Shutdown => SupervisorCommand::Shutdown(tx),
    };
    let sent = shared.supervisor.send(message).await.is_ok();
    let acknowledged = if sent {
        timeout(Duration::from_secs(10), rx)
            .await
            .ok()
            .and_then(Result::ok)
            .unwrap_or(false)
    } else {
        false
    };
    if !sent || !acknowledged {
        shared
            .logger
            .log(format!("supervisor command failed command={command_name}"));
    }
    (sent && acknowledged, *shared.status.read().await)
}

async fn supervise_core(
    config: AgentConfig,
    core_listener: TcpListener,
    core_token: String,
    helper_token: Option<String>,
    mut commands: mpsc::Receiver<SupervisorCommand>,
    shared: Arc<Shared>,
) -> Result<()> {
    let core_port = core_listener.local_addr()?.port();
    let mut child = None;
    let mut should_start = true;
    let mut crashes = 0_u32;

    loop {
        if !should_start {
            set_status(&shared, CoreStatus::Stopped).await;
            let end = resolve_supervisor_command(commands.recv().await);
            if apply_supervisor_end(end, &mut should_start, &shared).await {
                return Ok(());
            }
            continue;
        }

        set_status(&shared, CoreStatus::Starting).await;
        if let Err(error) = start_backend(
            &config,
            core_port,
            &core_token,
            helper_token.as_deref(),
            &shared.logger,
            &mut child,
        )
        .await
        {
            shared.logger.log(format!("Core start error: {error:#}"));
            crashes += 1;
            if crashes > MAX_CRASH_RETRIES {
                set_status(&shared, CoreStatus::Failed).await;
                should_start = false;
                continue;
            }
            if let Some(end) = retry_or_command(crash_delay(crashes), &mut commands).await {
                if apply_supervisor_end(end, &mut should_start, &shared).await {
                    return Ok(());
                }
            }
            continue;
        }

        let attach = tokio::select! {
            result = accept_core(&core_listener, &core_token) => Some(result),
            command = commands.recv() => {
                let end = resolve_supervisor_command(command);
                stop_backend(
                    &config,
                    helper_token.as_deref(),
                    &shared.logger,
                    &mut child,
                )
                .await;
                if apply_supervisor_end(end, &mut should_start, &shared).await {
                    return Ok(());
                }
                None
            }
        };
        let Some(attach) = attach else {
            continue;
        };
        let mut stream = match attach {
            Ok(stream) => stream,
            Err(error) => {
                shared.logger.log(format!("Core attach error: {error:#}"));
                stop_backend(&config, helper_token.as_deref(), &shared.logger, &mut child).await;
                crashes += 1;
                if crashes > MAX_CRASH_RETRIES {
                    set_status(&shared, CoreStatus::Failed).await;
                    should_start = false;
                } else if let Some(end) =
                    retry_or_command(crash_delay(crashes), &mut commands).await
                {
                    if apply_supervisor_end(end, &mut should_start, &shared).await {
                        return Ok(());
                    }
                }
                continue;
            }
        };

        let replay = tokio::select! {
            result = replay_journal(&mut stream, &shared) => Some(result),
            command = commands.recv() => {
                let end = resolve_supervisor_command(command);
                stop_backend(
                    &config,
                    helper_token.as_deref(),
                    &shared.logger,
                    &mut child,
                )
                .await;
                if apply_supervisor_end(end, &mut should_start, &shared).await {
                    return Ok(());
                }
                None
            }
        };
        let Some(replay) = replay else {
            continue;
        };
        if let Err(error) = replay {
            shared.logger.log(format!("Core replay error: {error:#}"));
            stop_backend(&config, helper_token.as_deref(), &shared.logger, &mut child).await;
            crashes += 1;
            if crashes > MAX_CRASH_RETRIES {
                set_status(&shared, CoreStatus::Failed).await;
                should_start = false;
            } else if let Some(end) = retry_or_command(crash_delay(crashes), &mut commands).await {
                if apply_supervisor_end(end, &mut should_start, &shared).await {
                    return Ok(());
                }
            }
            continue;
        }

        let (read_half, mut write_half) = stream.into_split();
        let (core_tx, mut core_rx) = mpsc::channel::<String>(CHANNEL_CAPACITY);
        *shared.core.lock().await = Some(core_tx);
        shared.generation.fetch_add(1, Ordering::AcqRel);
        set_status(&shared, CoreStatus::Ready).await;
        let ready_at = Instant::now();

        let writer = tokio::spawn(async move {
            while let Some(line) = core_rx.recv().await {
                write_half.write_all(line.as_bytes()).await?;
                write_half.write_all(b"\n").await?;
            }
            Result::<()>::Ok(())
        });
        let mut reader = BufReader::new(read_half);
        let session_end = loop {
            tokio::select! {
                line = read_bounded_line(&mut reader, MAX_MESSAGE_LINE_BYTES) => {
                    match line {
                        Ok(Some(line)) => {
                            let line = line.trim_end().to_owned();
                            #[cfg(windows)]
                            if handle_strict_core_line(&shared, &line).await {
                                continue;
                            }
                            shared.journal.lock().await.commit_response(&line);
                            #[cfg(target_os = "macos")]
                            {
                                let response: Value = serde_json::from_str(&line)?;
                                let mut state = shared.mac_strict_replay.lock().await;
                                let previous = state.clone();
                                let outcome = async {
                                    state.commit_response(&response)?;
                                    if response.get("code").and_then(Value::as_i64) == Some(0) {
                                        let method = response.get("method").and_then(Value::as_str).unwrap_or_default();
                                        if method == "configureStrictIngress" ||
                                            ["initClash", "setState", "setupConfig", "updateConfig", "startListener", "stopListener", "startLog", "stopLog", "changeProxy"].contains(&method) {
                                            let snapshot = state.encode_store(&shared.journal.lock().await, &shared.home_dir)?;
                                            let account = shared.mac_strict_account.clone();
                                            tokio::task::spawn_blocking(move || crate::mac_strict_store::save(&account, snapshot.as_deref()))
                                                .await.context("macOS strict recovery save task failed")??;
                                        }
                                    }
                                    Ok::<(), anyhow::Error>(())
                                }.await;
                                if outcome.is_err() {
                                    *state = previous;
                                    drop(state);
                                    shared.logger.log("macOS strict ingress persistence rejected; stopping Core");
                                    let mut rejected = response;
                                    rejected["code"] = json!(-1);
                                    rejected["data"] = json!("strict ingress secure persistence failed");
                                    forward_to_ui(&shared, rejected.to_string()).await;
                                    break SessionEnd::Stopped;
                                }
                            }
                            forward_to_ui(&shared, line).await;
                        }
                        Ok(None) => break SessionEnd::Crashed,
                        Err(error) => {
                            shared.logger.log(format!("Core read error: {error:#}"));
                            break SessionEnd::Crashed;
                        }
                    }
                }
                command = commands.recv() => {
                    break resolve_supervisor_command(command)
                }
            }
        };

        *shared.core.lock().await = None;
        shared.journal.lock().await.discard_pending();
        #[cfg(target_os = "macos")]
        shared.mac_strict_replay.lock().await.discard_pending();
        #[cfg(windows)]
        if matches!(&session_end, SessionEnd::Crashed | SessionEnd::Restart) {
            fail_closed_strict_core_loss(&shared).await;
        }
        writer.abort();
        stop_backend(&config, helper_token.as_deref(), &shared.logger, &mut child).await;
        match session_end {
            SessionEnd::Restart => should_start = true,
            SessionEnd::Stopped => should_start = false,
            SessionEnd::Crashed => {
                crashes = if ready_at.elapsed() >= Duration::from_secs(60) {
                    1
                } else {
                    crashes + 1
                };
                if crashes > MAX_CRASH_RETRIES {
                    set_status(&shared, CoreStatus::Failed).await;
                    should_start = false;
                } else if let Some(end) =
                    retry_or_command(crash_delay(crashes), &mut commands).await
                {
                    if apply_supervisor_end(end, &mut should_start, &shared).await {
                        return Ok(());
                    }
                }
            }
            SessionEnd::ShutdownRequested => return Ok(()),
            SessionEnd::Shutdown => {
                signal_shutdown(&shared);
                return Ok(());
            }
        }
    }
}

#[cfg(windows)]
async fn fail_closed_strict_core_loss(shared: &Arc<Shared>) {
    let Some(runtime) = shared.strict_runtime.lock().await.clone() else {
        return;
    };
    set_strict_policy(
        shared,
        crate::protocol::StrictPolicyState::Recovering,
        Some(crate::protocol::StrictPolicyFailureReason::CoreUnavailable),
    )
    .await;
    let action = {
        let mut orchestrator = runtime.orchestrator.lock().await;
        orchestrator.force_blocking()
    };
    let action = match action {
        Ok(action) => action,
        Err(error) => {
            shared.logger.log(format!(
                "strict Core loss could not enter blocking phase: {error:#}"
            ));
            set_strict_policy(
                shared,
                crate::protocol::StrictPolicyState::Blocking,
                Some(crate::protocol::StrictPolicyFailureReason::CoreUnavailable),
            )
            .await;
            return;
        }
    };
    if !drive_strict_action(shared, runtime, action).await {
        shared
            .logger
            .log("strict Core loss recovery left policy fail-closed");
        set_strict_policy(
            shared,
            crate::protocol::StrictPolicyState::Blocking,
            Some(crate::protocol::StrictPolicyFailureReason::CoreUnavailable),
        )
        .await;
    }
}

#[cfg(windows)]
async fn handle_strict_core_line(shared: &Arc<Shared>, line: &str) -> bool {
    let Ok(value) = serde_json::from_str::<Value>(line) else {
        return false;
    };
    let Some(id) = value.get("id").and_then(Value::as_str) else {
        return false;
    };
    let Some(runtime) = shared.strict_runtime.lock().await.clone() else {
        return false;
    };
    let pending = runtime.pending_core_id.lock().await.clone();
    if pending.as_deref() != Some(id) {
        return false;
    }
    *runtime.pending_core_id.lock().await = None;
    let action = {
        let mut orchestrator = runtime.orchestrator.lock().await;
        match orchestrator.accept_core_response(line) {
            Ok(action) => action,
            Err(error) => {
                shared
                    .logger
                    .log(format!("strict Core response rejected: {error:#}"));
                if let Ok(fallback) = orchestrator.force_blocking() {
                    drop(orchestrator);
                    let _ = drive_strict_action(shared, runtime, fallback).await;
                }
                return true;
            }
        }
    };
    let _ = drive_strict_action(shared, runtime, action).await;
    true
}

async fn start_backend(
    config: &AgentConfig,
    core_port: u16,
    token: &str,
    helper_token: Option<&str>,
    logger: &Arc<AgentLogger>,
    child: &mut Option<Child>,
) -> Result<()> {
    if config.use_helper {
        let service_core = config
            .service_core
            .as_ref()
            .context("service Core is unavailable")?;
        logger.log(format!("starting Core through Helper on port={core_port}"));
        helper_request(
            config.helper_port,
            "/start",
            Some(json!({
                "path": service_core,
                "arg": core_port.to_string(),
                "home_dir": config.home,
                "auth_token": token,
                "helper_token": helper_token.context("Helper credential is unavailable")?,
            })),
        )
        .await?;
        return Ok(());
    }

    let mut command = Command::new(&config.core);
    #[cfg(target_os = "macos")]
    let launch_credential = "@stdin";
    #[cfg(not(target_os = "macos"))]
    let launch_credential = token;
    command
        .arg(core_port.to_string())
        .arg(launch_credential)
        .env("SAFE_PATHS", &config.home)
        .stdin(if cfg!(target_os = "macos") { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut process = command.spawn().context("unable to spawn local Core")?;
    #[cfg(target_os = "macos")]
    {
        let mut input = process.stdin.take().context("Core private credential pipe unavailable")?;
        input.write_all(format!("{token}\n").as_bytes()).await?;
        input.shutdown().await?;
    }
    if let Some(stdout) = process.stdout.take() {
        spawn_core_output_logger(stdout, logger.clone(), "stdout");
    }
    if let Some(stderr) = process.stderr.take() {
        spawn_core_output_logger(stderr, logger.clone(), "stderr");
    }
    logger.log(format!("local Core spawned on port={core_port}"));
    *child = Some(process);
    Ok(())
}

async fn stop_backend(
    config: &AgentConfig,
    helper_token: Option<&str>,
    logger: &Arc<AgentLogger>,
    child: &mut Option<Child>,
) {
    if config.use_helper {
        if let Some(helper_token) = helper_token {
            logger.log("stopping Core through Helper");
            let _ = helper_request(
                config.helper_port,
                "/stop",
                Some(json!({
                    "home_dir": config.home,
                    "helper_token": helper_token,
                })),
            )
            .await;
        }
    }
    if let Some(mut process) = child.take() {
        logger.log("stopping local Core");
        let _ = process.kill().await;
        let _ = process.wait().await;
    }
}

fn spawn_core_output_logger<R>(stream: R, logger: Arc<AgentLogger>, channel: &'static str)
where
    R: AsyncRead + Unpin + Send + 'static,
{
    tokio::spawn(async move {
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line).await {
                Ok(0) => break,
                Ok(_) => logger.log(format!("Core {channel}: {}", line.trim_end())),
                Err(error) => {
                    logger.log(format!("Core {channel} read error: {error}"));
                    break;
                }
            }
        }
    });
}

async fn helper_request(port: u16, path: &str, body: Option<Value>) -> Result<()> {
    let _ = helper_request_raw(port, path, body).await?;
    Ok(())
}

async fn helper_request_json(port: u16, path: &str, body: Value) -> Result<Value> {
    let response = helper_request_raw(port, path, Some(body)).await?;
    serde_json::from_str(&response).context("Helper returned invalid JSON")
}

async fn helper_request_raw(port: u16, path: &str, body: Option<Value>) -> Result<String> {
    let body = body.map(|value| value.to_string()).unwrap_or_default();
    let mut stream = timeout(
        Duration::from_secs(2),
        TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, port)),
    )
    .await
    .context("Helper connection timed out")??;
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    stream.write_all(request.as_bytes()).await?;
    let mut response = Vec::new();
    timeout(
        Duration::from_secs(2),
        stream
            .take((HELPER_RESPONSE_LIMIT + 1) as u64)
            .read_to_end(&mut response),
    )
    .await
    .context("Helper response timed out")??;
    if response.len() > HELPER_RESPONSE_LIMIT {
        bail!("Helper response exceeded the size limit");
    }
    let response = String::from_utf8(response).context("Helper returned non-UTF-8 data")?;
    let (headers, body) = response
        .split_once("\r\n\r\n")
        .context("invalid Helper HTTP response")?;
    if !headers
        .lines()
        .next()
        .is_some_and(|line| line.contains(" 200 "))
    {
        bail!("Helper rejected the request");
    }
    Ok(body.to_owned())
}

async fn accept_core(listener: &TcpListener, expected_token: &str) -> Result<TcpStream> {
    let deadline = Instant::now() + CORE_CONNECT_TIMEOUT;
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            bail!("Core did not authenticate before the deadline");
        }
        let (stream, address) = timeout(remaining, listener.accept())
            .await
            .context("Core connection timed out")??;
        if !address.ip().is_loopback() {
            continue;
        }
        let mut reader = BufReader::new(stream);
        let Some(line) = timeout(remaining, read_bounded_line(&mut reader, MAX_AUTH_LINE_BYTES))
            .await.context("Core authentication timed out")?? else {
            continue;
        };
        #[cfg(target_os = "macos")]
        {
            let reply = match mac_core_handshake_reply(&line, expected_token) {
                Ok(reply) => reply,
                Err(_) => continue,
            };
            timeout(remaining, reader.get_mut().write_all(reply.as_bytes()))
                .await.context("macOS Core authentication reply timed out")??;
            return Ok(reader.into_inner());
        }
        #[cfg(not(target_os = "macos"))]
        let valid = serde_json::from_str::<Value>(line.trim_end())
            .ok()
            .and_then(|value| {
                value
                    .get("_agentCore")?
                    .get("token")?
                    .as_str()
                    .map(str::to_owned)
            })
            .is_some_and(|token| crate::protocol::constant_time_eq(&token, expected_token));
        #[cfg(not(target_os = "macos"))]
        if valid {
            return Ok(reader.into_inner());
        }
    }
}

#[cfg(target_os = "macos")]
fn mac_core_handshake_reply(line: &str, token: &str) -> Result<String> {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;
    fn decode_hex(value: &str) -> Result<Vec<u8>> {
        if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            bail!("invalid macOS Core authentication field");
        }
        (0..64).step_by(2).map(|offset| {
            u8::from_str_radix(&value[offset..offset + 2], 16).map_err(Into::into)
        }).collect()
    }
    let message: Value = serde_json::from_str(line)?;
    let auth = message.get("_macCore").context("missing macOS Core authentication")?;
    if auth.get("protocol").and_then(Value::as_u64) != Some(1) {
        bail!("unsupported macOS Core authentication protocol");
    }
    let nonce = auth.get("nonce").and_then(Value::as_str).context("missing nonce")?;
    let _ = decode_hex(nonce)?;
    let proof = decode_hex(auth.get("proof").and_then(Value::as_str).context("missing proof")?)?;
    let key = decode_hex(token)?;
    let mut verifier = Hmac::<Sha256>::new_from_slice(&key).context("invalid MAC key")?;
    verifier.update(format!("FCX-MAC-CORE/1/core/{nonce}").as_bytes());
    verifier.verify_slice(&proof).map_err(|_| anyhow!("macOS Core proof rejected"))?;
    let mut signer = Hmac::<Sha256>::new_from_slice(&key).context("invalid MAC key")?;
    signer.update(format!("FCX-MAC-CORE/1/host/{nonce}").as_bytes());
    let proof = signer.finalize().into_bytes().iter().map(|byte| format!("{byte:02x}")).collect::<String>();
    Ok(format!("{}\n", json!({"_macCore": {"protocol": 1, "nonce": nonce, "proof": proof}})))
}

async fn replay_journal(stream: &mut TcpStream, shared: &Arc<Shared>) -> Result<()> {
    let lines = shared.journal.lock().await.replay_lines();
    for line in lines {
        let expected_id = serde_json::from_str::<Value>(&line)?["id"]
            .as_str()
            .context("replay action has no id")?
            .to_owned();
        stream.write_all(line.as_bytes()).await?;
        stream.write_all(b"\n").await?;
        timeout(CORE_REPLAY_TIMEOUT, async {
            loop {
                let response = read_line_bytewise(stream, MAX_MESSAGE_LINE_BYTES)
                    .await?
                    .context("Core disconnected during replay")?;
                let value = serde_json::from_str::<Value>(response.trim_end())?;
                if value.get("id").and_then(Value::as_str) == Some(expected_id.as_str()) {
                    if value
                        .get("code")
                        .and_then(Value::as_i64)
                        .unwrap_or_default()
                        != 0
                    {
                        bail!("Core rejected replay action {expected_id}");
                    }
                    return Ok(());
                }
            }
        })
        .await
        .with_context(|| format!("Core replay timed out for {expected_id}"))??;
    }
    #[cfg(target_os = "macos")]
    let strict_stopped = shared.journal.lock().await.listener_running() == Some(false);
    #[cfg(target_os = "macos")]
    let strict_replay = {
        let state = shared.mac_strict_replay.lock().await;
        if strict_stopped { state.stopped_replay_line() } else { state.replay_line() }
    };
    #[cfg(target_os = "macos")]
    if let Some(line) = strict_replay {
        stream.write_all(line.as_bytes()).await?;
        stream.write_all(b"\n").await?;
        let response = timeout(CORE_REPLAY_TIMEOUT, async {
            loop {
                let line = read_line_bytewise(stream, MAX_MESSAGE_LINE_BYTES).await?
                    .context("Core disconnected during strict ingress recovery")?;
                let value: Value = serde_json::from_str(&line)?;
                if value.get("id").and_then(Value::as_str) == Some(if strict_stopped { "_agent-macos-strict-intent" } else { "_agent-macos-strict-replay" }) {
                    return Ok::<Value, anyhow::Error>(value);
                }
            }
        }).await.context("strict ingress recovery timed out")??;
        if strict_stopped {
            if response.get("code").and_then(Value::as_i64) != Some(0) || response.get("data").and_then(Value::as_bool) != Some(true) {
                bail!("Core rejected stopped strict ingress intent");
            }
        } else {
            shared.mac_strict_replay.lock().await.validate_replay(&response)?;
        }
    }
    Ok(())
}

async fn read_line_bytewise(stream: &mut TcpStream, max: usize) -> Result<Option<String>> {
    let mut bytes = Vec::new();
    let mut byte = [0_u8; 1];
    loop {
        let count = stream.read(&mut byte).await?;
        if count == 0 {
            return if bytes.is_empty() {
                Ok(None)
            } else {
                bail!("truncated IPC line")
            };
        }
        bytes.push(byte[0]);
        if bytes.len() > max {
            bail!("IPC line exceeded {max} bytes");
        }
        if byte[0] == b'\n' {
            return Ok(Some(String::from_utf8(bytes)?));
        }
    }
}

async fn read_bounded_line<R>(reader: &mut R, max: usize) -> Result<Option<String>>
where
    R: AsyncBufRead + Unpin,
{
    let mut bytes = Vec::with_capacity(max.min(4096));
    loop {
        let available = reader.fill_buf().await?;
        if available.is_empty() {
            return if bytes.is_empty() {
                Ok(None)
            } else {
                bail!("truncated IPC line")
            };
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let consumed = newline.map_or(available.len(), |index| index + 1);
        if bytes.len().saturating_add(consumed) > max {
            bail!("IPC line exceeded {max} bytes");
        }
        bytes.extend_from_slice(&available[..consumed]);
        reader.consume(consumed);
        if newline.is_some() {
            return Ok(Some(String::from_utf8(bytes)?));
        }
    }
}

async fn send_ui_activity(shared: &Arc<Shared>, active: bool) {
    let action = json!({
        "id": format!("_agent-ui-{}", shared.next_session.load(Ordering::Relaxed)),
        "method": "setUiActive",
        "data": active,
    });
    if let Some(core) = shared.core.lock().await.clone() {
        let _ = core.send(action.to_string()).await;
    }
}

async fn set_status(shared: &Arc<Shared>, status: CoreStatus) {
    *shared.status.write().await = status;
    // `null` means no explicit listener decision has been observed yet, so a
    // first UI launch may still apply its auto-run preference. `false` is
    // reserved for an explicit stopListener action and must survive reattach.
    let proxy_running = if status == CoreStatus::Ready {
        shared.journal.lock().await.listener_running()
    } else {
        None
    };
    let envelope = json!({
        "_agent": {
            "type": "coreState",
            "protocol": PROTOCOL_VERSION,
            "coreState": status.as_str(),
            "generation": shared.generation.load(Ordering::Acquire),
            "proxyRunning": proxy_running,
            "privilegedBackend": shared.privileged_backend,
            "strictPolicy": strict_policy_json(shared).await,
        }
    });
    forward_to_ui(shared, envelope.to_string()).await;
}

async fn ready_envelope(shared: &Arc<Shared>) -> String {
    let status = *shared.status.read().await;
    let proxy_running = if status == CoreStatus::Ready {
        shared.journal.lock().await.listener_running()
    } else {
        None
    };
    json!({
        "_agent": {
            "type": "ready",
            "protocol": PROTOCOL_VERSION,
            "coreState": status.as_str(),
            "generation": shared.generation.load(Ordering::Acquire),
            "proxyRunning": proxy_running,
            "privilegedBackend": shared.privileged_backend,
            "strictPolicy": strict_policy_json(shared).await,
        }
    })
    .to_string()
}

async fn strict_policy_json(shared: &Arc<Shared>) -> Value {
    // StrictPolicyStatus contains only infallible serde primitives. The
    // explicit match keeps this boundary defensive if that ever changes.
    let mut value = serde_json::to_value(&*shared.strict_policy.read().await).unwrap_or_else(|_| {
        json!({
            "state": "blocking",
            "generation": 0,
            "failureReason": "invalidPolicy",
        })
    });
    #[cfg(windows)]
    if let Some(runtime) = shared.strict_runtime.lock().await.clone() {
        let diagnostics = runtime.retry.lock().await.diagnostics();
        value["recovery"] = json!({
            "attempts": diagnostics.attempts,
            "exhausted": diagnostics.exhausted,
            "nextDelayMs": diagnostics.next_delay.map(|delay| delay.as_millis() as u64),
        });
    }
    value
}

async fn forward_to_ui(shared: &Arc<Shared>, line: String) {
    let output = shared
        .ui
        .lock()
        .await
        .as_ref()
        .map(|session| session.output.clone());
    if let Some(output) = output {
        if is_unsolicited_message(&line) {
            // Connection/log/traffic streams may be much faster than a hidden
            // or stalled UI. Dropping stale stream samples keeps Agent memory
            // bounded without sacrificing request/response correctness.
            let _ = output.try_send(UiOutput::new(line));
        } else {
            // Responses and lifecycle state must apply backpressure; dropping
            // one would strand a Flutter completer until its timeout.
            let _ = output.send(UiOutput::new(line)).await;
        }
    }
}

fn is_unsolicited_message(line: &str) -> bool {
    serde_json::from_str::<Value>(line)
        .ok()
        .and_then(|value| value.get("method")?.as_str().map(str::to_owned))
        .is_some_and(|method| method == "message")
}

fn crash_delay(attempt: u32) -> Duration {
    Duration::from_secs(1_u64 << attempt.saturating_sub(1).min(4))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session_fixture() -> Arc<Shared> {
        let (supervisor, _) = mpsc::channel(1);
        Arc::new(Shared {
            ui: Mutex::new(None),
            core: Mutex::new(None),
            journal: Mutex::new(ReplayJournal::default()),
            #[cfg(target_os = "macos")]
            mac_strict_replay: Mutex::new(crate::mac_strict_replay::MacStrictReplay::default()),
            #[cfg(target_os = "macos")]
            mac_strict_account: "test-only-no-keychain-access".to_owned(),
            logger: AgentLogger::new(&std::env::temp_dir().join("flclash-agent-session-tests")),
            status: RwLock::new(CoreStatus::Ready),
            strict_policy: RwLock::new(StrictPolicyStatus::disabled()),
            generation: AtomicU64::new(7),
            next_session: AtomicU64::new(1),
            shutting_down: AtomicBool::new(false),
            shutdown: Notify::new(),
            supervisor,
            privileged_backend: false,
            helper_port: None,
            helper_token: None,
            home_dir: PathBuf::new(),
            strict_blocks: Mutex::new(HashSet::new()),
            #[cfg(windows)]
            strict_runtime: Mutex::new(None),
            #[cfg(windows)]
            strict_store: Mutex::new(None),
        })
    }

    async fn attach_ui(shared: Arc<Shared>) -> (BufReader<TcpStream>, tokio::task::JoinHandle<Result<()>>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let mut client = TcpStream::connect(listener.local_addr().unwrap()).await.unwrap();
        let (server, _) = listener.accept().await.unwrap();
        let task = tokio::spawn(handle_ui(server, "test-token".to_owned(), shared));
        client.write_all(b"{\"token\":\"test-token\",\"protocol\":1}\n").await.unwrap();
        let mut reader = BufReader::new(client);
        let mut ready = String::new();
        timeout(Duration::from_secs(3), reader.read_line(&mut ready)).await.unwrap().unwrap();
        let event: Value = serde_json::from_str(&ready).unwrap();
        assert_eq!(event["_agent"]["type"], "ready");
        (reader, task)
    }

    #[tokio::test]
    async fn ui_error_cleanup_allows_reattach_without_core_restart() {
        for payload in ["not-json\n", "{\"id\":\"broken\"}\n", "truncated"] {
            let shared = session_fixture();
            let (mut client, task) = attach_ui(shared.clone()).await;
            client.get_mut().write_all(payload.as_bytes()).await.unwrap();
            client.get_mut().shutdown().await.unwrap();
            assert!(timeout(Duration::from_secs(3), task).await.unwrap().unwrap().is_err());
            assert!(shared.ui.lock().await.is_none(), "failed session retained");
            let (mut reconnected, task) = attach_ui(shared.clone()).await;
            assert_eq!(shared.generation.load(Ordering::Acquire), 7);
            reconnected.get_mut().shutdown().await.unwrap();
            assert!(timeout(Duration::from_secs(3), task).await.unwrap().unwrap().is_ok());
            assert!(shared.ui.lock().await.is_none());
        }
    }

    #[tokio::test]
    async fn bounded_reader_rejects_oversized_and_truncated_lines() {
        let mut oversized = BufReader::new(&b"12345\n"[..]);
        assert!(read_bounded_line(&mut oversized, 4).await.is_err());
        let mut truncated = BufReader::new(&b"1234"[..]);
        assert!(read_bounded_line(&mut truncated, 8).await.is_err());
    }

    #[test]
    fn crash_backoff_is_bounded() {
        assert_eq!(crash_delay(1), Duration::from_secs(1));
        assert_eq!(crash_delay(5), Duration::from_secs(16));
        assert_eq!(crash_delay(50), Duration::from_secs(16));
    }

    #[test]
    fn only_unsolicited_core_streams_are_lossy() {
        assert!(is_unsolicited_message(
            r#"{"method":"message","data":{},"code":0}"#
        ));
        assert!(!is_unsolicited_message(
            r#"{"id":"request","method":"getConnections","data":{},"code":0}"#
        ));
        assert!(!is_unsolicited_message(
            r#"{"_agent":{"type":"coreState","coreState":"ready"}}"#
        ));
        assert!(!is_unsolicited_message("not-json"));
    }
}
