use std::collections::BTreeSet;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{
    BrokerProof, StrictAction, StrictCapability, StrictPolicyBundle, StrictProxyIngressSet,
    MAX_STRICT_APPLICATIONS, STRICT_PROTOCOL_VERSION,
};
use serde::{Deserialize, Serialize};

mod dispatch;
mod ipc_auth;
mod package_manifest;
mod planned_wfp_backend;
mod recovery_file;
mod redirect_context;
mod session_registry;
mod socks_probe;
#[cfg(any(test, feature = "production-host"))]
mod strict_udp_frame;
mod wfp_plan;
#[cfg(all(windows, any(test, feature = "production-host")))]
mod windows_core_udp_data;
#[cfg(all(windows, any(test, feature = "production-host")))]
mod windows_core_udp_health;
#[cfg(all(windows, any(test, feature = "production-host")))]
mod windows_datagram_wire;
#[cfg(windows)]
mod windows_driver_channel;
#[cfg(windows)]
mod windows_driver_service;
#[cfg(all(windows, feature = "production-host"))]
mod windows_host;
#[cfg(windows)]
mod windows_identity;
#[cfg(windows)]
mod windows_pipe;
#[cfg(windows)]
mod windows_pipe_pool;
#[cfg(windows)]
mod windows_recovery_acl;
#[cfg(windows)]
mod windows_redirect_socket;
#[cfg(windows)]
mod windows_scm;
#[cfg(windows)]
mod windows_session;
#[cfg(windows)]
mod windows_tcp_listener_pool;
#[cfg(windows)]
mod windows_tcp_owner;
#[cfg(windows)]
mod windows_tcp_relay;
#[cfg(all(windows, feature = "production-host"))]
mod windows_tcp_runtime;
#[cfg(windows)]
mod windows_tcp_session;
#[cfg(windows)]
mod windows_wfp_control;
#[cfg(windows)]
mod windows_wfp_engine;

