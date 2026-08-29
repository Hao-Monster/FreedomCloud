use std::net::{
    Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6, TcpListener, UdpSocket,
};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::StrictProxyIngressSet;
use windows_sys::Win32::Security::Cryptography::{
    BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG,
};

use crate::windows_core_udp_health::probe_core_udp_health;
use crate::{
    handle_windows_strict_tcp_connection, probe_socks5_authentication,
    verify_windows_packaged_core_ingress_set, ForwardingHealth, ForwardingHealthProbe,
    Socks5ProxyIngress, StrictPackageManifest, WindowsDriverPolicySnapshot, WindowsEndpointLease,
    WindowsPipeShutdown, WindowsSharedIoctlDriverChannel, WindowsStrictTcpSessionPlan,
    WindowsTcpListenerBinding, WindowsTcpListenerReport, WindowsTcpRelayLimits,
};

const ENDPOINT_LEASE_TTL: Duration = Duration::from_secs(6);
const ENDPOINT_LEASE_RENEW_INTERVAL: Duration = Duration::from_secs(2);
const EXPIRY_WAIT_SLICE: Duration = Duration::from_millis(50);
const CORE_PROBE_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_CORE_PROBE_WORKERS: usize = 8;
const CORE_PROBE_THREAD_STACK_BYTES: usize = 256 * 1024;
const MAX_TCP_WORKERS: usize = 16;
const TCP_CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const SOCKS_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
const TCP_RELAY_IDLE_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const RUNTIME_THREAD_STACK_BYTES: usize = 512 * 1024;

trait EndpointLeaseChannel: Send {
    fn activate(&self, lease: &WindowsEndpointLease) -> Result<WindowsDriverPolicySnapshot>;
    fn revoke(&self) -> Result<()>;
}

impl EndpointLeaseChannel for WindowsSharedIoctlDriverChannel {
    fn activate(&self, lease: &WindowsEndpointLease) -> Result<WindowsDriverPolicySnapshot> {
        self.activate_endpoint_lease(lease)
    }

    fn revoke(&self) -> Result<()> {
        self.revoke_endpoint_lease().map(|_| ())
    }
}

pub(crate) struct WindowsTcpForwardingHealth {
    driver: Arc<Mutex<Box<dyn EndpointLeaseChannel>>>,
    core_path: PathBuf,
    package: StrictPackageManifest,
    active: Option<ActiveWindowsTcpRuntime>,
}

struct ActiveWindowsTcpRuntime {
    driver: Arc<Mutex<Box<dyn EndpointLeaseChannel>>>,
    renewal_stop: Option<SyncSender<()>>,
    renewal_worker: Option<JoinHandle<Result<()>>>,
    listener_shutdown: WindowsPipeShutdown,
    listener_worker: Option<JoinHandle<Result<WindowsTcpListenerReport>>>,
    conservative_expiry: Arc<Mutex<Instant>>,
    _tcp_retention: [TcpListener; 2],
    _udp_sockets: [UdpSocket; 2],
}

impl WindowsTcpForwardingHealth {
    pub(crate) fn new(
        driver: WindowsSharedIoctlDriverChannel,
        core_path: impl Into<PathBuf>,
        package: StrictPackageManifest,
    ) -> Self {
        Self {
            driver: Arc::new(Mutex::new(Box::new(driver))),
            core_path: core_path.into(),
            package,
            active: None,
        }
    }

