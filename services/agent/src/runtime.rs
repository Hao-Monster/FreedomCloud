use std::collections::HashMap;
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
use tokio::time::{timeout, timeout_at, Instant};

use crate::config::AgentConfig;
use crate::endpoint::{load_or_create_helper_token, random_token, EndpointGuard};
use crate::journal::ReplayJournal;
use crate::logging::AgentLogger;
use crate::protocol::{
    authenticate, is_reserved_core_action, parse_control, AgentCommand, MAX_AUTH_LINE_BYTES,
    MAX_MESSAGE_LINE_BYTES, PROTOCOL_VERSION,
};
use crate::strict::{StrictController, StrictReason};

const CHANNEL_CAPACITY: usize = 256;
const CORE_CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const CORE_REPLAY_TIMEOUT: Duration = Duration::from_secs(30);
const HELPER_RESPONSE_LIMIT: usize = 64 * 1024;
const MAX_CRASH_RETRIES: u32 = 5;
const MAX_PENDING_INTERNAL_CORE_REQUESTS: usize = 32;
const INTERNAL_CORE_RESPONSE_TIMEOUT: Duration = Duration::from_secs(2);

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

#[derive(Clone)]
struct CoreLink {
    input: mpsc::Sender<String>,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<String>>>>,
}

impl CoreLink {
    fn new(input: mpsc::Sender<String>) -> Self {
        Self {
            input,
            pending: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    async fn send(&self, line: String) -> Result<()> {
        self.input
            .send(line)
            .await
            .map_err(|_| anyhow!("Core command channel is closed"))
    }

    async fn request(&self, id: &str, line: &str, deadline: Duration) -> Result<String> {
        if id.len() > 128
            || !id.starts_with("_agent-")
            || !id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
        {
            bail!("internal Core request ID is invalid");
        }
        if line.is_empty() || line.len() > MAX_MESSAGE_LINE_BYTES {
            bail!("internal Core request size is invalid");
        }
        let envelope: Value = serde_json::from_str(line).context("invalid internal Core action")?;
        if envelope.get("id").and_then(Value::as_str) != Some(id) {
            bail!("internal Core action ID does not match its correlation ID");
        }

        let (response_tx, response_rx) = oneshot::channel();
        {
            let mut pending = self.pending.lock().await;
            if pending.len() >= MAX_PENDING_INTERNAL_CORE_REQUESTS {
                bail!("too many internal Core requests are pending");
            }
            if pending.contains_key(id) {
                bail!("internal Core request ID is already pending");
            }
            pending.insert(id.to_owned(), response_tx);
        }
        let expires = Instant::now() + deadline;
        match timeout_at(expires, self.input.send(line.to_owned())).await {
            Ok(Ok(())) => {}
            Ok(Err(_)) => {
                self.pending.lock().await.remove(id);
                bail!("Core command channel is closed");
            }
            Err(_) => {
                self.pending.lock().await.remove(id);
                bail!("internal Core request enqueue timed out");
            }
        }

        match timeout_at(expires, response_rx).await {
            Ok(Ok(response)) => Ok(response),
            Ok(Err(_)) => {
                self.pending.lock().await.remove(id);
                bail!("Core disconnected before the internal response")
            }
            Err(_) => {
                self.pending.lock().await.remove(id);
                bail!("internal Core request timed out")
            }
        }
    }

    async fn route_response(&self, line: &str) -> bool {
        // Core uses compact JSON. This cheap prefix avoids parsing high-rate
        // unsolicited connection/log/traffic messages in the internal RPC path.
        if !line.contains(r#""id":"_agent-"#) {
            return false;
        }
        let Some(id) = serde_json::from_str::<Value>(line)
            .ok()
            .and_then(|value| value.get("id")?.as_str().map(str::to_owned))
        else {
            return true;
        };
        if !id.starts_with("_agent-") {
            return false;
        }
        let response = self.pending.lock().await.remove(&id);
        if let Some(response) = response {
            let _ = response.send(line.to_owned());
        }
        // A timed-out Agent-owned response is still private and must never be
        // forwarded to the UI merely because its waiter has already gone away.
        true
    }

    async fn cancel_pending(&self) {
        self.pending.lock().await.clear();
    }

    #[cfg(test)]
    async fn pending_len(&self) -> usize {
        self.pending.lock().await.len()
    }
}

struct Shared {
    ui: Mutex<Option<UiSession>>,
    core: Mutex<Option<CoreLink>>,
    journal: Mutex<ReplayJournal>,
    logger: Arc<AgentLogger>,
    status: RwLock<CoreStatus>,
    strict: RwLock<StrictController>,
    generation: AtomicU64,
    next_session: AtomicU64,
    next_internal: AtomicU64,
    shutting_down: AtomicBool,
    shutdown: Notify,
    supervisor: mpsc::Sender<SupervisorCommand>,
    privileged_backend: bool,
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
    let (supervisor_tx, supervisor_rx) = mpsc::channel(16);
    let shared = Arc::new(Shared {
        ui: Mutex::new(None),
        core: Mutex::new(None),
        journal: Mutex::new(ReplayJournal::default()),
        logger: logger.clone(),
        status: RwLock::new(CoreStatus::Starting),
        strict: RwLock::new(StrictController::default()),
        generation: AtomicU64::new(0),
        next_session: AtomicU64::new(1),
        next_internal: AtomicU64::new(1),
        shutting_down: AtomicBool::new(false),
        shutdown: Notify::new(),
        supervisor: supervisor_tx,
        privileged_backend: config.use_helper,
    });

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
            let (ok, state) = match control.command {
                AgentCommand::Status => (true, *shared.status.read().await),
                AgentCommand::RestartCore => {
                    issue_supervisor_command(&shared, SupervisorCommandKind::Restart).await
                }
                AgentCommand::StopCore => {
                    issue_supervisor_command(&shared, SupervisorCommandKind::Stop).await
                }
                AgentCommand::ShutdownAgent => {
                    issue_supervisor_command(&shared, SupervisorCommandKind::Shutdown).await
                }
            };
            let response = json!({
                "_agent": {
                    "type": "commandResult",
                    "id": control.id,
                    "ok": ok,
                    "coreState": state.as_str(),
                    "generation": shared.generation.load(Ordering::Acquire),
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
        if is_reserved_core_action(&action) {
            let response = json!({
                "_agent": {
                    "type": "reservedCoreAction",
                    "id": action["id"],
                }
            });
            output_tx.send(UiOutput::new(response.to_string())).await?;
            continue;
        }
        let core = shared.core.lock().await.clone();
        if let Some(core) = core {
            shared.journal.lock().await.stage(line);
            if core.send(line.to_owned()).await.is_err() {
                shared.journal.lock().await.discard_pending();
                return Err(anyhow!("Core command channel is closed"));
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
    Ok(())
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
        let core_link = CoreLink::new(core_tx);
        *shared.core.lock().await = Some(core_link.clone());
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
                            if core_link.route_response(&line).await {
                                continue;
                            }
                            shared.journal.lock().await.commit_response(&line);
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
        core_link.cancel_pending().await;
        shared.journal.lock().await.discard_pending();
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
    command
        .arg(core_port.to_string())
        .arg(token)
        .env("SAFE_PATHS", &config.home)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut process = command.spawn().context("unable to spawn local Core")?;
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
    if !body.is_empty() {
        bail!("Helper rejected Core operation: {body}");
    }
    Ok(())
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
        let Some(line) = read_bounded_line(&mut reader, MAX_AUTH_LINE_BYTES).await? else {
            continue;
        };
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
        if valid {
            return Ok(reader.into_inner());
        }
    }
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
    let sequence = shared.next_internal.fetch_add(1, Ordering::Relaxed);
    let id = format!("_agent-internal-ui-{sequence}");
    let action = json!({
        "id": id,
        "method": "setUiActive",
        "data": active,
    });
    if let Some(core) = shared.core.lock().await.clone() {
        tokio::spawn(async move {
            let _ = core
                .request(&id, &action.to_string(), INTERNAL_CORE_RESPONSE_TIMEOUT)
                .await;
        });
    }
}

async fn set_status(shared: &Arc<Shared>, status: CoreStatus) {
    *shared.status.write().await = status;
    if status != CoreStatus::Ready {
        shared
            .strict
            .write()
            .await
            .backend_lost(StrictReason::CoreUnavailable);
    }
    // `null` means no explicit listener decision has been observed yet, so a
    // first UI launch may still apply its auto-run preference. `false` is
    // reserved for an explicit stopListener action and must survive reattach.
    let proxy_running = if status == CoreStatus::Ready {
        shared.journal.lock().await.listener_running()
    } else {
        None
    };
    let strict = shared.strict.read().await.status();
    let envelope = json!({
        "_agent": {
            "type": "coreState",
            "protocol": PROTOCOL_VERSION,
            "coreState": status.as_str(),
            "generation": shared.generation.load(Ordering::Acquire),
            "proxyRunning": proxy_running,
            "privilegedBackend": shared.privileged_backend,
            "strictState": strict.state.as_str(),
            "strictReason": strict.reason.as_str(),
            "strictRevision": strict.revision,
            "strictFilterGeneration": strict.filter_generation,
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
    let strict = shared.strict.read().await.status();
    json!({
        "_agent": {
            "type": "ready",
            "protocol": PROTOCOL_VERSION,
            "coreState": status.as_str(),
            "generation": shared.generation.load(Ordering::Acquire),
            "proxyRunning": proxy_running,
            "privilegedBackend": shared.privileged_backend,
            "strictState": strict.state.as_str(),
            "strictReason": strict.reason.as_str(),
            "strictRevision": strict.revision,
            "strictFilterGeneration": strict.filter_generation,
        }
    })
    .to_string()
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

    #[tokio::test]
    async fn agent_owned_core_responses_are_correlated_and_not_forwarded() {
        let (core_tx, mut core_rx) = mpsc::channel(4);
        let link = CoreLink::new(core_tx);
        let waiting_link = link.clone();
        let waiter = tokio::spawn(async move {
            waiting_link
                .request(
                    "_agent-internal-test-1",
                    r#"{"id":"_agent-internal-test-1","method":"setUiActive","data":true}"#,
                    Duration::from_secs(1),
                )
                .await
        });

        assert_eq!(
            core_rx.recv().await.unwrap(),
            r#"{"id":"_agent-internal-test-1","method":"setUiActive","data":true}"#
        );
        let response =
            r#"{"id":"_agent-internal-test-1","method":"setUiActive","code":0,"data":true}"#;
        assert!(link.route_response(response).await);
        assert_eq!(waiter.await.unwrap().unwrap(), response);
        assert!(link.route_response(response).await);
        assert!(
            !link
                .route_response(r#"{"id":"ui-1","method":"getConfig","code":0,"data":{}}"#)
                .await
        );
    }

    #[tokio::test]
    async fn timed_out_internal_core_requests_release_the_pending_slot() {
        let (core_tx, mut core_rx) = mpsc::channel(1);
        let link = CoreLink::new(core_tx);
        let request = link.request(
            "_agent-internal-timeout-1",
            r#"{"id":"_agent-internal-timeout-1","method":"setUiActive","data":true}"#,
            Duration::from_millis(1),
        );
        tokio::pin!(request);
        tokio::select! {
            result = &mut request => assert!(result.is_err()),
            line = core_rx.recv() => {
                assert!(line.is_some());
                assert!(request.await.is_err());
            }
        }
        assert_eq!(link.pending_len().await, 0);
    }

    #[tokio::test]
    async fn saturated_internal_core_queue_obeys_the_total_deadline() {
        let (core_tx, _core_rx) = mpsc::channel(1);
        let link = CoreLink::new(core_tx.clone());
        core_tx.send("occupied".into()).await.unwrap();

        assert!(link
            .request(
                "_agent-internal-saturated-1",
                r#"{"id":"_agent-internal-saturated-1","method":"setUiActive","data":true}"#,
                Duration::from_millis(1),
            )
            .await
            .is_err());
        assert_eq!(link.pending_len().await, 0);
    }
}