pub use dispatch::{BrokerDispatcher, ForwardingHealthProbe};
pub use ipc_auth::{AuthorizedBrokerRequest, BrokerAuthenticator, ClientPrincipal, ClientRole};
pub use package_manifest::StrictPackageManifest;
pub use planned_wfp_backend::{PlannedWfpBackend, WfpControlPlane, WfpControlSnapshot};
pub use recovery_file::FileRecoveryStore;
pub use redirect_context::{
    parse_strict_redirect_context, StrictRedirectContext, StrictRedirectLeaseBinding,
    StrictRedirectTransport,
};
pub use session_registry::{BrokerSessionRegistry, BrokerSessionResource};
pub use socks_probe::{
    establish_socks5_connect, probe_socks5_authentication, probe_socks5_connect,
    Socks5ConnectTarget, Socks5ProxyIngress,
};
#[cfg(any(test, feature = "production-host"))]
pub use strict_udp_frame::{
    strict_udp_data_frame_key_id, StrictUdpDataAuthenticator, StrictUdpDataDirection,
    StrictUdpDataFrame, StrictUdpReplayWindow, STRICT_UDP_DATA_HEADER_BYTES,
    STRICT_UDP_DATA_MAX_FRAME_BYTES, STRICT_UDP_DATA_MAX_PAYLOAD_BYTES,
};
pub use wfp_plan::{
    DriverIdentityRule, PlanInstallStep, PlanRemoveStep, WfpCallout, WfpFilterLifetime,
    WfpFilterSpec, WfpLayer, WfpObjectKey, WfpPolicyPlan,
};
#[cfg(all(windows, any(test, feature = "production-host")))]
pub use windows_core_udp_data::{
    StrictCoreUdpReply, StrictCoreUdpTransport, STRICT_CORE_UDP_MAX_ASSOCIATIONS,
};
#[cfg(all(windows, any(test, feature = "production-host")))]
pub use windows_datagram_wire::{
    StrictDriverDatagramBatch, StrictDriverDatagramBatchBuilder, StrictDriverDatagramBatchKind,
    StrictDriverDatagramFlags, StrictDriverDatagramLeaseIdentity, StrictDriverDatagramRecord,
    StrictDriverDatagramRecords, STRICT_DRIVER_DATAGRAM_BATCH_HEADER_BYTES,
    STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES, STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES,
    STRICT_DRIVER_DATAGRAM_MAX_RECORDS, STRICT_DRIVER_DATAGRAM_RECORD_HEADER_BYTES,
};
#[cfg(windows)]
pub use windows_driver_channel::{
    WindowsDriverIoctlDeadline, WindowsEndpointLease, WindowsIoctlDriverChannel,
    WindowsSharedIoctlDriverChannel,
};
#[cfg(all(windows, feature = "production-host"))]
pub use windows_host::{run_windows_strict_broker_service, WindowsStrictBrokerPaths};
#[cfg(windows)]
pub use windows_identity::{
    inspect_windows_driver, inspect_windows_executable, verify_windows_driver,
    verify_windows_packaged_agent_image, verify_windows_packaged_agent_process,
    verify_windows_packaged_agent_process_with_image, verify_windows_packaged_core_image,
    verify_windows_packaged_core_process, verify_windows_packaged_core_process_with_image,
    verify_windows_packaged_driver, WindowsAgentImageTrustLease, WindowsAgentProcessTrustLease,
    WindowsCoreImageTrustLease, WindowsCoreProcessTrustLease, WindowsDriverTrustLease,
    WindowsIdentityLease, WindowsIdentityVerifier, WindowsVerifiedIdentity,
};
#[cfg(windows)]
pub use windows_pipe::{
    current_process_user_sid, exchange_windows_activation_for_agent,
    exchange_windows_pipe_for_agent, generate_windows_broker_session_pipe_name,
    WindowsAuthenticatedRequest, WindowsBrokerActivationAttempt,
    WindowsBrokerActivationPipeInstance, WindowsNamedPipeInstance, WindowsPipeDeadlines,
    WindowsVerifiedActivationRequest,
};
#[cfg(windows)]
pub use windows_pipe_pool::{
    WindowsNamedPipeWorkerPool, WindowsPipeServiceReport, WindowsPipeShutdown,
};
#[cfg(windows)]
pub use windows_recovery_acl::WindowsRecoveryAclVerifier;
#[cfg(windows)]
pub use windows_redirect_socket::{
    connect_windows_redirected_outbound, query_windows_redirect_socket,
    WindowsRedirectSocketMetadata,
};
#[cfg(windows)]
pub use windows_scm::{run_windows_scm_service, WindowsScmContext};
#[cfg(windows)]
pub use windows_session::WindowsBrokerPipeSession;
#[cfg(windows)]
pub use windows_tcp_listener_pool::{
    WindowsTcpListenerBinding, WindowsTcpListenerEndpoints, WindowsTcpListenerPool,
    WindowsTcpListenerReport,
};
#[cfg(windows)]
pub use windows_tcp_owner::{
    verify_windows_packaged_core_ingress_set, verify_windows_packaged_core_ingress_set_with_image,
    verify_windows_packaged_core_listener_owner,
    verify_windows_packaged_core_listener_owner_with_image,
    verify_windows_packaged_core_listener_set,
    verify_windows_packaged_core_listener_set_with_image, windows_tcp_listener_owner_pid,
    windows_tcp_listener_owner_pid_for_all, windows_udp_listener_owner_pid,
    windows_udp_listener_owner_pid_for_all, WindowsCoreListenerTrustLease,
};
#[cfg(windows)]
pub use windows_tcp_relay::{
    relay_windows_tcp_bidirectional, WindowsTcpRelayLimits, WindowsTcpRelayReport,
};
#[cfg(windows)]
pub use windows_tcp_session::{handle_windows_strict_tcp_connection, WindowsStrictTcpSessionPlan};
#[cfg(windows)]
pub use windows_wfp_control::{
    WindowsDriverEndpointLeaseSnapshot, WindowsDriverPolicyChannel, WindowsDriverPolicySnapshot,
    WindowsWfpControl, WindowsWfpFilterInventory, WindowsWfpFilterStore,
};
#[cfg(windows)]
pub use windows_wfp_engine::WindowsWfpEngineStore;

