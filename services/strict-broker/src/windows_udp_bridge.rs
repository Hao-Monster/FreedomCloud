use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender, TryRecvError, TrySendError};
use std::sync::{Arc, RwLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};

use crate::{
    StrictCoreUdpTransport, StrictDriverDatagramBatch, StrictDriverDatagramBatchBuilder,
    StrictDriverDatagramBatchKind, StrictDriverDatagramFlags, StrictDriverDatagramLeaseWindow,
    StrictDriverDatagramRecord, StrictUdpReplayWindow, WindowsDriverDatagramHealthSnapshot,
    WindowsDriverIoctlCancellation, WindowsDriverIoctlDeadline, WindowsPipeShutdown,
    WindowsSharedIoctlDriverChannel, STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES,
    STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES, STRICT_DRIVER_DATAGRAM_MAX_RECORDS,
};

pub const STRICT_DRIVER_UDP_MAX_ASSOCIATIONS: usize = 1024;
pub const STRICT_DRIVER_UDP_ASSOCIATION_IDLE: Duration = Duration::from_secs(90);
const DRIVER_BATCH_BUFFER_COUNT: usize = 2;
const DRIVER_RECEIVE_DEADLINE: Duration = Duration::from_secs(300);
const DRIVER_SUBMIT_DEADLINE: Duration = Duration::from_secs(1);
const DRIVER_HEALTH_POLL_INTERVAL: Duration = Duration::from_millis(100);
const DRIVER_RECEIVE_READY_TIMEOUT: Duration = Duration::from_secs(1);
const BRIDGE_WAIT_SLICE: Duration = Duration::from_millis(100);
const BRIDGE_THREAD_STACK_BYTES: usize = 512 * 1024;

pub struct StrictDriverUdpAssociations {
    by_flow: HashMap<u64, DriverUdpAssociation>,
    by_association: HashMap<[u8; 16], u64>,
}

impl Default for StrictDriverUdpAssociations {
    fn default() -> Self {
        Self::new()
    }
}

struct DriverUdpAssociation {
    association_id: [u8; 16],
    target_group_index: u16,
    flags: StrictDriverDatagramFlags,
    local_endpoint: SocketAddr,
    remote_endpoint: SocketAddr,
    captured_replay: StrictUdpReplayWindow,
    reply_replay: StrictUdpReplayWindow,
    last_seen: Instant,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StrictDriverUdpOutbound {
    association_id: [u8; 16],
    target_group_index: u16,
    destination: SocketAddr,
}

impl StrictDriverUdpOutbound {
    pub fn association_id(&self) -> [u8; 16] {
        self.association_id
    }

    pub fn target_group_index(&self) -> u16 {
        self.target_group_index
    }

