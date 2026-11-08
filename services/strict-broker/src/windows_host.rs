use std::collections::VecDeque;
use std::ffi::c_void;
use std::fs;
use std::os::windows::fs::MetadataExt;
use std::path::{Component, Path, PathBuf};
use std::ptr::null_mut;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{
    BrokerActivationErrorCode, BrokerActivationResponse, BrokerCommand, BrokerErrorCode,
    BrokerResponse, WINDOWS_STRICT_BROKER_ACTIVATION_PIPE_NAME,
};
use windows_sys::Win32::System::Com::CoTaskMemFree;
use windows_sys::Win32::UI::Shell::{FOLDERID_ProgramData, SHGetKnownFolderPath};

use crate::logging::StrictBrokerLogger;
use crate::windows_pipe::is_connect_deadline;
use crate::windows_tcp_runtime::WindowsTcpForwardingHealth;
use crate::{
    run_windows_scm_service, verify_windows_packaged_agent_image,
    verify_windows_packaged_core_image, AuthorizedBrokerRequest, BrokerDispatcher, BrokerEngine,
    BrokerSessionRegistry, BrokerSessionResource, FileRecoveryStore, ForwardingHealthProbe,
    PlannedWfpBackend, StrictPackageManifest, WfpPolicyPlan, WindowsAgentImageTrustLease,
    WindowsBrokerActivationAttempt, WindowsBrokerActivationPipeInstance, WindowsBrokerPipeSession,
    WindowsIdentityVerifier, WindowsPipeDeadlines, WindowsPipeShutdown, WindowsScmContext,
    WindowsSharedIoctlDriverChannel, WindowsWfpControl, WindowsWfpEngineStore,
};

const BROKER_SERVICE_NAME: &str = "FlClashStrictBroker";
const BROKER_FILE_NAME: &str = "FlClashStrictBroker.exe";
const DRIVER_FILE_NAME: &str = "FlClashStrictCallout.sys";
const AGENT_FILE_NAME: &str = "FlClashAgent.exe";
const CORE_FILE_NAME: &str = "FlClashCore.exe";
const RECOVERY_DIRECTORY_NAME: &str = "FlClashX.StrictBroker";
const MAX_TRUSTED_PATH_UNITS: usize = 1024;
const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
const SESSION_WORKERS: usize = 4;
const ENGINE_QUEUE_CAPACITY: usize = SESSION_WORKERS;
const ENGINE_POLL_INTERVAL: Duration = Duration::from_millis(25);
const ENGINE_STARTUP_DEADLINE: Duration = Duration::from_secs(30);
const ENGINE_REQUEST_DEADLINE: Duration = Duration::from_secs(20);

type ProductionControl = WindowsWfpControl<WindowsWfpEngineStore, WindowsSharedIoctlDriverChannel>;
type ProductionBackend = PlannedWfpBackend<ProductionControl>;
type ProductionDispatcher = BrokerDispatcher<
    ProductionBackend,
    FileRecoveryStore,
    WindowsIdentityVerifier,
    WindowsTcpForwardingHealth,
>;

struct EngineDispatch {
    request: AuthorizedBrokerRequest,
    response: SyncSender<BrokerResponse>,
}

enum EngineControl {
    ForceFailClosed(SyncSender<Result<()>>),
    Shutdown(SyncSender<Result<()>>),
}

struct EngineInboxState {
    dispatch: VecDeque<EngineDispatch>,
    dispatch_capacity: usize,
    dispatch_closed: bool,
    control: VecDeque<EngineControl>,
    control_capacity: usize,
    control_closed: bool,
}

struct EngineInboxShared {
    state: Mutex<EngineInboxState>,
    wakeup: Condvar,
    dispatch_senders: AtomicUsize,
    control_senders: AtomicUsize,
    receiver_alive: std::sync::atomic::AtomicBool,
}

struct EngineDispatchSender {
    shared: Arc<EngineInboxShared>,
}

impl Clone for EngineDispatchSender {
    fn clone(&self) -> Self {
        self.shared.dispatch_senders.fetch_add(1, Ordering::Relaxed);
        Self {
            shared: self.shared.clone(),
        }
    }
}

impl Drop for EngineDispatchSender {
    fn drop(&mut self) {
        if self.shared.dispatch_senders.fetch_sub(1, Ordering::AcqRel) == 1 {
            if let Ok(mut state) = self.shared.state.lock() {
                state.dispatch_closed = true;
                self.shared.wakeup.notify_one();
            }
        }
    }
}

impl EngineDispatchSender {
    fn try_send(&self, item: EngineDispatch) -> std::result::Result<(), TrySendError<EngineDispatch>> {
        if !self.shared.receiver_alive.load(Ordering::Acquire) {
            return Err(TrySendError::Disconnected(item));
        }
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if !self.shared.receiver_alive.load(Ordering::Acquire) {
            return Err(TrySendError::Disconnected(item));
        }
        if state.dispatch.len() >= state.dispatch_capacity {
            return Err(TrySendError::Full(item));
        }
        state.dispatch.push_back(item);
        drop(state);
        self.shared.wakeup.notify_one();
        Ok(())
    }

    #[cfg(test)]
    fn send(&self, item: EngineDispatch) -> std::result::Result<(), &'static str> {
        self.try_send(item).map_err(|_| "dispatch queue closed or full")
    }
}

struct EngineControlSender {
    shared: Arc<EngineInboxShared>,
}

impl Clone for EngineControlSender {
    fn clone(&self) -> Self {
        self.shared.control_senders.fetch_add(1, Ordering::Relaxed);
        Self {
            shared: self.shared.clone(),
        }
    }
}