pub const MAX_VERIFIED_APP_ID_BYTES: usize = 4 * 1024;
const MAX_VERIFIED_POLICY_APP_ID_BYTES: usize = 2 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedApplicationAppIds {
    identity_id: String,
    app_ids: Vec<Vec<u8>>,
}

impl VerifiedApplicationAppIds {
    pub fn new(identity_id: impl Into<String>, app_ids: Vec<Vec<u8>>) -> Result<Self> {
        let identity_id = identity_id.into();
        if identity_id.is_empty() || identity_id.len() > 64 {
            bail!("verified application identity ID is invalid");
        }
        if app_ids.is_empty()
            || app_ids
                .iter()
                .any(|value| value.is_empty() || value.len() > MAX_VERIFIED_APP_ID_BYTES)
        {
            bail!("verified WFP application identity is empty or oversized");
        }
        Ok(Self {
            identity_id,
            app_ids,
        })
    }

    pub fn identity_id(&self) -> &str {
        &self.identity_id
    }

    pub fn app_ids(&self) -> &[Vec<u8>] {
        &self.app_ids
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifiedPolicyAppIds {
    applications: Vec<VerifiedApplicationAppIds>,
    app_id_count: usize,
}

impl VerifiedPolicyAppIds {
    pub fn new(
        policy: &StrictPolicyBundle,
        applications: Vec<VerifiedApplicationAppIds>,
    ) -> Result<Self> {
        policy.validate()?;
        if applications.len() != policy.entries.len() {
            bail!("verified application identities do not cover the strict policy");
        }
        let mut app_id_count = 0_usize;
        let mut total_bytes = 0_usize;
        for (expected, verified) in policy.entries.iter().zip(&applications) {
            if verified.identity_id != expected.identity.identity_id
                || verified.app_ids.len() != 1 + expected.identity.verified_children.len()
            {
                bail!("verified application identities do not match the strict policy");
            }
            app_id_count = app_id_count
                .checked_add(verified.app_ids.len())
                .ok_or_else(|| anyhow::anyhow!("verified application identity count overflow"))?;
            for app_id in &verified.app_ids {
                total_bytes = total_bytes.checked_add(app_id.len()).ok_or_else(|| {
                    anyhow::anyhow!("verified application identity size overflow")
                })?;
            }
        }
        if total_bytes > MAX_VERIFIED_POLICY_APP_ID_BYTES {
            bail!("verified WFP application identities exceed their total size limit");
        }
        let mut sorted_ids: Vec<&[u8]> = applications
            .iter()
            .flat_map(|application| application.app_ids.iter().map(Vec::as_slice))
            .collect();
        sorted_ids.sort_unstable();
        if sorted_ids.windows(2).any(|pair| pair[0] == pair[1]) {
            bail!("verified WFP application identity is assigned more than once");
        }
        Ok(Self {
            applications,
            app_id_count,
        })
    }

    pub fn applications(&self) -> &[VerifiedApplicationAppIds] {
        &self.applications
    }

    pub fn application_count(&self) -> usize {
        self.applications.len()
    }

    pub fn app_id_count(&self) -> usize {
        self.app_id_count
    }
}

pub struct IdentityVerification<L> {
    app_ids: VerifiedPolicyAppIds,
    lease: L,
}

impl<L> IdentityVerification<L> {
    pub fn new(app_ids: VerifiedPolicyAppIds, lease: L) -> Self {
        Self { app_ids, lease }
    }

    pub fn app_ids(&self) -> &VerifiedPolicyAppIds {
        &self.app_ids
    }

    pub fn lease(&self) -> &L {
        &self.lease
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum BrokerPhase {
    Disabled,
    Preparing,
    Blocking,
    Armed,
    Recovering,
    Disabling,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecoveryMarker {
    pub protocol: u32,
    pub revision: u64,
    pub policy_digest: String,
    pub filter_generation: u64,
    pub phase: BrokerPhase,
    pub policy: StrictPolicyBundle,
}

impl RecoveryMarker {
    pub fn preparing(policy: StrictPolicyBundle, policy_digest: String) -> Self {
        Self {
            protocol: STRICT_PROTOCOL_VERSION,
            revision: policy.revision,
            policy_digest,
            filter_generation: 0,
            phase: BrokerPhase::Preparing,
            policy,
        }
    }

    pub fn blocking(
        policy: StrictPolicyBundle,
        policy_digest: String,
        filter_generation: u64,
    ) -> Self {
        Self {
            protocol: STRICT_PROTOCOL_VERSION,
            revision: policy.revision,
            policy_digest,
            filter_generation,
            phase: BrokerPhase::Blocking,
            policy,
        }
    }

    pub fn disabling(
        policy: StrictPolicyBundle,
        policy_digest: String,
        filter_generation: u64,
    ) -> Self {
        Self {
            protocol: STRICT_PROTOCOL_VERSION,
            revision: policy.revision,
            policy_digest,
            filter_generation,
            phase: BrokerPhase::Disabling,
            policy,
        }
    }

    fn with_phase(&self, phase: BrokerPhase, filter_generation: u64) -> Self {
        let mut marker = self.clone();
        marker.phase = phase;
        marker.filter_generation = filter_generation;
        marker
    }

    pub fn validate(&self) -> Result<()> {
        if self.protocol != STRICT_PROTOCOL_VERSION {
            bail!("unsupported strict recovery protocol");
        }
        if self.phase == BrokerPhase::Disabled {
            bail!("a disabled strict policy cannot have a recovery marker");
        }
        self.policy.validate()?;
        if self.policy.revision != self.revision {
            bail!("strict recovery revision does not match its policy");
        }
        if !self
            .policy
            .canonical_digest()?
            .eq_ignore_ascii_case(&self.policy_digest)
        {
            bail!("strict recovery digest does not match its policy");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RecoveryRecord {
    pub high_watermark: u64,
    pub marker: Option<RecoveryMarker>,
}

pub trait RecoveryStore {
    /// Loading and persisting must use a private, integrity-protected location.
    fn load(&mut self) -> Result<RecoveryRecord>;

    /// Persists the marker atomically and advances, but never lowers, the high watermark.
    fn persist(&mut self, marker: &RecoveryMarker) -> Result<()>;

    /// Clears only the active marker. The revision high watermark must survive.
    fn clear_marker(&mut self) -> Result<()>;
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BackendSnapshot {
    pub revision: Option<u64>,
    pub policy_digest: Option<String>,
    pub filter_generation: u64,
    pub guard_filters_installed: bool,
    pub redirect_filters_installed: bool,
    pub capabilities: BTreeSet<StrictCapability>,
}

pub trait FilterBackend {
    /// Each mutation must be one atomic backend transaction owned by the FlClashX provider.
    fn install_guards(
        &mut self,
        policy: &StrictPolicyBundle,
        verified_app_ids: &VerifiedPolicyAppIds,
        digest: &str,
    ) -> Result<()>;
    fn install_redirects(
        &mut self,
        policy: &StrictPolicyBundle,
        verified_app_ids: &VerifiedPolicyAppIds,
        digest: &str,
    ) -> Result<()>;
    fn remove_redirects(&mut self) -> Result<()>;
    fn remove_guards(&mut self) -> Result<()>;
    fn snapshot(&mut self) -> Result<BackendSnapshot>;
}

pub trait IdentityVerifier {
    type VerificationLease;

    /// Implementations must reopen the executable and independently verify App-ID and signer data.
    /// The returned lease must keep every verified executable replacement-locked.
    fn verify(
        &mut self,
        policy: &StrictPolicyBundle,
    ) -> Result<IdentityVerification<Self::VerificationLease>>;
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ForwardingHealth {
    pub core_healthy: bool,
    pub relay_healthy: bool,
    pub dns_healthy: bool,
    pub capabilities: BTreeSet<StrictCapability>,
}

impl ForwardingHealth {
    fn is_complete_for(&self, policy: &StrictPolicyBundle) -> bool {
        let required = required_capabilities(policy);
        self.core_healthy
            && self.relay_healthy
            && self.dns_healthy
            && required.is_subset(&self.capabilities)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrokerStatus {
    pub phase: BrokerPhase,
    pub proof: BrokerProof,
}

pub struct BrokerEngine<B, S, V: IdentityVerifier> {
    backend: B,
    store: S,
    verifier: V,
    current_marker: Option<RecoveryMarker>,
    high_watermark: u64,
    store_loaded: bool,
    phase: BrokerPhase,
    forwarding_health: ForwardingHealth,
    verification_lease: Option<IdentityVerification<V::VerificationLease>>,
}

impl<B, S, V> BrokerEngine<B, S, V>
where
    B: FilterBackend,
    S: RecoveryStore,
    V: IdentityVerifier,
{
    pub fn new(backend: B, store: S, verifier: V) -> Self {
        Self {
            backend,
            store,
            verifier,
            current_marker: None,
            high_watermark: 0,
            store_loaded: false,
            phase: BrokerPhase::Disabled,
            forwarding_health: ForwardingHealth::default(),
            verification_lease: None,
        }
    }

    pub fn backend(&self) -> &B {
        &self.backend
    }

    pub fn backend_mut(&mut self) -> &mut B {
        &mut self.backend
    }

    pub fn store(&self) -> &S {
        &self.store
    }

    pub fn verifier(&self) -> &V {
        &self.verifier
    }

    pub fn prepare(&mut self, policy: StrictPolicyBundle) -> Result<BrokerStatus> {
        self.load_store_once()?;
        if self.current_marker.is_some() {
            bail!("strict policy recovery or disable is required before prepare");
        }
        policy.validate()?;
        if policy.entries.len() > MAX_STRICT_APPLICATIONS {
            bail!("strict policy application limit exceeded");
        }
        if policy.revision <= self.high_watermark {
            bail!("strict policy revision was already used");
        }

        let verification = self.verifier.verify(&policy)?;
        let digest = policy.canonical_digest()?;
        let preparing = RecoveryMarker::preparing(policy, digest);
        self.store.persist(&preparing)?;
        self.verification_lease = Some(verification);
        self.high_watermark = preparing.revision;
        self.current_marker = Some(preparing.clone());
        self.phase = BrokerPhase::Preparing;
        self.forwarding_health = ForwardingHealth::default();

        self.backend
            .install_guards(
                &preparing.policy,
                self.verification_lease
                    .as_ref()
                    .expect("verification is retained before filter installation")
                    .app_ids(),
                &preparing.policy_digest,
            )
            .context("install strict guard filters")?;
        let snapshot = self.backend.snapshot()?;
        validate_snapshot(&snapshot, &preparing, true, false)?;

        let next_phase = if has_proxy_entries(&preparing.policy) {
            BrokerPhase::Blocking
        } else {
            BrokerPhase::Armed
        };
        let blocking = preparing.with_phase(next_phase, snapshot.filter_generation);
        self.current_marker = Some(blocking.clone());
        self.phase = next_phase;
        self.store.persist(&blocking)?;
        self.status_from_snapshot(snapshot)
    }

    pub fn commit(
        &mut self,
        revision: u64,
        policy_digest: &str,
        health: ForwardingHealth,
    ) -> Result<BrokerStatus> {
        let marker = self.match_current(revision, policy_digest)?.clone();
        if !has_proxy_entries(&marker.policy) {
            bail!("a block-only strict policy does not require a forwarding commit");
        }
        if self.phase != BrokerPhase::Blocking {
            bail!("strict policy is not in the blocking commit phase");
        }
        if !health.is_complete_for(&marker.policy) {
            bail!("strict forwarding capability proof is incomplete");
        }

        if let Err(error) = self.backend.install_redirects(
            &marker.policy,
            self.verification_lease
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("strict identity verification lease is missing"))?
                .app_ids(),
            &marker.policy_digest,
        ) {
            if let Err(rollback_error) = self.rollback_redirects(&marker) {
                bail!(
                    "install strict redirect filters failed: {error:#}; fail-closed rollback failed: {rollback_error:#}"
                );
            }
            return Err(error).context("install strict redirect filters");
        }
        let snapshot = self.backend.snapshot()?;
        if let Err(error) = validate_snapshot(&snapshot, &marker, true, true) {
            if let Err(rollback_error) = self.rollback_redirects(&marker) {
                bail!(
                    "strict redirect verification failed: {error:#}; fail-closed rollback failed: {rollback_error:#}"
                );
            }
            return Err(error);
        }
        let required = required_capabilities(&marker.policy);
        if !required.is_subset(&snapshot.capabilities) {
            if let Err(rollback_error) = self.rollback_redirects(&marker) {
                bail!(
                    "strict backend capability proof is incomplete; fail-closed rollback failed: {rollback_error:#}"
                );
            }
            bail!("strict backend capability proof is incomplete");
        }

        let armed = marker.with_phase(BrokerPhase::Armed, snapshot.filter_generation);
        if let Err(error) = self.store.persist(&armed) {
            if let Err(rollback_error) = self.rollback_redirects(&marker) {
                bail!(
                    "persist armed strict recovery marker failed: {error:#}; fail-closed rollback failed: {rollback_error:#}"
                );
            }
            return Err(error).context("persist armed strict recovery marker");
        }
        self.current_marker = Some(armed);
        self.phase = BrokerPhase::Armed;
        self.forwarding_health = health;
        self.status_from_snapshot(snapshot)
    }

    pub(crate) fn validate_forwarding_ingress(
        &self,
        revision: u64,
        policy_digest: &str,
        ingress: &StrictProxyIngressSet,
    ) -> Result<()> {
        let marker = self.match_current(revision, policy_digest)?;
        if self.phase != BrokerPhase::Blocking {
            bail!("strict policy is not accepting a forwarding commit");
        }
        ingress.validate()?;

        let expected_groups: BTreeSet<&str> = marker
            .policy
            .entries
            .iter()
            .filter(|entry| entry.action == StrictAction::Proxy)
            .filter_map(|entry| entry.target_group.as_deref())
            .collect();
        if expected_groups.len() != ingress.entries.len()
            || expected_groups
                .iter()
                .zip(&ingress.entries)
                .any(|(expected, actual)| **expected != actual.target_group)
        {
            bail!("strict proxy ingresses do not match the prepared policy target groups");
        }
        Ok(())
    }

    pub fn status(&mut self) -> Result<BrokerStatus> {
        let snapshot = self.backend.snapshot()?;
        self.status_from_snapshot(snapshot)
    }

    pub fn disable(&mut self, revision: u64) -> Result<BrokerStatus> {
        let marker = self
            .current_marker
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("strict policy is not active"))?
            .clone();
        if marker.revision != revision {
            bail!("strict disable revision does not match the active policy");
        }
        let disabling = marker.with_phase(BrokerPhase::Disabling, marker.filter_generation);
        self.store.persist(&disabling)?;
        self.current_marker = Some(disabling.clone());
        self.phase = BrokerPhase::Recovering;
        self.forwarding_health = ForwardingHealth::default();

        self.complete_disable(&disabling)
    }

    pub fn force_blocking(&mut self, revision: u64) -> Result<BrokerStatus> {
        let marker = self
            .current_marker
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("strict policy is not active"))?
            .clone();
        if marker.revision != revision {
            bail!("strict force-blocking revision does not match the active policy");
        }

        self.backend.remove_redirects()?;
        let snapshot = self.backend.snapshot()?;
        validate_snapshot(&snapshot, &marker, true, false)?;
        let next_phase = if has_proxy_entries(&marker.policy) {
            BrokerPhase::Blocking
        } else {
            BrokerPhase::Armed
        };
        self.phase = next_phase;
        self.forwarding_health = ForwardingHealth::default();
        let blocking = marker.with_phase(next_phase, snapshot.filter_generation);
        self.store.persist(&blocking)?;
        self.current_marker = Some(blocking);
        self.status_from_snapshot(snapshot)
    }

    /// Runtime/session teardown uses the active recovery marker rather than an
    /// Agent-supplied revision. With no active policy this remains a read-only
    /// status check, which makes repeated shutdown cleanup idempotent.
    pub fn force_blocking_if_active(&mut self) -> Result<BrokerStatus> {
        let Some(revision) = self.current_marker.as_ref().map(|marker| marker.revision) else {
            return self.status();
        };
        self.force_blocking(revision)
    }

    pub fn recover(&mut self) -> Result<BrokerStatus> {
        let record = self.store.load()?;
        self.store_loaded = true;
        self.high_watermark = record.high_watermark;
        let mut snapshot = self.backend.snapshot()?;

        let Some(marker) = record.marker else {
            if snapshot.guard_filters_installed
                || snapshot.redirect_filters_installed
                || snapshot.revision.is_some()
                || snapshot.policy_digest.is_some()
            {
                bail!("orphaned strict backend state requires operator recovery");
            }
            self.current_marker = None;
            self.phase = BrokerPhase::Disabled;
            return self.status_from_snapshot(snapshot);
        };
        marker.validate()?;
        if record.high_watermark < marker.revision {
            bail!("strict recovery high watermark is inconsistent");
        }
        self.current_marker = Some(marker.clone());
        self.phase = BrokerPhase::Recovering;
        self.forwarding_health = ForwardingHealth::default();

        if marker.phase == BrokerPhase::Disabling {
            return self.complete_disable(&marker);
        }

        let verification = self.verifier.verify(&marker.policy)?;
        self.verification_lease = Some(verification);
        if snapshot.redirect_filters_installed {
            self.backend.remove_redirects()?;
            snapshot = self.backend.snapshot()?;
            if snapshot.redirect_filters_installed {
                bail!("strict redirect filters survived recovery removal");
            }
        }
        // Replacing guards is intentionally idempotent. It rebinds an enumerated persistent
        // filter set to the freshly verified App-IDs and re-uploads the immutable driver snapshot.
        self.backend.install_guards(
            &marker.policy,
            self.verification_lease
                .as_ref()
                .expect("recovery retains verification before filter installation")
                .app_ids(),
            &marker.policy_digest,
        )?;
        snapshot = self.backend.snapshot()?;
        validate_snapshot(&snapshot, &marker, true, false)?;

        let recovered_phase = if has_proxy_entries(&marker.policy) {
            BrokerPhase::Blocking
        } else {
            BrokerPhase::Armed
        };
        let recovered = marker.with_phase(recovered_phase, snapshot.filter_generation);
        self.store.persist(&recovered)?;
        self.current_marker = Some(recovered);
        self.phase = recovered_phase;
        self.status_from_snapshot(snapshot)
    }

    fn load_store_once(&mut self) -> Result<()> {
        if self.store_loaded {
            return Ok(());
        }
        let record = self.store.load()?;
        if record.marker.is_some() {
            bail!("strict recovery marker must be recovered before prepare");
        }
        self.high_watermark = record.high_watermark;
        self.store_loaded = true;
        Ok(())
    }

    fn match_current(&self, revision: u64, policy_digest: &str) -> Result<&RecoveryMarker> {
        let marker = self
            .current_marker
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("strict policy is not prepared"))?;
        if marker.revision != revision || !marker.policy_digest.eq_ignore_ascii_case(policy_digest)
        {
            bail!("strict commit does not match the prepared policy");
        }
        Ok(marker)
    }

    fn complete_disable(&mut self, marker: &RecoveryMarker) -> Result<BrokerStatus> {
        self.backend.remove_redirects()?;
        let mut snapshot = self.backend.snapshot()?;
        if snapshot.redirect_filters_installed {
            bail!("strict redirect filters remain during disable");
        }

        if snapshot.guard_filters_installed {
            validate_snapshot(&snapshot, marker, true, false)?;
            self.backend.remove_guards()?;
            snapshot = self.backend.snapshot()?;
        }
        if snapshot.guard_filters_installed || snapshot.redirect_filters_installed {
            bail!("strict filters remain after disable");
        }
        self.store.clear_marker()?;
        self.current_marker = None;
        self.verification_lease = None;
        self.phase = BrokerPhase::Disabled;
        self.forwarding_health = ForwardingHealth::default();
        self.status_from_snapshot(snapshot)
    }

    fn rollback_redirects(&mut self, marker: &RecoveryMarker) -> Result<()> {
        self.phase = BrokerPhase::Blocking;
        self.forwarding_health = ForwardingHealth::default();
        self.backend
            .remove_redirects()
            .context("remove redirects during fail-closed rollback")?;
        let snapshot = self.backend.snapshot()?;
        validate_snapshot(&snapshot, marker, true, false)?;
        let blocking = marker.with_phase(BrokerPhase::Blocking, snapshot.filter_generation);
        self.store.persist(&blocking)?;
        self.current_marker = Some(blocking);
        Ok(())
    }

    fn status_from_snapshot(&self, snapshot: BackendSnapshot) -> Result<BrokerStatus> {
        let marker = self.current_marker.as_ref();
        let revision = marker
            .map(|value| value.revision)
            .or(snapshot.revision)
            .unwrap_or(0);
        let policy_digest = marker
            .map(|value| value.policy_digest.clone())
            .or(snapshot.policy_digest.clone())
            .unwrap_or_else(|| "0".repeat(64));

        let capabilities =
            if self.phase == BrokerPhase::Armed && snapshot.redirect_filters_installed {
                snapshot
                    .capabilities
                    .intersection(&self.forwarding_health.capabilities)
                    .copied()
                    .collect()
            } else {
                snapshot
                    .capabilities
                    .intersection(&StrictCapability::required_for_block_only())
                    .copied()
                    .collect()
            };
        Ok(BrokerStatus {
            phase: self.phase,
            proof: BrokerProof {
                revision,
                policy_digest,
                filter_generation: snapshot.filter_generation,
                capabilities,
                guard_filters_installed: snapshot.guard_filters_installed,
                recovery_marker_present: self.current_marker.is_some(),
                core_healthy: self.phase == BrokerPhase::Armed
                    && self.forwarding_health.core_healthy,
                relay_healthy: self.phase == BrokerPhase::Armed
                    && self.forwarding_health.relay_healthy,
                dns_healthy: self.phase == BrokerPhase::Armed && self.forwarding_health.dns_healthy,
            },
        })
    }
}

fn required_capabilities(policy: &StrictPolicyBundle) -> BTreeSet<StrictCapability> {
    if has_proxy_entries(policy) {
        StrictCapability::required_for_proxy()
    } else {
        StrictCapability::required_for_block_only()
    }
}

fn has_proxy_entries(policy: &StrictPolicyBundle) -> bool {
    policy
        .entries
        .iter()
        .any(|entry| entry.action == flclash_strict_contract::StrictAction::Proxy)
}

fn validate_snapshot(
    snapshot: &BackendSnapshot,
    marker: &RecoveryMarker,
    expect_guards: bool,
    expect_redirects: bool,
) -> Result<()> {
    if snapshot.revision != Some(marker.revision)
        || snapshot
            .policy_digest
            .as_deref()
            .is_none_or(|digest| !digest.eq_ignore_ascii_case(&marker.policy_digest))
    {
        bail!("strict backend snapshot does not match the recovery marker");
    }
    if snapshot.guard_filters_installed != expect_guards {
        bail!("strict backend guard state does not match the requested phase");
    }
    if snapshot.redirect_filters_installed != expect_redirects {
        bail!("strict backend redirect state does not match the requested phase");
    }
    Ok(())
}