    fn activate(
        &mut self,
        revision: u64,
        policy_digest: &str,
        ingress: &StrictProxyIngressSet,
    ) -> Result<ForwardingHealth> {
        self.deactivate()?;
        ingress.validate()?;

        let listener_binding = WindowsTcpListenerBinding::bind()?;
        let listener_endpoints = listener_binding.endpoints();
        let tcp_retention = listener_binding.retention_handles()?;
        let udp_sockets = bind_udp_reservations()?;
        let udp_v4 = udp_endpoint_v4(&udp_sockets[0])?;
        let udp_v6 = udp_endpoint_v6(&udp_sockets[1])?;
        let ingresses = build_socks_ingresses(ingress)?;
        let core_endpoints = ingresses
            .iter()
            .map(Socks5ProxyIngress::endpoint)
            .collect::<Vec<_>>();
        let core_udp_endpoint = ingress
            .udp_endpoint
            .context("strict Core UDP health endpoint is missing")?;
        let core_owner = verify_windows_packaged_core_ingress_set(
            &core_endpoints,
            std::slice::from_ref(&core_udp_endpoint),
            &self.core_path,
            &self.package,
        )
        .context("attest strict Core ingress ownership")?;
        probe_all_core_ingresses(&ingresses, core_udp_endpoint, ingress.generation)?;

        let plan_slot = Arc::new(OnceLock::<Arc<WindowsStrictTcpSessionPlan>>::new());
        let handler_slot = Arc::clone(&plan_slot);
        let pool = listener_binding.into_pool(tcp_worker_count(), move |stream, shutdown| {
            let plan = handler_slot
                .get()
                .ok_or_else(|| anyhow::anyhow!("strict TCP session plan is not active"))?;
            handle_windows_strict_tcp_connection(stream, plan, shutdown).map(|_| ())
        })?;
        let nonce = random_nonce()?;
        let lease = WindowsEndpointLease::new(
            revision,
            policy_digest,
            nonce,
            ENDPOINT_LEASE_TTL,
            listener_endpoints.v4(),
            listener_endpoints.v6(),
            udp_v4,
            udp_v6,
        )?;
        let relay_limits = WindowsTcpRelayLimits::new(TCP_RELAY_IDLE_TIMEOUT)?;
        let listener_shutdown = WindowsPipeShutdown::new();
        let listener_alive = Arc::new(AtomicBool::new(true));
        let listener_worker = spawn_listener(pool, listener_shutdown.clone(), &listener_alive)?;

        let conservative_expiry = Arc::new(Mutex::new(Instant::now() + ENDPOINT_LEASE_TTL));
        let initial_snapshot = match activate_lease(&self.driver, &lease, &conservative_expiry) {
            Ok(snapshot) => snapshot,
            Err(activation) => {
                let cleanup = revoke_or_wait(&self.driver, &conservative_expiry);
                listener_shutdown.request();
                let listener = join_listener(listener_worker);
                return Err(combine_setup_failure(activation, cleanup, listener));
            }
        };
        let plan = (|| {
            let lease_generation = initial_snapshot
                .endpoint_lease
                .as_ref()
                .map(|active| active.generation)
                .ok_or_else(|| {
                    anyhow::anyhow!("strict driver omitted its active endpoint lease")
                })?;
            let plan = Arc::new(WindowsStrictTcpSessionPlan::new(
                core_owner,
                lease_generation,
                revision,
                policy_digest,
                nonce,
                ingresses,
                TCP_CONNECT_TIMEOUT,
                SOCKS_HANDSHAKE_TIMEOUT,
                relay_limits,
            )?);
            plan_slot
                .set(Arc::clone(&plan))
                .map_err(|_| anyhow::anyhow!("strict TCP session plan was installed twice"))?;
            Ok::<_, anyhow::Error>(plan)
        })();
        let plan = match plan {
            Ok(plan) => plan,
            Err(setup) => {
                let cleanup = revoke_or_wait(&self.driver, &conservative_expiry);
                listener_shutdown.request();
                let listener = join_listener(listener_worker);
                return Err(combine_setup_failure(setup, cleanup, listener));
            }
        };

        let (renewal_stop, renewal_requests) = mpsc::sync_channel(1);
        let renewal_worker = match spawn_renewal(
            Arc::clone(&self.driver),
            lease,
            plan,
            renewal_requests,
            listener_shutdown.clone(),
            Arc::clone(&listener_alive),
            Arc::clone(&conservative_expiry),
        ) {
            Ok(worker) => worker,
            Err(spawn) => {
                let cleanup = revoke_or_wait(&self.driver, &conservative_expiry);
                listener_shutdown.request();
                let listener = join_listener(listener_worker);
                return Err(combine_setup_failure(spawn, cleanup, listener));
            }
        };

        self.active = Some(ActiveWindowsTcpRuntime {
            driver: Arc::clone(&self.driver),
            renewal_stop: Some(renewal_stop),
            renewal_worker: Some(renewal_worker),
            listener_shutdown,
            listener_worker: Some(listener_worker),
            conservative_expiry,
            _tcp_retention: tcp_retention,
            _udp_sockets: udp_sockets,
        });

        // Core ownership and authentication are proven locally. Full relay and
        // DNS health remain false until an end-to-end WFP canary and UDP/DNS
        // runtime exist, so BrokerEngine cannot arm this partial data plane.
        Ok(ForwardingHealth {
            core_healthy: true,
            relay_healthy: false,
            dns_healthy: false,
            capabilities: initial_snapshot.capabilities,
        })
    }
}