impl Drop for EngineControlSender {
    fn drop(&mut self) {
        if self.shared.control_senders.fetch_sub(1, Ordering::AcqRel) == 1 {
            if let Ok(mut state) = self.shared.state.lock() {
                state.control_closed = true;
                self.shared.wakeup.notify_one();
            }
        }
    }
}

impl EngineControlSender {
    fn try_send(&self, item: EngineControl) -> std::result::Result<(), TrySendError<EngineControl>> {
        if !self.shared.receiver_alive.load(Ordering::Acquire) {
            return Err(TrySendError::Disconnected(item));
        }
        let mut state = self
            .shared
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if !self.shared.receiver_alive.load(Ordering::Acquire) {
            return Err(TrySendError::Disconnected(item));
        }
        if state.control.len() >= state.control_capacity {
            return Err(TrySendError::Full(item));
        }
        state.control.push_back(item);
        drop(state);
        self.shared.wakeup.notify_one();
        Ok(())
    }

    #[cfg(test)]
    fn send(&self, item: EngineControl) -> std::result::Result<(), &'static str> {
        self.try_send(item).map_err(|_| "control queue closed or full")
    }
}

struct EngineInboxReceiver {
    shared: Arc<EngineInboxShared>,
}

impl Drop for EngineInboxReceiver {
    fn drop(&mut self) {
        self.shared.receiver_alive.store(false, Ordering::Release);
    }
}

fn engine_actor_channels(
    dispatch_capacity: usize,
) -> (EngineDispatchSender, EngineControlSender, EngineInboxReceiver) {
    let shared = Arc::new(EngineInboxShared {
        state: Mutex::new(EngineInboxState {
            dispatch: VecDeque::with_capacity(dispatch_capacity),
            dispatch_capacity,
            dispatch_closed: false,
            control: VecDeque::with_capacity(1),
            control_capacity: 1,
            control_closed: false,
        }),
        wakeup: Condvar::new(),
        dispatch_senders: AtomicUsize::new(1),
        control_senders: AtomicUsize::new(1),
        receiver_alive: std::sync::atomic::AtomicBool::new(true),
    });
    (
        EngineDispatchSender {
            shared: shared.clone(),
        },
        EngineControlSender {
            shared: shared.clone(),
        },
        EngineInboxReceiver { shared },
    )
}

#[derive(Clone)]
struct EngineActorClient {
    dispatch: EngineDispatchSender,
    control: EngineControlSender,
    logger: Arc<StrictBrokerLogger>,
}

struct EngineActor {
    client: EngineActorClient,
    worker: Option<JoinHandle<Result<()>>>,
}