    pub fn destination(&self) -> SocketAddr {
        self.destination
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StrictDriverUdpReplyRoute {
    flow_token: u64,
    sequence: u64,
    target_group_index: u16,
    flags: StrictDriverDatagramFlags,
    local_endpoint: SocketAddr,
    remote_endpoint: SocketAddr,
}

impl StrictDriverUdpReplyRoute {
    pub fn flow_token(&self) -> u64 {
        self.flow_token
    }

    pub fn sequence(&self) -> u64 {
        self.sequence
    }

    pub fn target_group_index(&self) -> u16 {
        self.target_group_index
    }

    pub fn flags(&self) -> StrictDriverDatagramFlags {
        self.flags
    }

    pub fn local_endpoint(&self) -> SocketAddr {
        self.local_endpoint
    }

    pub fn remote_endpoint(&self) -> SocketAddr {
        self.remote_endpoint
    }
}

impl StrictDriverUdpAssociations {
    pub fn new() -> Self {
        Self {
            by_flow: HashMap::with_capacity(STRICT_DRIVER_UDP_MAX_ASSOCIATIONS),
            by_association: HashMap::with_capacity(STRICT_DRIVER_UDP_MAX_ASSOCIATIONS),
        }
    }

    pub fn len(&self) -> usize {
        self.by_flow.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_flow.is_empty()
    }

    pub fn route_captured(
        &mut self,
        record: &StrictDriverDatagramRecord<'_>,
        new_association_id: impl FnOnce() -> Result<[u8; 16]>,
    ) -> Result<StrictDriverUdpOutbound> {
        self.route_captured_at(record, new_association_id, Instant::now())
    }

    fn route_captured_at(
        &mut self,
        record: &StrictDriverDatagramRecord<'_>,
        new_association_id: impl FnOnce() -> Result<[u8; 16]>,
        now: Instant,
    ) -> Result<StrictDriverUdpOutbound> {
        let flow_token = record.flow_token();
        if let Some(association) = self.by_flow.get_mut(&flow_token) {
            if association.target_group_index != record.target_group_index()
                || association.flags != record.flags()
                || association.local_endpoint != record.local_endpoint()
                || association.remote_endpoint != record.remote_endpoint()
            {
                bail!("strict driver UDP flow metadata changed");
            }
            if !association.captured_replay.accept(record.sequence()) {
                bail!("strict driver UDP captured sequence is replayed or stale");
            }
            association.last_seen = now;
            return Ok(StrictDriverUdpOutbound {
                association_id: association.association_id,
                target_group_index: association.target_group_index,
                destination: association.remote_endpoint,
            });
        }

        if self.by_flow.len() >= STRICT_DRIVER_UDP_MAX_ASSOCIATIONS {
            self.sweep_expired_at(now, |_| {});
            if self.by_flow.len() >= STRICT_DRIVER_UDP_MAX_ASSOCIATIONS {
                bail!("strict driver UDP association limit is reached");
            }
        }
        let association_id = new_association_id().context("create strict UDP association ID")?;
        if association_id.iter().all(|byte| *byte == 0)
            || self.by_association.contains_key(&association_id)
        {
            bail!("strict driver UDP association ID is empty or duplicated");
        }
        let mut captured_replay = StrictUdpReplayWindow::default();
        if !captured_replay.accept(record.sequence()) {
            bail!("strict driver UDP initial captured sequence is invalid");
        }
        let association = DriverUdpAssociation {
            association_id,
            target_group_index: record.target_group_index(),
            flags: record.flags(),
            local_endpoint: record.local_endpoint(),
            remote_endpoint: record.remote_endpoint(),
            captured_replay,
            reply_replay: StrictUdpReplayWindow::default(),
            last_seen: now,
        };
        if self
            .by_association
            .insert(association_id, flow_token)
            .is_some()
        {
            bail!("strict driver UDP association index was unexpectedly occupied");
        }
        if self.by_flow.insert(flow_token, association).is_some() {
            self.by_association.remove(&association_id);
            bail!("strict driver UDP flow index was unexpectedly occupied");
        }
        Ok(StrictDriverUdpOutbound {
            association_id,
            target_group_index: record.target_group_index(),
            destination: record.remote_endpoint(),
        })
    }

    pub fn route_reply(
        &mut self,
        association_id: [u8; 16],
        sequence: u64,
        remote_endpoint: SocketAddr,
    ) -> Result<StrictDriverUdpReplyRoute> {
        self.route_reply_at(association_id, sequence, remote_endpoint, Instant::now())
    }

    fn route_reply_at(
        &mut self,
        association_id: [u8; 16],
        sequence: u64,
        remote_endpoint: SocketAddr,
        now: Instant,
    ) -> Result<StrictDriverUdpReplyRoute> {
        let flow_token = *self
            .by_association
            .get(&association_id)
            .context("strict driver UDP reply association is unknown or expired")?;
        let association = self
            .by_flow
            .get_mut(&flow_token)
            .context("strict driver UDP reply flow index is inconsistent")?;
        if association.association_id != association_id
            || association.remote_endpoint != remote_endpoint
        {
            bail!("strict driver UDP reply endpoint or association changed");
        }
        if !association.reply_replay.accept(sequence) {
            bail!("strict driver UDP reply sequence is replayed or stale");
        }
        association.last_seen = now;
        Ok(StrictDriverUdpReplyRoute {
            flow_token,
            sequence,
            target_group_index: association.target_group_index,
            flags: association.flags,
            local_endpoint: association.local_endpoint,
            remote_endpoint: association.remote_endpoint,
        })
    }

    pub fn sweep_expired(&mut self, on_expired: impl FnMut([u8; 16])) {
        self.sweep_expired_at(Instant::now(), on_expired);
    }

    fn sweep_expired_at(&mut self, now: Instant, mut on_expired: impl FnMut([u8; 16])) {
        let by_association = &mut self.by_association;
        self.by_flow.retain(|_, association| {
            if now.saturating_duration_since(association.last_seen)
                < STRICT_DRIVER_UDP_ASSOCIATION_IDLE
            {
                true
            } else {
                by_association.remove(&association.association_id);
                on_expired(association.association_id);
                false
            }
        });
    }
}

pub trait StrictDriverDatagramIo: Send + Sync {
    fn poll_captured(
        &self,
        output: &mut [u8],
        deadline: WindowsDriverIoctlDeadline,
        cancellation: &WindowsDriverIoctlCancellation,
        ready: Option<&SyncSender<()>>,
    ) -> Result<Option<usize>>;

    fn submit_reply(&self, input: &mut [u8], deadline: WindowsDriverIoctlDeadline) -> Result<()>;

    fn datagram_health(&self) -> Result<WindowsDriverDatagramHealthSnapshot>;
}

impl StrictDriverDatagramIo for WindowsSharedIoctlDriverChannel {
    fn poll_captured(
        &self,
        output: &mut [u8],
        deadline: WindowsDriverIoctlDeadline,
        cancellation: &WindowsDriverIoctlCancellation,
        ready: Option<&SyncSender<()>>,
    ) -> Result<Option<usize>> {
        self.receive_datagram_batch_until(output, deadline, cancellation, ready)
    }

    fn submit_reply(&self, input: &mut [u8], deadline: WindowsDriverIoctlDeadline) -> Result<()> {
        self.submit_datagram_batch(input, deadline)
    }

    fn datagram_health(&self) -> Result<WindowsDriverDatagramHealthSnapshot> {
        Ok(self.query_policy_snapshot()?.datagram_health)
    }
}

struct StrictDriverDatagramHealthMonitor {
    baseline: WindowsDriverDatagramHealthSnapshot,
    submitted: u64,
}

impl StrictDriverDatagramHealthMonitor {
    fn new(baseline: WindowsDriverDatagramHealthSnapshot) -> Result<Self> {
        baseline.validate()?;
        if baseline.injection_in_flight != 0 {
            bail!("strict driver retained UDP injections before bridge startup");
        }
        Ok(Self {
            baseline,
            submitted: 0,
        })
    }

    fn record_submission(&mut self, datagrams: usize) -> Result<()> {
        if datagrams == 0 || datagrams > STRICT_DRIVER_DATAGRAM_MAX_RECORDS {
            bail!("strict driver UDP submission count is invalid");
        }
        self.submitted = self
            .submitted
            .checked_add(datagrams as u64)
            .ok_or_else(|| anyhow::anyhow!("strict driver UDP submission count overflow"))?;
        Ok(())
    }

    fn observe(&self, current: WindowsDriverDatagramHealthSnapshot) -> Result<bool> {
        current.validate()?;
        if current.injection_failed != self.baseline.injection_failed {
            bail!(
                "strict driver UDP injection failure changed from {} to {} (last status 0x{:08x})",
                self.baseline.injection_failed,
                current.injection_failed,
                current.last_failure_status
            );
        }
        if current.partial_batch_failures != self.baseline.partial_batch_failures {
            bail!(
                "strict driver UDP partial-batch failure changed from {} to {} (last status 0x{:08x})",
                self.baseline.partial_batch_failures,
                current.partial_batch_failures,
                current.last_failure_status
            );
        }
        if current.last_failure_status != self.baseline.last_failure_status {
            bail!("strict driver UDP last-failure status changed without a matching counter");
        }
        let expected_attempts = self
            .baseline
            .injection_attempts
            .checked_add(self.submitted)
            .ok_or_else(|| anyhow::anyhow!("strict driver UDP attempt expectation overflow"))?;
        if current.injection_attempts != expected_attempts {
            bail!(
                "strict driver UDP attempt counter is {}, expected {}",
                current.injection_attempts,
                expected_attempts
            );
        }
        let succeeded = current
            .injection_succeeded
            .checked_sub(self.baseline.injection_succeeded)
            .ok_or_else(|| anyhow::anyhow!("strict driver UDP success counter rolled back"))?;
        let accounted = succeeded
            .checked_add(u64::from(current.injection_in_flight))
            .ok_or_else(|| anyhow::anyhow!("strict driver UDP completion accounting overflow"))?;
        if accounted != self.submitted {
            bail!("strict driver UDP completion accounting drifted from Broker submissions");
        }
        Ok(current.injection_in_flight != 0)
    }
}

struct CapturedDriverBatch {
    storage: Box<[u8]>,
    bytes: usize,
}

struct DriverReceiverControl {
    shutdown: WindowsPipeShutdown,
    cancellation: WindowsDriverIoctlCancellation,
    gate_revoking: Arc<AtomicBool>,
    ready: SyncSender<()>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct WindowsUdpBridgeReport {
    pub captured_batches: u64,
    pub captured_datagrams: u64,
    pub reply_batches: u64,
    pub reply_datagrams: u64,
}

pub struct WindowsUdpBridgeRuntime {
    shutdown: WindowsPipeShutdown,
    driver_cancellation: WindowsDriverIoctlCancellation,
    alive: Arc<AtomicBool>,
    gate_revoking: Arc<AtomicBool>,
    receiver_worker: Option<JoinHandle<Result<()>>>,
    bridge_worker: Option<JoinHandle<Result<WindowsUdpBridgeReport>>>,
}

impl WindowsUdpBridgeRuntime {
    pub fn is_alive(&self) -> bool {
        self.alive.load(Ordering::Acquire)
    }

    pub fn prepare_gate_revocation(&self) {
        self.gate_revoking.store(true, Ordering::Release);
    }

    pub fn stop(mut self) -> Result<WindowsUdpBridgeReport> {
        self.prepare_gate_revocation();
        self.shutdown.request();
        let cancellation = self.driver_cancellation.request();
        let receiver = join_bridge_worker(self.receiver_worker.take(), "driver datagram receiver");
        let bridge = join_bridge_worker(self.bridge_worker.take(), "Core UDP bridge");
        cancellation.context("cancel strict driver datagram receive")?;
        match (receiver, bridge) {
            (Ok(()), Ok(report)) => Ok(report),
            (Err(receiver), Ok(_)) => Err(receiver),
            (Ok(()), Err(bridge)) => Err(bridge),
            (Err(receiver), Err(bridge)) => Err(anyhow::anyhow!(
                "strict driver datagram receiver failed: {receiver:#}; Core UDP bridge failed: {bridge:#}"
            )),
        }
    }
}

impl Drop for WindowsUdpBridgeRuntime {
    fn drop(&mut self) {
        self.prepare_gate_revocation();
        self.shutdown.request();
        let _ = self.driver_cancellation.request();
        let _ = join_bridge_worker(self.receiver_worker.take(), "driver datagram receiver");
        let _ = join_bridge_worker(self.bridge_worker.take(), "Core UDP bridge");
    }
}

pub fn spawn_windows_udp_bridge_runtime<D, A>(
    driver: Arc<D>,
    core: StrictCoreUdpTransport,
    target_groups: Vec<String>,
    lease_window: Arc<RwLock<StrictDriverDatagramLeaseWindow>>,
    new_association_id: A,
) -> Result<WindowsUdpBridgeRuntime>
where
    D: StrictDriverDatagramIo + 'static,
    A: Fn() -> Result<[u8; 16]> + Send + Sync + 'static,
{
    if target_groups.is_empty()
        || target_groups.len() > 128
        || target_groups.iter().any(String::is_empty)
        || target_groups
            .windows(2)
            .any(|pair| pair[0].as_str() >= pair[1].as_str())
    {
        bail!("strict UDP bridge target groups are invalid");
    }
    let receive_deadline = WindowsDriverIoctlDeadline::new(DRIVER_RECEIVE_DEADLINE)?;
    let submit_deadline = WindowsDriverIoctlDeadline::new(DRIVER_SUBMIT_DEADLINE)?;
    let health_monitor = StrictDriverDatagramHealthMonitor::new(driver.datagram_health()?)?;
    let shutdown = WindowsPipeShutdown::new();
    let driver_cancellation = WindowsDriverIoctlCancellation::new()?;
    let alive = Arc::new(AtomicBool::new(true));
    let gate_revoking = Arc::new(AtomicBool::new(false));
    let (free_sender, free_receiver) = mpsc::sync_channel(DRIVER_BATCH_BUFFER_COUNT);
    let (captured_sender, captured_receiver) = mpsc::sync_channel(DRIVER_BATCH_BUFFER_COUNT);
    for _ in 0..DRIVER_BATCH_BUFFER_COUNT {
        free_sender
            .send(vec![0_u8; STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES].into_boxed_slice())
            .map_err(|_| anyhow::anyhow!("initialize strict driver datagram buffer pool"))?;
    }

    let receiver_shutdown = shutdown.clone();
    let receiver_alive = Arc::clone(&alive);
    let receiver_driver = Arc::clone(&driver);
    let receiver_free_sender = free_sender.clone();
    let receiver_cancellation = driver_cancellation.clone();
    let receiver_gate_revoking = Arc::clone(&gate_revoking);
    let (receiver_ready_sender, receiver_ready) = mpsc::sync_channel(1);
    let receiver_control = DriverReceiverControl {
        shutdown: receiver_shutdown.clone(),
        cancellation: receiver_cancellation.clone(),
        gate_revoking: receiver_gate_revoking,
        ready: receiver_ready_sender,
    };
    let receiver_worker = thread::Builder::new()
        .name("flclash-strict-driver-udp".into())
        .stack_size(BRIDGE_THREAD_STACK_BYTES)
        .spawn(move || {
            let result = run_driver_receiver(
                receiver_driver,
                free_receiver,
                receiver_free_sender,
                captured_sender,
                receive_deadline,
                receiver_control,
            );
            if result.is_err() {
                receiver_alive.store(false, Ordering::Release);
                receiver_shutdown.request();
                let _ = receiver_cancellation.request();
            }
            result
        })
        .context("start strict driver datagram receiver")?;

    if receiver_ready
        .recv_timeout(DRIVER_RECEIVE_READY_TIMEOUT)
        .is_err()
    {
        shutdown.request();
        gate_revoking.store(true, Ordering::Release);
        let _ = driver_cancellation.request();
        let receiver = receiver_worker
            .join()
            .map_err(|_| anyhow::anyhow!("strict driver datagram receiver panicked"))?;
        return match receiver {
            Ok(()) => Err(anyhow::anyhow!(
                "strict driver datagram receive was not pre-armed"
            )),
            Err(error) => Err(error).context("pre-arm strict driver datagram receive"),
        };
    }

    let bridge_shutdown = shutdown.clone();
    let bridge_alive = Arc::clone(&alive);
    let bridge_driver = driver;
    let bridge_cancellation = driver_cancellation.clone();
    let association_ids = Arc::new(new_association_id);
    let bridge_worker = match thread::Builder::new()
        .name("flclash-strict-core-udp".into())
        .stack_size(BRIDGE_THREAD_STACK_BYTES)
        .spawn(move || {
            let result = run_udp_bridge(
                bridge_driver,
                core,
                target_groups,
                lease_window,
                association_ids,
                captured_receiver,
                free_sender,
                &bridge_shutdown,
                submit_deadline,
                health_monitor,
            );
            bridge_alive.store(false, Ordering::Release);
            if result.is_err() {
                bridge_shutdown.request();
                let _ = bridge_cancellation.request();
            }
            result
        }) {
        Ok(worker) => worker,
        Err(error) => {
            shutdown.request();
            let _ = driver_cancellation.request();
            let _ = receiver_worker.join();
            return Err(error).context("start strict Core UDP bridge");
        }
    };

    Ok(WindowsUdpBridgeRuntime {
        shutdown,
        driver_cancellation,
        alive,
        gate_revoking,
        receiver_worker: Some(receiver_worker),
        bridge_worker: Some(bridge_worker),
    })
}

fn run_driver_receiver<D: StrictDriverDatagramIo + 'static>(
    driver: Arc<D>,
    free_receiver: Receiver<Box<[u8]>>,
    free_sender: SyncSender<Box<[u8]>>,
    captured_sender: SyncSender<CapturedDriverBatch>,
    deadline: WindowsDriverIoctlDeadline,
    control: DriverReceiverControl,
) -> Result<()> {
    let mut ready = Some(control.ready);
    while !control.shutdown.is_requested() {
        let mut storage = match free_receiver.recv_timeout(BRIDGE_WAIT_SLICE) {
            Ok(storage) => storage,
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) if control.shutdown.is_requested() => return Ok(()),
            Err(RecvTimeoutError::Disconnected) => {
                bail!("strict driver datagram buffer pool disconnected")
            }
        };
        let polled = driver.poll_captured(
            &mut storage,
            deadline,
            &control.cancellation,
            ready.as_ref(),
        );
        ready = None;
        let bytes = match polled {
            Err(_) if control.gate_revoking.load(Ordering::Acquire) => return Ok(()),
            Err(error) => return Err(error),
            Ok(Some(bytes)) => bytes,
            Ok(None) if control.cancellation.is_requested() || control.shutdown.is_requested() => {
                return Ok(())
            }
            Ok(None) => {
                free_sender
                    .try_send(storage)
                    .map_err(|_| anyhow::anyhow!("return idle strict driver datagram buffer"))?;
                continue;
            }
        };
        match captured_sender.try_send(CapturedDriverBatch { storage, bytes }) {
            Ok(()) => {}
            Err(TrySendError::Full(_)) => {
                bail!("strict driver datagram bridge queue is saturated")
            }
            Err(TrySendError::Disconnected(_)) if control.shutdown.is_requested() => return Ok(()),
            Err(TrySendError::Disconnected(_)) => {
                bail!("strict driver datagram bridge disconnected")
            }
        }
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn run_udp_bridge<D, A>(
    driver: Arc<D>,
    mut core: StrictCoreUdpTransport,
    target_groups: Vec<String>,
    lease_window: Arc<RwLock<StrictDriverDatagramLeaseWindow>>,
    association_ids: Arc<A>,
    captured_receiver: Receiver<CapturedDriverBatch>,
    free_sender: SyncSender<Box<[u8]>>,
    shutdown: &WindowsPipeShutdown,
    submit_deadline: WindowsDriverIoctlDeadline,
    mut health_monitor: StrictDriverDatagramHealthMonitor,
) -> Result<WindowsUdpBridgeReport>
where
    D: StrictDriverDatagramIo + 'static,
    A: Fn() -> Result<[u8; 16]> + Send + Sync + 'static,
{
    let mut report = WindowsUdpBridgeReport::default();
    let mut associations = StrictDriverUdpAssociations::new();
    let mut reply_payload = vec![0_u8; STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES].into_boxed_slice();
    let mut reply_batch = vec![0_u8; STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES].into_boxed_slice();
    let mut health_pending = false;
    let mut next_health_check = Instant::now() + DRIVER_HEALTH_POLL_INTERVAL;

    while !shutdown.is_requested() {
        if health_pending && Instant::now() >= next_health_check {
            health_pending = health_monitor.observe(driver.datagram_health()?)?;
            next_health_check = Instant::now() + DRIVER_HEALTH_POLL_INTERVAL;
        }
        loop {
            match captured_receiver.try_recv() {
                Ok(batch) => {
                    process_captured_batch(
                        &batch.storage[..batch.bytes],
                        &lease_window,
                        &target_groups,
                        association_ids.as_ref(),
                        &mut associations,
                        &mut core,
                        &mut report,
                    )?;
                    free_sender
                        .try_send(batch.storage)
                        .map_err(|_| anyhow::anyhow!("return strict driver datagram buffer"))?;
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) if shutdown.is_requested() => break,
                Err(TryRecvError::Disconnected) => {
                    bail!("strict driver datagram receiver exited unexpectedly")
                }
            }
        }

        let identity = lease_window
            .read()
            .map_err(|_| anyhow::anyhow!("strict UDP lease window lock is poisoned"))?
            .current();
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut reply_batch,
            StrictDriverDatagramBatchKind::Reply,
            identity,
        )?;
        let mut reply_count = 0_usize;
        for _ in 0..STRICT_DRIVER_DATAGRAM_MAX_RECORDS {
            let Some(reply) = core.poll_receive_into(&mut reply_payload)? else {
                break;
            };
            let route = associations.route_reply(
                reply.association_id(),
                reply.sequence(),
                reply.endpoint(),
            )?;
            builder.push(
                route.flow_token(),
                route.sequence(),
                route.target_group_index(),
                route.flags(),
                route.local_endpoint(),
                route.remote_endpoint(),
                &reply_payload[..reply.payload_bytes()],
            )?;
            reply_count += 1;
        }
        if reply_count != 0 {
            let bytes = builder.finish()?.len();
            driver.submit_reply(&mut reply_batch[..bytes], submit_deadline)?;
            health_monitor.record_submission(reply_count)?;
            if !health_pending {
                health_pending = true;
                next_health_check = Instant::now() + DRIVER_HEALTH_POLL_INTERVAL;
            }
            report.reply_batches = report.reply_batches.saturating_add(1);
            report.reply_datagrams = report.reply_datagrams.saturating_add(reply_count as u64);
        }
        associations.sweep_expired(|association_id| {
            core.remove_association(association_id);
        });
    }
    Ok(report)
}

fn process_captured_batch<A>(
    input: &[u8],
    lease_window: &RwLock<StrictDriverDatagramLeaseWindow>,
    target_groups: &[String],
    association_ids: &A,
    associations: &mut StrictDriverUdpAssociations,
    core: &mut StrictCoreUdpTransport,
    report: &mut WindowsUdpBridgeReport,
) -> Result<()>
where
    A: Fn() -> Result<[u8; 16]>,
{
    let window = *lease_window
        .read()
        .map_err(|_| anyhow::anyhow!("strict UDP lease window lock is poisoned"))?;
    let batch = StrictDriverDatagramBatch::decode_with_window(
        input,
        StrictDriverDatagramBatchKind::Captured,
        window,
    )?;
    for record in batch.records() {
        let route = associations.route_captured(&record, association_ids)?;
        let target_group = target_groups
            .get(usize::from(route.target_group_index()))
            .context("strict driver UDP target-group index is unavailable")?;
        core.send(
            route.association_id(),
            target_group,
            route.destination(),
            record.payload(),
        )?;
        report.captured_datagrams = report.captured_datagrams.saturating_add(1);
    }
    report.captured_batches = report.captured_batches.saturating_add(1);
    Ok(())
}

fn join_bridge_worker<T>(worker: Option<JoinHandle<Result<T>>>, label: &str) -> Result<T> {
    let worker = worker.with_context(|| format!("strict {label} worker is missing"))?;
    worker
        .join()
        .map_err(|_| anyhow::anyhow!("strict {label} worker panicked"))?
        .with_context(|| format!("strict {label} worker failed"))
}

#[cfg(test)]
mod tests {
    use std::net::{Ipv4Addr, SocketAddrV4, UdpSocket};
    use std::sync::Mutex;

    use flclash_strict_contract::{StrictProxyIngressEntry, StrictProxyIngressSet};

    use super::*;
    use crate::{
        StrictDriverDatagramBatch, StrictDriverDatagramBatchBuilder, StrictDriverDatagramBatchKind,
        StrictDriverDatagramLeaseIdentity, StrictUdpDataAuthenticator, StrictUdpDataDirection,
        STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES, STRICT_UDP_DATA_MAX_FRAME_BYTES,
    };

    const LOCAL: &str = "10.0.0.2:53000";
    const REMOTE: &str = "1.1.1.1:443";

    fn encoded_record(
        flow_token: u64,
        sequence: u64,
        target_group_index: u16,
        remote: &str,
    ) -> Vec<u8> {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let mut storage = vec![0_u8; STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES];
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut storage,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        builder
            .push(
                flow_token,
                sequence,
                target_group_index,
                StrictDriverDatagramFlags::QUIC,
                LOCAL.parse().unwrap(),
                remote.parse().unwrap(),
                b"payload",
            )
            .unwrap();
        builder.finish().unwrap().to_vec()
    }

    fn with_record<T>(bytes: &[u8], body: impl FnOnce(&StrictDriverDatagramRecord<'_>) -> T) -> T {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let batch = StrictDriverDatagramBatch::decode(
            bytes,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        body(&batch.records().next().unwrap())
    }

    #[test]
    fn association_state_routes_async_replies_without_endpoint_or_group_drift() {
        let now = Instant::now();
        let mut table = StrictDriverUdpAssociations::new();
        let first = encoded_record(11, 1, 3, REMOTE);
        let outbound = with_record(&first, |record| {
            table.route_captured_at(record, || Ok([0x44; 16]), now)
        })
        .unwrap();
        assert_eq!(outbound.association_id(), [0x44; 16]);
        assert_eq!(outbound.target_group_index(), 3);
        assert_eq!(
            outbound.destination(),
            REMOTE.parse::<SocketAddr>().unwrap()
        );

        let second = encoded_record(11, 2, 3, REMOTE);
        let second = with_record(&second, |record| {
            table.route_captured_at(record, || Ok([0x55; 16]), now)
        })
        .unwrap();
        assert_eq!(second.association_id(), [0x44; 16]);

        let reply = table
            .route_reply_at([0x44; 16], 1, REMOTE.parse().unwrap(), now)
            .unwrap();
        assert_eq!(reply.flow_token(), 11);
        assert_eq!(reply.target_group_index(), 3);
        assert_eq!(reply.local_endpoint(), LOCAL.parse::<SocketAddr>().unwrap());
        assert_eq!(
            reply.remote_endpoint(),
            REMOTE.parse::<SocketAddr>().unwrap()
        );
        assert_eq!(reply.flags(), StrictDriverDatagramFlags::QUIC);
        assert_eq!(reply.sequence(), 1);

        assert!(table
            .route_reply_at([0x44; 16], 1, REMOTE.parse().unwrap(), now)
            .is_err());
        assert!(table
            .route_reply_at([0x44; 16], 2, "8.8.8.8:443".parse().unwrap(), now)
            .is_err());
        assert!(table
            .route_reply_at([0x66; 16], 1, REMOTE.parse().unwrap(), now)
            .is_err());
    }

    #[test]
    fn association_state_rejects_replay_mutation_and_identifier_collision() {
        let now = Instant::now();
        let mut table = StrictDriverUdpAssociations::new();
        let first = encoded_record(11, 2, 3, REMOTE);
        with_record(&first, |record| {
            table.route_captured_at(record, || Ok([0x44; 16]), now)
        })
        .unwrap();

        let replay = encoded_record(11, 2, 3, REMOTE);
        assert!(with_record(&replay, |record| {
            table.route_captured_at(record, || Ok([0x55; 16]), now)
        })
        .is_err());
        let changed_group = encoded_record(11, 3, 4, REMOTE);
        assert!(with_record(&changed_group, |record| {
            table.route_captured_at(record, || Ok([0x55; 16]), now)
        })
        .is_err());

        let other = encoded_record(12, 1, 3, REMOTE);
        assert!(with_record(&other, |record| {
            table.route_captured_at(record, || Ok([0x44; 16]), now)
        })
        .is_err());
    }

    #[test]
    fn association_state_has_a_hard_limit_and_idle_expiry() {
        let now = Instant::now();
        let mut table = StrictDriverUdpAssociations::new();
        for flow_token in 1..=STRICT_DRIVER_UDP_MAX_ASSOCIATIONS as u64 {
            let encoded = encoded_record(flow_token, 1, 0, REMOTE);
            with_record(&encoded, |record| {
                let mut association_id = [0_u8; 16];
                association_id[8..].copy_from_slice(&flow_token.to_le_bytes());
                table.route_captured_at(record, || Ok(association_id), now)
            })
            .unwrap();
        }
        assert_eq!(table.len(), STRICT_DRIVER_UDP_MAX_ASSOCIATIONS);
        let overflow = encoded_record(2_000, 1, 0, REMOTE);
        assert!(with_record(&overflow, |record| {
            table.route_captured_at(record, || Ok([0xff; 16]), now)
        })
        .is_err());

        let mut expired = Vec::new();
        table.sweep_expired_at(
            now + STRICT_DRIVER_UDP_ASSOCIATION_IDLE + Duration::from_millis(1),
            |association_id| expired.push(association_id),
        );
        assert_eq!(expired.len(), STRICT_DRIVER_UDP_MAX_ASSOCIATIONS);
        assert!(table.is_empty());
    }

    struct FakeDriverDatagramIo {
        captured: Mutex<Receiver<Vec<u8>>>,
        replies: SyncSender<Vec<u8>>,
        health: Mutex<WindowsDriverDatagramHealthSnapshot>,
        fail_completion: bool,
    }

    impl StrictDriverDatagramIo for FakeDriverDatagramIo {
        fn poll_captured(
            &self,
            output: &mut [u8],
            _deadline: WindowsDriverIoctlDeadline,
            cancellation: &WindowsDriverIoctlCancellation,
            ready: Option<&SyncSender<()>>,
        ) -> Result<Option<usize>> {
            if cancellation.is_requested() {
                return Ok(None);
            }
            if let Some(ready) = ready {
                let _ = ready.try_send(());
            }
            match self
                .captured
                .lock()
                .map_err(|_| anyhow::anyhow!("fake captured queue lock is poisoned"))?
                .recv_timeout(Duration::from_millis(20))
            {
                Ok(batch) => {
                    if batch.len() > output.len() {
                        bail!("fake captured batch is oversized");
                    }
                    output[..batch.len()].copy_from_slice(&batch);
                    Ok(Some(batch.len()))
                }
                Err(RecvTimeoutError::Timeout) => Ok(None),
                Err(RecvTimeoutError::Disconnected) => {
                    bail!("fake captured batch queue disconnected")
                }
            }
        }

        fn submit_reply(
            &self,
            input: &mut [u8],
            _deadline: WindowsDriverIoctlDeadline,
        ) -> Result<()> {
            let record_count = u32::from_le_bytes(
                input
                    .get(16..20)
                    .context("fake reply batch header is truncated")?
                    .try_into()
                    .map_err(|_| anyhow::anyhow!("fake reply batch header is truncated"))?,
            );
            let mut health = self
                .health
                .lock()
                .map_err(|_| anyhow::anyhow!("fake driver health lock is poisoned"))?;
            health.injection_attempts = health
                .injection_attempts
                .checked_add(u64::from(record_count))
                .ok_or_else(|| anyhow::anyhow!("fake driver attempt counter overflow"))?;
            if self.fail_completion {
                health.injection_failed = health
                    .injection_failed
                    .checked_add(1)
                    .ok_or_else(|| anyhow::anyhow!("fake driver failure counter overflow"))?;
                health.injection_succeeded = health
                    .injection_succeeded
                    .checked_add(u64::from(record_count.saturating_sub(1)))
                    .ok_or_else(|| anyhow::anyhow!("fake driver success counter overflow"))?;
                health.last_failure_status = 0xc000_0001;
            } else {
                health.injection_succeeded = health
                    .injection_succeeded
                    .checked_add(u64::from(record_count))
                    .ok_or_else(|| anyhow::anyhow!("fake driver success counter overflow"))?;
            }
            self.replies
                .send(input.to_vec())
                .map_err(|_| anyhow::anyhow!("fake reply queue disconnected"))
        }

        fn datagram_health(&self) -> Result<WindowsDriverDatagramHealthSnapshot> {
            self.health
                .lock()
                .map(|health| *health)
                .map_err(|_| anyhow::anyhow!("fake driver health lock is poisoned"))
        }
    }

    #[test]
    fn bridge_preserves_multiple_async_replies_for_one_captured_datagram() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let core_endpoint = match core.local_addr().unwrap() {
            SocketAddr::V4(endpoint) => endpoint,
            SocketAddr::V6(_) => unreachable!(),
        };
        let ingress = StrictProxyIngressSet::new(
            41,
            core_endpoint,
            vec![StrictProxyIngressEntry::new(
                "GLOBAL".into(),
                SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41001),
                format!("{}{}", "11".repeat(16), "22".repeat(16)),
                "33".repeat(32),
            )
            .unwrap()],
        )
        .unwrap();
        let core_worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(41, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (bytes, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..bytes], StrictUdpDataDirection::Outbound)
                .unwrap();
            assert_eq!(decoded.payload(), b"payload");
            for (sequence, payload) in [(1, b"reply-one".as_slice()), (2, b"reply-two".as_slice())]
            {
                let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
                let bytes = authenticator
                    .encode(
                        &mut response,
                        StrictUdpDataDirection::Inbound,
                        decoded.association_id(),
                        sequence,
                        decoded.endpoint(),
                        payload,
                    )
                    .unwrap();
                core.send_to(&response[..bytes], source).unwrap();
            }
        });