impl ForwardingHealthProbe for WindowsTcpForwardingHealth {
    fn measure(
        &mut self,
        revision: u64,
        policy_digest: &str,
        ingress: &StrictProxyIngressSet,
    ) -> Result<ForwardingHealth> {
        self.activate(revision, policy_digest, ingress)
    }

    fn deactivate(&mut self) -> Result<()> {
        let Some(active) = self.active.take() else {
            return Ok(());
        };
        deactivate_active_runtime(active)
    }
}

fn deactivate_active_runtime(mut active: ActiveWindowsTcpRuntime) -> Result<()> {
    if let Some(stop) = active.renewal_stop.take() {
        let _ = stop.try_send(());
    }
    let renewal = join_runtime_worker(active.renewal_worker.take(), "endpoint lease renewal");
    let revoke = revoke_or_wait(&active.driver, &active.conservative_expiry);
    active.listener_shutdown.request();
    let listener = match active.listener_worker.take() {
        Some(worker) => join_listener(worker),
        None => Ok(()),
    };
    combine_runtime_cleanup(renewal, revoke, listener)
}

impl Drop for WindowsTcpForwardingHealth {
    fn drop(&mut self) {
        let _ = self.deactivate();
    }
}

fn build_socks_ingresses(ingress: &StrictProxyIngressSet) -> Result<Vec<Socks5ProxyIngress>> {
    ingress
        .entries
        .iter()
        .map(|entry| {
            Socks5ProxyIngress::new(
                entry.endpoint,
                entry.username.clone(),
                entry.password.clone(),
            )
        })
        .collect()
}

fn bind_udp_reservations() -> Result<[UdpSocket; 2]> {
    let v4 = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
        .context("bind strict UDP IPv4 reservation")?;
    let v6 = UdpSocket::bind(SocketAddrV6::new(Ipv6Addr::LOCALHOST, 0, 0, 0))
        .context("bind strict UDP IPv6 reservation")?;
    Ok([v4, v6])
}

fn udp_endpoint_v4(socket: &UdpSocket) -> Result<SocketAddrV4> {
    match socket.local_addr()? {
        SocketAddr::V4(endpoint)
            if endpoint.ip() == &Ipv4Addr::LOCALHOST && endpoint.port() != 0 =>
        {
            Ok(endpoint)
        }
        _ => bail!("strict UDP IPv4 reservation bound an unsafe endpoint"),
    }
}

fn udp_endpoint_v6(socket: &UdpSocket) -> Result<SocketAddrV6> {
    match socket.local_addr()? {
        SocketAddr::V6(endpoint)
            if endpoint.ip() == &Ipv6Addr::LOCALHOST && endpoint.port() != 0 =>
        {
            Ok(endpoint)
        }
        _ => bail!("strict UDP IPv6 reservation bound an unsafe endpoint"),
    }
}

fn probe_all_core_ingresses(
    ingresses: &[Socks5ProxyIngress],
    udp_endpoint: SocketAddrV4,
    generation: u64,
) -> Result<()> {
    let next = AtomicUsize::new(0);
    let failed = AtomicBool::new(false);
    let failure = Mutex::new(None::<String>);
    let worker_count = ingresses.len().min(MAX_CORE_PROBE_WORKERS);
    thread::scope(|scope| -> Result<()> {
        let mut workers = Vec::with_capacity(worker_count);
        for _ in 0..worker_count {
            workers.push(
                thread::Builder::new()
                    .name("flclash-strict-core-probe".into())
                    .stack_size(CORE_PROBE_THREAD_STACK_BYTES)
                    .spawn_scoped(scope, || loop {
                        if failed.load(Ordering::Acquire) {
                            break;
                        }
                        let index = next.fetch_add(1, Ordering::Relaxed);
                        let Some(ingress) = ingresses.get(index) else {
                            break;
                        };
                        let probe = (|| {
                            probe_socks5_authentication(ingress, CORE_PROBE_TIMEOUT)?;
                            probe_core_udp_health(
                                udp_endpoint,
                                generation,
                                ingress.username(),
                                ingress.password(),
                                random_nonce()?,
                                CORE_PROBE_TIMEOUT,
                            )
                        })();
                        if let Err(error) = probe {
                            failed.store(true, Ordering::Release);
                            if let Ok(mut slot) = failure.lock() {
                                *slot = Some(format!("{error:#}"));
                            }
                            break;
                        }
                    })
                    .context("start strict Core authentication probe")?,
            );
        }
        for worker in workers {
            worker
                .join()
                .map_err(|_| anyhow::anyhow!("strict Core authentication probe panicked"))?;
        }
        Ok(())
    })?;
    let failure = failure
        .into_inner()
        .map_err(|_| anyhow::anyhow!("strict Core probe result lock is poisoned"))?;
    if let Some(error) = failure {
        bail!("strict Core authentication probe failed: {error}");
    }
    Ok(())
}