trait EngineRuntime {
    fn dispatch(&mut self, request: AuthorizedBrokerRequest) -> BrokerResponse;
    fn verify_health(&mut self) -> Result<()>;
    fn force_fail_closed(&mut self) -> Result<()>;
    fn has_active_health_supervision(&self) -> bool {
        true
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowsStrictBrokerPaths {
    broker: PathBuf,
    driver: PathBuf,
    agent: PathBuf,
    core: PathBuf,
    recovery: PathBuf,
}

impl WindowsStrictBrokerPaths {
    pub fn discover() -> Result<Self> {
        let broker = std::env::current_exe().context("resolve strict Broker executable path")?;
        let program_data = program_data_path()?;
        let paths = Self::from_trusted_roots(broker, program_data)?;
        verify_plain_file(&paths.broker, "strict Broker executable")?;
        verify_plain_directory(
            paths
                .broker
                .parent()
                .ok_or_else(|| anyhow::anyhow!("strict Broker install directory is missing"))?,
            "strict Broker install directory",
        )?;
        verify_plain_directory(
            paths
                .recovery
                .parent()
                .ok_or_else(|| anyhow::anyhow!("strict Broker ProgramData root is missing"))?,
            "strict Broker ProgramData root",
        )?;
        Ok(paths)
    }

    fn from_trusted_roots(
        broker: impl Into<PathBuf>,
        program_data: impl Into<PathBuf>,
    ) -> Result<Self> {
        let broker = broker.into();
        let program_data = program_data.into();
        validate_trusted_path(&broker, "strict Broker executable")?;
        validate_trusted_path(&program_data, "strict Broker ProgramData root")?;
        if broker
            .file_name()
            .and_then(|name| name.to_str())
            .is_none_or(|name| !name.eq_ignore_ascii_case(BROKER_FILE_NAME))
        {
            bail!("strict Broker executable has an unexpected package name");
        }
        let install = broker
            .parent()
            .ok_or_else(|| anyhow::anyhow!("strict Broker install directory is missing"))?;
        let driver = install.join(DRIVER_FILE_NAME);
        let agent = install.join(AGENT_FILE_NAME);
        let core = install.join(CORE_FILE_NAME);
        let recovery = program_data.join(RECOVERY_DIRECTORY_NAME);
        for (path, label) in [
            (&driver, "strict driver package path"),
            (&agent, "strict Agent package path"),
            (&core, "strict Core package path"),
            (&recovery, "strict Broker recovery path"),
        ] {
            validate_trusted_path(path, label)?;
        }
        Ok(Self {
            broker,
            driver,
            agent,
            core,
            recovery,
        })
    }

    pub fn broker(&self) -> &Path {
        &self.broker
    }

    pub fn driver(&self) -> &Path {
        &self.driver
    }

    pub fn agent(&self) -> &Path {
        &self.agent
    }

    pub fn core(&self) -> &Path {
        &self.core
    }

    pub fn recovery(&self) -> &Path {
        &self.recovery
    }
}

pub fn run_windows_strict_broker_service() -> Result<()> {
    let logger = StrictBrokerLogger::new_default();
    logger.log("SCM dispatcher starting");
    run_windows_scm_service(BROKER_SERVICE_NAME, move |context| {
        logger.log("SCM service callback entered");
        let paths = match WindowsStrictBrokerPaths::discover() {
            Ok(paths) => paths,
            Err(error) => {
                logger.log(format!("discover trusted package paths failed: {error:#}"));
                return Err(error);
            }
        };
        let package = match StrictPackageManifest::embedded() {
            Ok(package) => package,
            Err(error) => {
                logger.log(format!("load embedded package manifest failed: {error:#}"));
                return Err(error);
            }
        };
        run_service(context, paths, package, logger.clone())
    })
}

fn run_service(
    context: WindowsScmContext,
    paths: WindowsStrictBrokerPaths,
    package: StrictPackageManifest,
    logger: Arc<StrictBrokerLogger>,
) -> Result<()> {
    logger.log("strict Broker service initializing");
    let activation_deadlines = WindowsPipeDeadlines::new(
        Duration::from_secs(1),
        Duration::from_secs(2),
        Duration::from_secs(2),
    )?;
    let session_deadlines = WindowsPipeDeadlines::new(
        Duration::from_secs(1),
        Duration::from_secs(5),
        Duration::from_secs(5),
    )?;
    let activation = WindowsBrokerActivationPipeInstance::create(
        WINDOWS_STRICT_BROKER_ACTIVATION_PIPE_NAME,
        activation_deadlines,
    )?;
    let agent_image = verify_windows_packaged_agent_image(paths.agent(), &package)
        .context("open and attest packaged strict Agent")?;
    let _core_image = verify_windows_packaged_core_image(paths.core(), &package)
        .context("open and attest packaged strict Core")?;
    let mut engine = EngineActor::start(paths.clone(), package.clone(), logger.clone())?;
    if let Err(error) = context.report_running() {
        logger.log(format!("report service running failed: {error:#}"));
        return combine_service_results(Err(error), engine.shutdown());
    }
    logger.log("strict Broker service running");
    let service = run_activation_loop(
        activation,
        context.shutdown(),
        &agent_image,
        session_deadlines,
        engine.client(),
        logger.clone(),
    );
    let engine_shutdown = engine.shutdown();
    let result = combine_service_results(service, engine_shutdown);
    match &result {
        Ok(()) => logger.log("strict Broker service stopped cleanly"),
        Err(error) => logger.log(format!(
            "strict Broker service stopped with error: {error:#}"
        )),
    }
    result
}

fn build_dispatcher(
    paths: &WindowsStrictBrokerPaths,
    package: &StrictPackageManifest,
) -> Result<ProductionDispatcher> {
    // No persistent WFP object is touched before the recovery location proves
    // that the installer established its exact protected ACL.
    let store = FileRecoveryStore::from_presecured_directory(paths.recovery())?;
    let driver = WindowsSharedIoctlDriverChannel::open(paths.driver(), package)
        .context("open and attest strict callout driver")?;
    let mut filters = WindowsWfpEngineStore::open(
        WfpPolicyPlan::canonical_provider_key(),
        WfpPolicyPlan::canonical_sublayer_key(),
    )?;
    filters
        .provision_management_objects()
        .context("provision strict WFP management objects")?;
    filters
        .verify_management_objects()
        .context("attest strict WFP management objects")?;
    let control = WindowsWfpControl::new(filters, driver.clone());
    let backend = PlannedWfpBackend::new(control);
    let mut engine = BrokerEngine::new(backend, store, WindowsIdentityVerifier);
    engine
        .recover()
        .context("recover strict policy into a fail-closed state at service startup")?;
    Ok(BrokerDispatcher::new(
        engine,
        WindowsTcpForwardingHealth::new(driver, paths.core(), package.clone()),
    ))
}

fn run_activation_loop(
    activation: WindowsBrokerActivationPipeInstance,
    shutdown: WindowsPipeShutdown,
    agent_image: &WindowsAgentImageTrustLease,
    session_deadlines: WindowsPipeDeadlines,
    engine: EngineActorClient,
    logger: Arc<StrictBrokerLogger>,
) -> Result<()> {
    let mut sessions = BrokerSessionRegistry::<WindowsBrokerPipeSession>::default();
    while !shutdown.is_requested() {
        sessions.reap_exited(|| engine.force_fail_closed())?;
        let attempt = match activation.connect_and_classify_with_image(agent_image) {
            Ok(attempt) => attempt,
            Err(error) if is_connect_deadline(&error) => continue,
            Err(error) => {
                logger.log(format!("activation pipe classification failed: {error:#}"));
                activation.disconnect_for_reuse();
                continue;
            }
        };

        let (response, installed) = match attempt {
            WindowsBrokerActivationAttempt::Rejected(response) => {
                logger.log("activation rejected");
                (response, false)
            }
            WindowsBrokerActivationAttempt::Verified(verified) => {
                logger.log("activation verified");
                let request_id = verified.request.request_id.clone();
                let handler_engine = engine.clone();
                match WindowsBrokerPipeSession::start(
                    verified,
                    session_deadlines,
                    SESSION_WORKERS,
                    move |request| handler_engine.dispatch(request),
                ) {
                    Ok(candidate) => {
                        let response = candidate.activation_response()?;
                        let active_is_live = sessions
                            .active()
                            .map(BrokerSessionResource::is_alive)
                            .transpose()?
                            .unwrap_or(false);
                        if active_is_live {
                            logger.log("activation rejected because another session is active");
                            drop(candidate);
                            (
                                BrokerActivationResponse::error(
                                    request_id,
                                    BrokerActivationErrorCode::Busy,
                                )?,
                                false,
                            )
                        } else if sessions
                            .activate(candidate, || engine.force_fail_closed())
                            .is_ok()
                        {
                            logger.log("activation session installed");
                            (response, true)
                        } else {
                            logger.log("activation session install failed");
                            (
                                BrokerActivationResponse::error(
                                    request_id,
                                    BrokerActivationErrorCode::Internal,
                                )?,
                                false,
                            )
                        }
                    }
                    Err(error) => {
                        logger.log(format!("activation session start failed: {error:#}"));
                        (
                            BrokerActivationResponse::error(
                                request_id,
                                BrokerActivationErrorCode::Internal,
                            )?,
                            false,
                        )
                    }
                }
            }
        };

        let write_result = activation.write_response(&response);
        activation.disconnect_for_reuse();
        if installed && write_result.is_err() {
            logger.log("activation response write failed; forcing fail-closed");
            sessions.shutdown(|| engine.force_fail_closed())?;
        }
    }
    logger.log("activation loop observed shutdown");
    sessions.shutdown(|| engine.force_fail_closed())?;
    Ok(())
}

impl EngineRuntime for ProductionDispatcher {
    fn dispatch(&mut self, request: AuthorizedBrokerRequest) -> BrokerResponse {
        BrokerDispatcher::dispatch(self, request)
    }

    fn verify_health(&mut self) -> Result<()> {
        self.health_probe_mut().verify_active()
    }

    fn has_active_health_supervision(&self) -> bool {
        self.health_probe().is_active()
    }

    fn force_fail_closed(&mut self) -> Result<()> {
        let prepare = self.health_probe_mut().prepare_deactivation();
        let revoke = self
            .engine_mut()
            .backend_mut()
            .control_mut()
            .driver_mut()
            .revoke_endpoint_lease()
            .map(|_| ());
        let deactivate = self.health_probe_mut().deactivate();
        let block = self.engine_mut().force_blocking_if_active().map(|_| ());
        combine_fail_closed_results(prepare, revoke, deactivate, block)
    }
}

fn combine_fail_closed_results(
    prepare: Result<()>,
    revoke: Result<()>,
    deactivate: Result<()>,
    block: Result<()>,
) -> Result<()> {
    let mut failures = Vec::new();
    if let Err(error) = prepare {
        failures.push(format!("prepare forwarding teardown failed: {error:#}"));
    }
    if let Err(error) = revoke {
        failures.push(format!("revoke endpoint lease failed: {error:#}"));
    }
    if let Err(error) = deactivate {
        failures.push(format!("deactivate forwarding runtime failed: {error:#}"));
    }
    if let Err(error) = block {
        failures.push(format!("force policy blocking failed: {error:#}"));
    }
    if failures.is_empty() {
        Ok(())
    } else {
        bail!(
            "strict fail-closed transition failed: {}",
            failures.join("; ")
        )
    }
}

impl EngineActor {
    fn start(
        paths: WindowsStrictBrokerPaths,
        package: StrictPackageManifest,
        logger: Arc<StrictBrokerLogger>,
    ) -> Result<Self> {
        let (dispatch_tx, control_tx, inbox) = engine_actor_channels(ENGINE_QUEUE_CAPACITY);
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        let worker_logger = logger.clone();
        let worker = thread::Builder::new()
            .name("flclash-strict-engine".into())
            .spawn(move || {
                let mut dispatcher = match build_dispatcher(&paths, &package) {
                    Ok(dispatcher) => dispatcher,
                    Err(error) => {
                        worker_logger
                            .log(format!("strict engine initialization failed: {error:#}"));
                        let _ = ready_tx.send(Err(anyhow::anyhow!(format!("{error:#}"))));
                        return Err(error);
                    }
                };
                worker_logger.log("strict engine initialized");
                if ready_tx.send(Ok(())).is_err() {
                    worker_logger.log("strict engine readiness receiver closed");
                    return dispatcher
                        .force_fail_closed()
                        .context("startup listener left before strict engine became ready");
                }
                let result = run_engine_actor(&mut dispatcher, inbox);
                if let Err(error) = &result {
                    worker_logger.log(format!("strict engine actor failed: {error:#}"));
                }
                result
            })
            .context("start strict Broker engine actor")?;
        match ready_rx.recv_timeout(ENGINE_STARTUP_DEADLINE) {
            Ok(Ok(())) => Ok(Self {
                client: EngineActorClient {
                    dispatch: dispatch_tx,
                    control: control_tx,
                    logger,
                },
                worker: Some(worker),
            }),
            Ok(Err(error)) => {
                logger.log(format!("strict engine startup rejected: {error:#}"));
                let _ = worker.join();
                Err(error).context("initialize strict Broker engine actor")
            }
            Err(_) => {
                logger.log("strict engine startup exceeded its deadline");
                bail!("strict Broker engine startup exceeded its deadline")
            }
        }
    }

    fn client(&self) -> EngineActorClient {
        self.client.clone()
    }

    fn shutdown(&mut self) -> Result<()> {
        self.client.logger.log("strict engine shutdown requested");
        let control = self.client.request_control(EngineControl::Shutdown)?;
        let worker = self
            .worker
            .take()
            .ok_or_else(|| anyhow::anyhow!("strict Broker engine actor is already stopped"))?;
        let joined = worker
            .join()
            .map_err(|_| anyhow::anyhow!("strict Broker engine actor panicked"))?;
        match (control, joined) {
            (Ok(()), Ok(())) => {
                self.client.logger.log("strict engine shutdown completed");
                Ok(())
            }
            (Err(control), Ok(())) => {
                self.client.logger.log(format!(
                    "strict engine control shutdown failed: {control:#}"
                ));
                Err(control)
            }
            (Ok(()), Err(worker)) => {
                self.client
                    .logger
                    .log(format!("strict engine worker shutdown failed: {worker:#}"));
                Err(worker)
            }
            (Err(control), Err(worker)) => {
                self.client.logger.log(format!(
                    "strict engine shutdown failed: control={control:#}; worker={worker:#}"
                ));
                bail!("strict engine shutdown failed: {control:#}; engine actor failed: {worker:#}")
            }
        }
    }
}

impl EngineActorClient {
    fn dispatch(&self, request: AuthorizedBrokerRequest) -> BrokerResponse {
        let request_id = request.request().request_id.clone();
        let fallback = || {
            BrokerResponse::error(&request_id, BrokerErrorCode::BackendUnavailable)
                .expect("an authenticated request ID always produces a bounded error response")
        };
        let (response_tx, response_rx) = mpsc::sync_channel(1);
        match self.dispatch.try_send(EngineDispatch {
            request,
            response: response_tx,
        }) {
            Ok(()) => match response_rx.recv_timeout(ENGINE_REQUEST_DEADLINE) {
                Ok(response) => response,
                Err(error) => {
                    self.logger
                        .log(format!("strict engine request timed out: {error}"));
                    fallback()
                }
            },
            Err(TrySendError::Full(_)) => {
                self.logger.log("strict engine request queue is full");
                fallback()
            }
            Err(TrySendError::Disconnected(_)) => {
                self.logger
                    .log("strict engine request queue is disconnected");
                fallback()
            }
        }
    }

    fn force_fail_closed(&self) -> Result<()> {
        self.request_control(EngineControl::ForceFailClosed)?
    }

    fn request_control(
        &self,
        constructor: impl FnOnce(SyncSender<Result<()>>) -> EngineControl,
    ) -> Result<Result<()>> {
        let (response_tx, response_rx) = mpsc::sync_channel(1);
        self.control
            .try_send(constructor(response_tx))
            .map_err(|error| match error {
                TrySendError::Full(_) => anyhow::anyhow!("strict engine control queue is busy"),
                TrySendError::Disconnected(_) => {
                    anyhow::anyhow!("strict engine control queue is disconnected")
                }
            })?;
        response_rx
            .recv_timeout(ENGINE_REQUEST_DEADLINE)
            .context("strict engine control response exceeded its deadline")
    }
}

enum NextEngineStep {
    Control(EngineControl),
    ControlDisconnected,
    Dispatch(EngineDispatch),
    DispatchDisconnected,
    PollHealth,
}

fn run_engine_actor<R: EngineRuntime>(
    dispatcher: &mut R,
    inbox: EngineInboxReceiver,
) -> Result<()> {
    let mut health_supervision_suspended = false;
    loop {
        if dispatcher.has_active_health_supervision() && !health_supervision_suspended {
            let health = dispatcher.verify_health();
            if let Err(health) = health {
                let cleanup = dispatcher.force_fail_closed();
                if let Err(cleanup) = cleanup {
                    return Err(anyhow::anyhow!(
                        "strict forwarding runtime became unhealthy: {health:#}; fail-closed cleanup failed: {cleanup:#}"
                    ));
                }
                // The persisted policy is now blocking and the forwarding runtime
                // is inactive. Keep the single-owner actor available for status,
                // disable and a fresh authenticated commit, but do not spin on a
                // failed runtime. A fresh authenticated commit attempt is the only
                // operation that can resume supervision.
                reject_queued_dispatches_after_health_failure(&inbox);
                health_supervision_suspended = true;
                continue;
            }
        }

        let active_poll =
            dispatcher.has_active_health_supervision() && !health_supervision_suspended;
        let next_step = {
            let mut state = inbox
                .shared
                .state
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            loop {
                if let Some(control) = state.control.pop_front() {
                    break NextEngineStep::Control(control);
                }
                if state.control_closed {
                    break NextEngineStep::ControlDisconnected;
                }
                if let Some(command) = state.dispatch.pop_front() {
                    break NextEngineStep::Dispatch(command);
                }
                if state.dispatch_closed {
                    break NextEngineStep::DispatchDisconnected;
                }
                if active_poll {
                    let (next_state, wait_result) = inbox
                        .shared
                        .wakeup
                        .wait_timeout(state, ENGINE_POLL_INTERVAL)
                        .unwrap_or_else(|poisoned| poisoned.into_inner());
                    state = next_state;
                    if wait_result.timed_out()
                        && state.control.is_empty()
                        && !state.control_closed
                        && state.dispatch.is_empty()
                        && !state.dispatch_closed
                    {
                        break NextEngineStep::PollHealth;
                    }
                } else {
                    state = inbox
                        .shared
                        .wakeup
                        .wait(state)
                        .unwrap_or_else(|poisoned| poisoned.into_inner());
                }
            }
        };

        match next_step {
            NextEngineStep::Control(EngineControl::ForceFailClosed(response)) => {
                send_result(response, dispatcher.force_fail_closed());
            }
            NextEngineStep::Control(EngineControl::Shutdown(response)) => {
                let result = dispatcher.force_fail_closed();
                let returned = result
                    .as_ref()
                    .map(|_| ())
                    .map_err(|error| anyhow::anyhow!(format!("{error:#}")));
                let _ = response.send(returned);
                return result;
            }
            NextEngineStep::ControlDisconnected => {
                return dispatcher
                    .force_fail_closed()
                    .context("strict engine control channel disconnected");
            }
            NextEngineStep::Dispatch(command) => {
                let may_resume_supervision = matches!(
                    &command.request.request().command,
                    BrokerCommand::CommitPolicy { .. }
                );
                let response = dispatcher.dispatch(command.request);
                if health_supervision_suspended && may_resume_supervision {
                    health_supervision_suspended = false;
                }
                let _ = command.response.send(response);
            }
            NextEngineStep::DispatchDisconnected => {
                return dispatcher
                    .force_fail_closed()
                    .context("strict engine dispatch channel disconnected");
            }
            NextEngineStep::PollHealth => {}
        }
    }
}

fn reject_queued_dispatches_after_health_failure(inbox: &EngineInboxReceiver) {
    // At most one pre-failure item can exist per bounded queue slot. Do not let
    // concurrent clients turn recovery cleanup into an unbounded drain loop.
    let mut drained = Vec::new();
    {
        let mut state = inbox
            .shared
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        for _ in 0..ENGINE_QUEUE_CAPACITY {
            let Some(command) = state.dispatch.pop_front() else {
                break;
            };
            drained.push(command);
        }
    }
    for command in drained {
        let request_id = command.request.request().request_id.clone();
        let response = BrokerResponse::error(&request_id, BrokerErrorCode::BackendUnavailable)
            .expect("an authenticated request ID always produces a bounded error response");
        let _ = command.response.send(response);
    }
}

fn send_result(response: SyncSender<Result<()>>, result: Result<()>) {
    let returned = result
        .as_ref()
        .map(|_| ())
        .map_err(|error| anyhow::anyhow!(format!("{error:#}")));
    let _ = response.send(returned);
}

fn combine_service_results(service: Result<()>, shutdown: Result<()>) -> Result<()> {
    match (service, shutdown) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(service), Ok(())) => Err(service),
        (Ok(()), Err(shutdown)) => Err(shutdown),
        (Err(service), Err(shutdown)) => {
            bail!("strict service loop failed: {service:#}; shutdown failed: {shutdown:#}")
        }
    }
}