        let transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_millis(20)).unwrap();
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let window = Arc::new(RwLock::new(StrictDriverDatagramLeaseWindow::new(identity)));
        let (captured_sender, captured_receiver) = mpsc::sync_channel(1);
        let (reply_sender, reply_receiver) = mpsc::sync_channel(4);
        let driver = Arc::new(FakeDriverDatagramIo {
            captured: Mutex::new(captured_receiver),
            replies: reply_sender,
            health: Mutex::new(WindowsDriverDatagramHealthSnapshot::default()),
            fail_completion: false,
        });
        let runtime = spawn_windows_udp_bridge_runtime(
            driver,
            transport,
            vec!["GLOBAL".into()],
            window,
            || Ok([0x44; 16]),
        )
        .unwrap();
        assert!(runtime.is_alive());
        captured_sender
            .send(encoded_record(11, 1, 0, REMOTE))
            .unwrap();

        let mut replies = Vec::new();
        while replies.len() < 2 {
            let encoded = reply_receiver.recv_timeout(Duration::from_secs(2)).unwrap();
            let batch = StrictDriverDatagramBatch::decode(
                &encoded,
                StrictDriverDatagramBatchKind::Reply,
                identity,
            )
            .unwrap();
            for reply in batch.records() {
                assert_eq!(reply.flow_token(), 11);
                assert_eq!(reply.remote_endpoint(), REMOTE.parse().unwrap());
                replies.push((reply.sequence(), reply.payload().to_vec()));
            }
        }
        replies.sort_by_key(|reply| reply.0);
        assert_eq!(replies[0], (1, b"reply-one".to_vec()));
        assert_eq!(replies[1], (2, b"reply-two".to_vec()));
        let report = runtime.stop().unwrap();
        assert_eq!(report.captured_batches, 1);
        assert_eq!(report.captured_datagrams, 1);
        assert_eq!(report.reply_datagrams, 2);
        assert!((1..=2).contains(&report.reply_batches));
        core_worker.join().unwrap();
    }

    #[test]
    fn bridge_stops_on_async_driver_injection_failure() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let core_endpoint = match core.local_addr().unwrap() {
            SocketAddr::V4(endpoint) => endpoint,
            SocketAddr::V6(_) => unreachable!(),
        };
        let ingress = StrictProxyIngressSet::new(
            41,
            core_endpoint,
            vec![StrictProxyIngressEntry::new(
                "GLOBAL".into(),
                SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41001),
                format!("{}{}", "11".repeat(16), "22".repeat(16)),
                "33".repeat(32),
            )
            .unwrap()],
        )
        .unwrap();
        let core_worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(41, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (bytes, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..bytes], StrictUdpDataDirection::Outbound)
                .unwrap();
            let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let bytes = authenticator
                .encode(
                    &mut response,
                    StrictUdpDataDirection::Inbound,
                    decoded.association_id(),
                    1,
                    decoded.endpoint(),
                    b"reply",
                )
                .unwrap();
            core.send_to(&response[..bytes], source).unwrap();
        });

        let transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_millis(20)).unwrap();
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let window = Arc::new(RwLock::new(StrictDriverDatagramLeaseWindow::new(identity)));
        let (captured_sender, captured_receiver) = mpsc::sync_channel(1);
        let (reply_sender, reply_receiver) = mpsc::sync_channel(1);
        let driver = Arc::new(FakeDriverDatagramIo {
            captured: Mutex::new(captured_receiver),
            replies: reply_sender,
            health: Mutex::new(WindowsDriverDatagramHealthSnapshot::default()),
            fail_completion: true,
        });
        let runtime = spawn_windows_udp_bridge_runtime(
            driver,
            transport,
            vec!["GLOBAL".into()],
            window,
            || Ok([0x44; 16]),
        )
        .unwrap();
        captured_sender
            .send(encoded_record(11, 1, 0, REMOTE))
            .unwrap();
        reply_receiver.recv_timeout(Duration::from_secs(2)).unwrap();

        let deadline = Instant::now() + Duration::from_secs(2);
        while runtime.is_alive() && Instant::now() < deadline {
            thread::yield_now();
        }
        assert!(!runtime.is_alive());
        let error = runtime.stop().unwrap_err();
        assert!(format!("{error:#}").contains("injection failure"));
        core_worker.join().unwrap();
    }

    #[test]
    fn injection_health_monitor_rejects_failure_and_counter_drift() {
        let baseline = WindowsDriverDatagramHealthSnapshot::default();
        let mut monitor = StrictDriverDatagramHealthMonitor::new(baseline).unwrap();
        monitor.record_submission(2).unwrap();
        assert!(monitor
            .observe(WindowsDriverDatagramHealthSnapshot {
                injection_attempts: 2,
                injection_succeeded: 1,
                injection_in_flight: 1,
                ..Default::default()
            })
            .unwrap());
        assert!(!monitor
            .observe(WindowsDriverDatagramHealthSnapshot {
                injection_attempts: 2,
                injection_succeeded: 2,
                ..Default::default()
            })
            .unwrap());

        let error = monitor
            .observe(WindowsDriverDatagramHealthSnapshot {
                injection_attempts: 3,
                injection_succeeded: 2,
                injection_failed: 1,
                last_failure_status: 0xc000_0001,
                ..Default::default()
            })
            .unwrap_err();
        assert!(error.to_string().contains("injection failure"));

        let mut drift = StrictDriverDatagramHealthMonitor::new(baseline).unwrap();
        drift.record_submission(1).unwrap();
        assert!(drift
            .observe(WindowsDriverDatagramHealthSnapshot::default())
            .unwrap_err()
            .to_string()
            .contains("attempt counter"));
    }
}