fn spawn_listener<H>(
    pool: crate::WindowsTcpListenerPool<H>,
    shutdown: WindowsPipeShutdown,
    alive: &Arc<AtomicBool>,
) -> Result<JoinHandle<Result<WindowsTcpListenerReport>>>
where
    H: Fn(std::net::TcpStream, &WindowsPipeShutdown) -> Result<()> + Send + Sync + 'static,
{
    let alive = Arc::clone(alive);
    thread::Builder::new()
        .name("flclash-strict-tcp-listener".into())
        .stack_size(RUNTIME_THREAD_STACK_BYTES)
        .spawn(move || {
            let result = pool.run(shutdown);
            alive.store(false, Ordering::Release);
            result
        })
        .context("start strict TCP listener runtime")
}

#[allow(clippy::too_many_arguments)]
fn spawn_renewal(
    driver: Arc<Mutex<Box<dyn EndpointLeaseChannel>>>,
    lease: WindowsEndpointLease,
    plan: Arc<WindowsStrictTcpSessionPlan>,
    stop: Receiver<()>,
    listener_shutdown: WindowsPipeShutdown,
    listener_alive: Arc<AtomicBool>,
    conservative_expiry: Arc<Mutex<Instant>>,
) -> Result<JoinHandle<Result<()>>> {
    thread::Builder::new()
        .name("flclash-strict-lease-renewal".into())
        .stack_size(RUNTIME_THREAD_STACK_BYTES)
        .spawn(move || loop {
            match stop.recv_timeout(ENDPOINT_LEASE_RENEW_INTERVAL) {
                Ok(()) | Err(RecvTimeoutError::Disconnected) => return Ok(()),
                Err(RecvTimeoutError::Timeout) => {}
            }
            let renewal = (|| {
                if !listener_alive.load(Ordering::Acquire) {
                    bail!("strict TCP listener runtime exited");
                }
                plan.verify_core_listener_ownership()?;
                let snapshot = activate_lease(&driver, &lease, &conservative_expiry)?;
                let generation = snapshot
                    .endpoint_lease
                    .as_ref()
                    .map(|active| active.generation)
                    .ok_or_else(|| anyhow::anyhow!("strict driver omitted its renewed lease"))?;
                plan.advance_lease_generation(generation)?;
                Ok(())
            })();
            if let Err(renewal) = renewal {
                let cleanup = revoke_or_wait(&driver, &conservative_expiry);
                listener_shutdown.request();
                return match cleanup {
                    Ok(()) => Err(renewal.context("renew strict endpoint lease")),
                    Err(cleanup) => Err(anyhow::anyhow!(
                        "renew strict endpoint lease failed: {renewal:#}; fail-closed cleanup failed: {cleanup:#}"
                    )),
                };
            }
        })
        .context("start strict endpoint lease renewal runtime")
}

fn activate_lease(
    driver: &Arc<Mutex<Box<dyn EndpointLeaseChannel>>>,
    lease: &WindowsEndpointLease,
    conservative_expiry: &Arc<Mutex<Instant>>,
) -> Result<WindowsDriverPolicySnapshot> {
    let activation = driver
        .lock()
        .map_err(|_| anyhow::anyhow!("strict endpoint lease channel lock is poisoned"))?
        .activate(lease);
    // An IOCTL may have committed immediately before returning an error or a
    // failed attestation. Track a full TTL from observation so cleanup never
    // closes endpoints while such a lease could still be live.
    set_conservative_expiry(conservative_expiry, Instant::now() + ENDPOINT_LEASE_TTL)?;
    activation
}