fn validate_trusted_path(path: &Path, label: &str) -> Result<()> {
    let rendered = path
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("{label} is not valid Unicode"))?;
    if !path.is_absolute()
        || rendered.len() > MAX_TRUSTED_PATH_UNITS
        || rendered.contains(['\0', '\r', '\n', '/'])
        || path
            .components()
            .any(|component| matches!(component, Component::CurDir | Component::ParentDir))
    {
        bail!("{label} is invalid");
    }
    Ok(())
}

fn verify_plain_file(path: &Path, label: &str) -> Result<()> {
    let metadata = fs::symlink_metadata(path).with_context(|| format!("inspect {label}"))?;
    if !metadata.is_file() || metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
        bail!("{label} is not a plain file");
    }
    Ok(())
}

fn verify_plain_directory(path: &Path, label: &str) -> Result<()> {
    let metadata = fs::symlink_metadata(path).with_context(|| format!("inspect {label}"))?;
    if !metadata.is_dir() || metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
        bail!("{label} is not a plain directory");
    }
    Ok(())
}

fn program_data_path() -> Result<PathBuf> {
    let mut raw = null_mut();
    // SAFETY: raw is a valid output pointer and a null token requests the current process token.
    let result = unsafe { SHGetKnownFolderPath(&FOLDERID_ProgramData, 0, null_mut(), &mut raw) };
    if result < 0 || raw.is_null() {
        bail!("resolve Windows ProgramData known folder failed with HRESULT 0x{result:08x}");
    }
    let allocation = CoTaskMemPath(raw);
    let mut length = 0_usize;
    // SAFETY: SHGetKnownFolderPath returns a NUL-terminated CoTaskMem string.
    while length <= MAX_TRUSTED_PATH_UNITS && unsafe { *allocation.0.add(length) } != 0 {
        length += 1;
    }
    if length == 0 || length > MAX_TRUSTED_PATH_UNITS {
        bail!("Windows ProgramData known-folder path length is invalid");
    }
    // SAFETY: length was bounded by the terminator scan above.
    let value = unsafe { String::from_utf16(std::slice::from_raw_parts(allocation.0, length)) }
        .context("Windows ProgramData known-folder path is not UTF-16")?;
    let path = PathBuf::from(value);
    validate_trusted_path(&path, "strict Broker ProgramData root")?;
    Ok(path)
}

struct CoTaskMemPath(*mut u16);

impl Drop for CoTaskMemPath {
    fn drop(&mut self) {
        // SAFETY: the pointer was allocated by SHGetKnownFolderPath and is released once.
        unsafe { CoTaskMemFree(self.0.cast::<c_void>()) };
    }
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc::{Receiver, RecvTimeoutError};

    use flclash_strict_contract::{
        BrokerCommand, BrokerRequest, BrokerResponseBody, StrictProxyIngressSet,
        STRICT_PROTOCOL_VERSION,
    };

    use super::*;
    use crate::{BrokerAuthenticator, ClientPrincipal, ClientRole};

    struct FakeRuntime {
        events: SyncSender<&'static str>,
        first_dispatch_gate: Receiver<()>,
        dispatches: usize,
    }

    struct FailingHealthRuntime {
        events: SyncSender<&'static str>,
        fail_cleanup: bool,
    }

    impl EngineRuntime for FailingHealthRuntime {
        fn dispatch(&mut self, request: AuthorizedBrokerRequest) -> BrokerResponse {
            self.events.send("dispatch-after-recovery").unwrap();
            BrokerResponse::error(
                request.request().request_id.clone(),
                BrokerErrorCode::BackendUnavailable,
            )
            .unwrap()
        }