fn revoke_or_wait(
    driver: &Arc<Mutex<Box<dyn EndpointLeaseChannel>>>,
    conservative_expiry: &Arc<Mutex<Instant>>,
) -> Result<()> {
    let revoke = driver
        .lock()
        .map_err(|_| anyhow::anyhow!("strict endpoint lease channel lock is poisoned"))
        .and_then(|driver| driver.revoke());
    if revoke.is_ok() {
        return Ok(());
    }
    let expiry = conservative_expiry
        .lock()
        .map(|value| *value)
        .unwrap_or_else(|_| Instant::now() + ENDPOINT_LEASE_TTL);
    while Instant::now() < expiry {
        thread::sleep(EXPIRY_WAIT_SLICE.min(expiry.saturating_duration_since(Instant::now())));
    }
    revoke.context("revoke strict endpoint lease before listener shutdown")
}

fn set_conservative_expiry(expiry: &Arc<Mutex<Instant>>, value: Instant) -> Result<()> {
    *expiry
        .lock()
        .map_err(|_| anyhow::anyhow!("strict endpoint lease expiry lock is poisoned"))? = value;
    Ok(())
}

fn random_nonce() -> Result<[u8; 16]> {
    let mut nonce = [0_u8; 16];
    // SAFETY: the system-preferred RNG ignores the algorithm handle and nonce
    // is a valid writable buffer for the supplied length.
    let status = unsafe {
        BCryptGenRandom(
            std::ptr::null_mut(),
            nonce.as_mut_ptr(),
            nonce.len() as u32,
            BCRYPT_USE_SYSTEM_PREFERRED_RNG,
        )
    };
    if status != 0 || nonce.iter().all(|byte| *byte == 0) {
        bail!("generate strict endpoint lease nonce failed");
    }
    Ok(nonce)
}

fn tcp_worker_count() -> usize {
    thread::available_parallelism()
        .map(|count| count.get())
        .unwrap_or(4)
        .clamp(2, MAX_TCP_WORKERS)
}

fn join_listener(worker: JoinHandle<Result<WindowsTcpListenerReport>>) -> Result<()> {
    worker
        .join()
        .map_err(|_| anyhow::anyhow!("strict TCP listener runtime panicked"))?
        .map(|_| ())
}

fn join_runtime_worker(worker: Option<JoinHandle<Result<()>>>, label: &str) -> Result<()> {
    match worker {
        None => Ok(()),
        Some(worker) => worker
            .join()
            .map_err(|_| anyhow::anyhow!("strict {label} runtime panicked"))?,
    }
}

fn combine_setup_failure(
    setup: anyhow::Error,
    cleanup: Result<()>,
    listener: Result<()>,
) -> anyhow::Error {
    let mut failures = vec![format!("setup failed: {setup:#}")];
    if let Err(error) = cleanup {
        failures.push(format!("lease cleanup failed: {error:#}"));
    }
    if let Err(error) = listener {
        failures.push(format!("listener cleanup failed: {error:#}"));
    }
    anyhow::anyhow!("strict TCP runtime setup failed: {}", failures.join("; "))
}