        fn verify_health(&mut self) -> Result<()> {
            self.events.send("health-failed").unwrap();
            bail!("injected forwarding failure")
        }

        fn force_fail_closed(&mut self) -> Result<()> {
            self.events.send("force-fail-closed").unwrap();
            if self.fail_cleanup {
                bail!("injected cleanup failure")
            }
            Ok(())
        }
    }

    impl EngineRuntime for FakeRuntime {
        fn dispatch(&mut self, request: AuthorizedBrokerRequest) -> BrokerResponse {
            self.dispatches += 1;
            self.events
                .send(if self.dispatches == 1 {
                    "dispatch-1"
                } else {
                    "dispatch-2"
                })
                .unwrap();
            if self.dispatches == 1 {
                self.first_dispatch_gate.recv().unwrap();
            }
            BrokerResponse::error(
                request.request().request_id.clone(),
                BrokerErrorCode::BackendUnavailable,
            )
            .unwrap()
        }

        fn verify_health(&mut self) -> Result<()> {
            Ok(())
        }

        fn force_fail_closed(&mut self) -> Result<()> {
            self.events.send("force-fail-closed").unwrap();
            Ok(())
        }
    }

    fn authorized_request(request_id: &str) -> AuthorizedBrokerRequest {
        authorized_command(request_id, BrokerCommand::Status {})
    }

    fn authorized_command(request_id: &str, command: BrokerCommand) -> AuthorizedBrokerRequest {
        let capability = [0x11; 32];
        let request = BrokerRequest {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: request_id.into(),
            session_capability: "11".repeat(32),
            command,
        };
        BrokerAuthenticator::new(capability)
            .authenticate(
                &ClientPrincipal::new(true, ClientRole::Owner),
                &serde_json::to_string(&request).unwrap(),
            )
            .unwrap()
    }

    #[test]
    fn fixed_package_layout_never_accepts_runtime_selected_component_paths() {
        let paths = WindowsStrictBrokerPaths::from_trusted_roots(
            r"C:\Program Files\FlClashX\FlClashStrictBroker.exe",
            r"C:\ProgramData",
        )
        .unwrap();
        assert_eq!(
            paths.driver(),
            Path::new(r"C:\Program Files\FlClashX\FlClashStrictCallout.sys")
        );
        assert_eq!(
            paths.agent(),
            Path::new(r"C:\Program Files\FlClashX\FlClashAgent.exe")
        );
        assert_eq!(
            paths.core(),
            Path::new(r"C:\Program Files\FlClashX\FlClashCore.exe")
        );
        assert_eq!(
            paths.recovery(),
            Path::new(r"C:\ProgramData\FlClashX.StrictBroker")
        );
        assert!(WindowsStrictBrokerPaths::from_trusted_roots(
            r"C:\Temp\renamed.exe",
            r"C:\ProgramData"
        )
        .is_err());
        assert!(WindowsStrictBrokerPaths::from_trusted_roots(
            r"C:\Program Files\FlClashX\FlClashStrictBroker.exe",
            r"C:\ProgramData\..\Temp"
        )
        .is_err());
    }

    #[test]
    fn fail_closed_combiner_preserves_every_cleanup_failure() {
        assert!(combine_fail_closed_results(Ok(()), Ok(()), Ok(()), Ok(())).is_ok());
        let error = combine_fail_closed_results(
            Err(anyhow::anyhow!("prepare")),
            Err(anyhow::anyhow!("lease")),
            Err(anyhow::anyhow!("runtime")),
            Err(anyhow::anyhow!("filters")),
        )
        .unwrap_err()
        .to_string();
        assert!(error.contains("prepare"));
        assert!(error.contains("lease"));
        assert!(error.contains("runtime"));
        assert!(error.contains("filters"));
    }

    #[test]
    fn engine_control_preempts_queued_data_work_after_the_current_transaction() {
        let (dispatch_tx, control_tx, inbox) = engine_actor_channels(ENGINE_QUEUE_CAPACITY);
        let (event_tx, event_rx) = mpsc::sync_channel(8);
        let (gate_tx, gate_rx) = mpsc::sync_channel(1);
        let worker = thread::spawn(move || {
            let mut runtime = FakeRuntime {
                events: event_tx,
                first_dispatch_gate: gate_rx,
                dispatches: 0,
            };
            run_engine_actor(&mut runtime, inbox)
        });

        let (first_tx, first_rx) = mpsc::sync_channel(1);
        dispatch_tx
            .send(EngineDispatch {
                request: authorized_request("actor-first"),
                response: first_tx,
            })
            .unwrap();
        assert_eq!(event_rx.recv().unwrap(), "dispatch-1");

        let (second_tx, _second_rx) = mpsc::sync_channel(1);
        dispatch_tx
            .send(EngineDispatch {
                request: authorized_request("actor-second"),
                response: second_tx,
            })
            .unwrap();
        let (force_tx, force_rx) = mpsc::sync_channel(1);
        control_tx
            .send(EngineControl::ForceFailClosed(force_tx))
            .unwrap();
        gate_tx.send(()).unwrap();
        first_rx.recv().unwrap();

        assert_eq!(event_rx.recv().unwrap(), "force-fail-closed");
        force_rx.recv().unwrap().unwrap();

        let (shutdown_tx, shutdown_rx) = mpsc::sync_channel(1);
        control_tx
            .send(EngineControl::Shutdown(shutdown_tx))
            .unwrap();
        shutdown_rx.recv().unwrap().unwrap();
        worker.join().unwrap().unwrap();
    }