fn combine_runtime_cleanup(
    renewal: Result<()>,
    revoke: Result<()>,
    listener: Result<()>,
) -> Result<()> {
    let mut failures = Vec::new();
    if let Err(error) = renewal {
        failures.push(format!("renewal failed: {error:#}"));
    }
    if let Err(error) = revoke {
        failures.push(format!("lease revocation failed: {error:#}"));
    }
    if let Err(error) = listener {
        failures.push(format!("listener shutdown failed: {error:#}"));
    }
    if failures.is_empty() {
        Ok(())
    } else {
        bail!("strict TCP runtime cleanup failed: {}", failures.join("; "))
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::WindowsDriverEndpointLeaseSnapshot;
    use flclash_strict_contract::StrictCapability;

    struct FakeLeaseChannel {
        generation: AtomicUsize,
        revocations: Arc<AtomicUsize>,
        fail_revoke: bool,
    }

    impl EndpointLeaseChannel for FakeLeaseChannel {
        fn activate(&self, _lease: &WindowsEndpointLease) -> Result<WindowsDriverPolicySnapshot> {
            let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
            Ok(WindowsDriverPolicySnapshot {
                driver_build_id: Some("1".repeat(32)),
                revision: Some(7),
                policy_digest: Some("ab".repeat(32)),
                rule_count: 1,
                generation: generation as u64,
                loaded: true,
                capabilities: BTreeSet::from([StrictCapability::PersistentFailClosed]),
                endpoint_lease: Some(WindowsDriverEndpointLeaseSnapshot {
                    generation: generation as u64,
                    remaining_millis: ENDPOINT_LEASE_TTL.as_millis() as u32,
                    nonce: [0x11; 16],
                }),
                datagram_path_active: false,
                datagram_health: Default::default(),
            })
        }

        fn revoke(&self) -> Result<()> {
            self.revocations.fetch_add(1, Ordering::SeqCst);
            if self.fail_revoke {
                bail!("injected revoke failure");
            }
            Ok(())
        }
    }

    #[test]
    fn successful_revocation_completes_without_waiting_for_ttl() {
        let revocations = Arc::new(AtomicUsize::new(0));
        let driver: Arc<Mutex<Box<dyn EndpointLeaseChannel>>> =
            Arc::new(Mutex::new(Box::new(FakeLeaseChannel {
                generation: AtomicUsize::new(0),
                revocations: Arc::clone(&revocations),
                fail_revoke: false,
            })));
        let expiry = Arc::new(Mutex::new(Instant::now() + Duration::from_secs(2)));
        let started = Instant::now();

        revoke_or_wait(&driver, &expiry).unwrap();

        assert_eq!(revocations.load(Ordering::SeqCst), 1);
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn failed_revocation_waits_for_conservative_expiry() {
        let driver: Arc<Mutex<Box<dyn EndpointLeaseChannel>>> =
            Arc::new(Mutex::new(Box::new(FakeLeaseChannel {
                generation: AtomicUsize::new(0),
                revocations: Arc::new(AtomicUsize::new(0)),
                fail_revoke: true,
            })));
        let wait = Duration::from_millis(80);
        let expiry = Arc::new(Mutex::new(Instant::now() + wait));
        let started = Instant::now();

        assert!(revoke_or_wait(&driver, &expiry).is_err());

        assert!(started.elapsed() >= wait);
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn udp_reservations_are_exact_loopback_endpoints() {
        let sockets = bind_udp_reservations().unwrap();
        assert_eq!(
            udp_endpoint_v4(&sockets[0]).unwrap().ip(),
            &Ipv4Addr::LOCALHOST
        );
        assert_eq!(
            udp_endpoint_v6(&sockets[1]).unwrap().ip(),
            &Ipv6Addr::LOCALHOST
        );
    }

    #[test]
    fn runtime_revokes_admission_before_listener_shutdown() {
        let revocations = Arc::new(AtomicUsize::new(0));
        let driver: Arc<Mutex<Box<dyn EndpointLeaseChannel>>> =
            Arc::new(Mutex::new(Box::new(FakeLeaseChannel {
                generation: AtomicUsize::new(0),
                revocations: Arc::clone(&revocations),
                fail_revoke: false,
            })));
        let listener_shutdown = WindowsPipeShutdown::new();
        let observed_shutdown = listener_shutdown.clone();
        let listener_revocations = Arc::clone(&revocations);
        let listener_worker = thread::spawn(move || {
            while !observed_shutdown.is_requested() {
                thread::yield_now();
            }
            if listener_revocations.load(Ordering::SeqCst) != 1 {
                bail!("listener stopped before endpoint admission was revoked");
            }
            Ok(WindowsTcpListenerReport::default())
        });
        let active = ActiveWindowsTcpRuntime {
            driver,
            renewal_stop: None,
            renewal_worker: None,
            listener_shutdown,
            listener_worker: Some(listener_worker),
            conservative_expiry: Arc::new(Mutex::new(Instant::now())),
            _tcp_retention: WindowsTcpListenerBinding::bind()
                .unwrap()
                .retention_handles()
                .unwrap(),
            _udp_sockets: bind_udp_reservations().unwrap(),
        };

        deactivate_active_runtime(active).unwrap();
        assert_eq!(revocations.load(Ordering::SeqCst), 1);
    }
}