    #[test]
    fn engine_health_failure_forces_blocking_and_keeps_actor_recoverable() {
        let (dispatch_tx, control_tx, inbox) = engine_actor_channels(1);
        let (event_tx, event_rx) = mpsc::sync_channel(4);
        let (stale_response_tx, stale_response_rx) = mpsc::sync_channel(1);
        dispatch_tx
            .send(EngineDispatch {
                request: authorized_command(
                    "actor-stale-commit",
                    BrokerCommand::CommitPolicy {
                        revision: 1,
                        policy_digest: "a".repeat(64),
                        ingress: StrictProxyIngressSet::empty(),
                    },
                ),
                response: stale_response_tx,
            })
            .unwrap();
        let worker = thread::spawn(move || {
            let mut runtime = FailingHealthRuntime {
                events: event_tx,
                fail_cleanup: false,
            };
            run_engine_actor(&mut runtime, inbox)
        });

        assert_eq!(event_rx.recv().unwrap(), "health-failed");
        assert_eq!(event_rx.recv().unwrap(), "force-fail-closed");
        let stale_response = stale_response_rx
            .recv_timeout(Duration::from_secs(1))
            .unwrap();
        assert!(matches!(
            stale_response.body,
            BrokerResponseBody::Error {
                code: BrokerErrorCode::BackendUnavailable
            }
        ));
        assert!(matches!(
            event_rx.recv_timeout(Duration::from_millis(100)),
            Err(RecvTimeoutError::Timeout)
        ));

        let (dispatch_response_tx, dispatch_response_rx) = mpsc::sync_channel(1);
        dispatch_tx
            .send(EngineDispatch {
                request: authorized_request("actor-recovery-status"),
                response: dispatch_response_tx,
            })
            .unwrap();
        dispatch_response_rx
            .recv_timeout(Duration::from_secs(1))
            .unwrap();
        assert_eq!(event_rx.recv().unwrap(), "dispatch-after-recovery");
        assert!(matches!(
            event_rx.recv_timeout(Duration::from_millis(100)),
            Err(RecvTimeoutError::Timeout)
        ));

        let (commit_response_tx, commit_response_rx) = mpsc::sync_channel(1);
        dispatch_tx
            .send(EngineDispatch {
                request: authorized_command(
                    "actor-recovery-commit",
                    BrokerCommand::CommitPolicy {
                        revision: 1,
                        policy_digest: "a".repeat(64),
                        ingress: StrictProxyIngressSet::empty(),
                    },
                ),
                response: commit_response_tx,
            })
            .unwrap();
        commit_response_rx
            .recv_timeout(Duration::from_secs(1))
            .unwrap();
        assert_eq!(event_rx.recv().unwrap(), "dispatch-after-recovery");
        assert_eq!(event_rx.recv().unwrap(), "health-failed");
        assert_eq!(event_rx.recv().unwrap(), "force-fail-closed");

        let (shutdown_tx, shutdown_rx) = mpsc::sync_channel(1);
        control_tx
            .send(EngineControl::Shutdown(shutdown_tx))
            .unwrap();
        assert_eq!(event_rx.recv().unwrap(), "force-fail-closed");
        shutdown_rx.recv().unwrap().unwrap();
        worker.join().unwrap().unwrap();
    }

    #[test]
    fn engine_health_failure_exits_when_fail_closed_cleanup_is_unproven() {
        let (_dispatch_tx, _control_tx, inbox) = engine_actor_channels(1);
        let (event_tx, event_rx) = mpsc::sync_channel(2);
        let mut runtime = FailingHealthRuntime {
            events: event_tx,
            fail_cleanup: true,
        };

        let error = run_engine_actor(&mut runtime, inbox)
            .unwrap_err()
            .to_string();

        assert!(error.contains("strict forwarding runtime became unhealthy"));
        assert!(error.contains("fail-closed cleanup failed"));
        assert!(error.contains("injected forwarding failure"));
        assert!(error.contains("injected cleanup failure"));
        assert_eq!(event_rx.recv().unwrap(), "health-failed");
        assert_eq!(event_rx.recv().unwrap(), "force-fail-closed");
    }

    #[test]
    fn idle_engine_actor_does_not_poll_health_every_25ms_when_forwarding_is_inactive() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        struct IdleCountingRuntime {
            health_checks: Arc<AtomicUsize>,
        }

        impl EngineRuntime for IdleCountingRuntime {
            fn dispatch(&mut self, request: AuthorizedBrokerRequest) -> BrokerResponse {
                BrokerResponse::error(
                    request.request().request_id.clone(),
                    BrokerErrorCode::BackendUnavailable,
                )
                .unwrap()
            }

            fn verify_health(&mut self) -> Result<()> {
                self.health_checks.fetch_add(1, Ordering::SeqCst);
                Ok(())
            }

            fn force_fail_closed(&mut self) -> Result<()> {
                Ok(())
            }

            fn has_active_health_supervision(&self) -> bool {
                false
            }
        }

        let (_dispatch_tx, control_tx, inbox) = engine_actor_channels(1);
        let health_checks = Arc::new(AtomicUsize::new(0));
        let worker_checks = health_checks.clone();
        let worker = thread::spawn(move || {
            let mut runtime = IdleCountingRuntime {
                health_checks: worker_checks,
            };
            run_engine_actor(&mut runtime, inbox)
        });

        thread::sleep(Duration::from_millis(120));
        let observed = health_checks.load(Ordering::SeqCst);
        let (shutdown_tx, shutdown_rx) = mpsc::sync_channel(1);
        control_tx
            .send(EngineControl::Shutdown(shutdown_tx))
            .unwrap();
        shutdown_rx.recv().unwrap().unwrap();
        worker.join().unwrap().unwrap();
        assert_eq!(
            observed, 0,
            "idle engine actor woke and polled verify_health {observed} times in 120ms"
        );
    }
}
