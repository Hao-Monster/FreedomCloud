use std::collections::BTreeSet;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{
    BrokerProof, StrictCapability, StrictPolicyBundle, MAX_STRICT_APPLICATIONS,
    STRICT_PROTOCOL_VERSION,
};
use serde::{Deserialize, Serialize};

mod ipc_auth;
mod recovery_file;
#[cfg(windows)]
mod windows_pipe;

pub use ipc_auth::{AuthorizedBrokerRequest, BrokerAuthenticator, ClientPrincipal, ClientRole};
pub use recovery_file::FileRecoveryStore;
#[cfg(windows)]
pub use windows_pipe::{
    connect_windows_pipe_for_agent, current_process_user_sid, WindowsAuthenticatedRequest,
    WindowsNamedPipeInstance,
};

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
    fn install_guards(&mut self, policy: &StrictPolicyBundle, digest: &str) -> Result<()>;
    fn install_redirects(&mut self, policy: &StrictPolicyBundle, digest: &str) -> Result<()>;
    fn remove_redirects(&mut self) -> Result<()>;
    fn remove_guards(&mut self) -> Result<()>;
    fn snapshot(&mut self) -> Result<BackendSnapshot>;
}

pub trait IdentityVerifier {
    /// Implementations must reopen the executable and independently verify App-ID and signer data.
    fn verify(&mut self, policy: &StrictPolicyBundle) -> Result<()>;
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

pub struct BrokerEngine<B, S, V> {
    backend: B,
    store: S,
    verifier: V,
    current_marker: Option<RecoveryMarker>,
    high_watermark: u64,
    store_loaded: bool,
    phase: BrokerPhase,
    forwarding_health: ForwardingHealth,
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
        }
    }

    pub fn backend(&self) -> &B {
        &self.backend
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

        self.verifier.verify(&policy)?;
        let digest = policy.canonical_digest()?;
        let preparing = RecoveryMarker::preparing(policy, digest);
        self.store.persist(&preparing)?;
        self.high_watermark = preparing.revision;
        self.current_marker = Some(preparing.clone());
        self.phase = BrokerPhase::Preparing;
        self.forwarding_health = ForwardingHealth::default();

        self.backend
            .install_guards(&preparing.policy, &preparing.policy_digest)
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

        if let Err(error) = self
            .backend
            .install_redirects(&marker.policy, &marker.policy_digest)
        {
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

    pub fn recover(&mut self) -> Result<BrokerStatus> {
        let record = self.store.load()?;
        self.store_loaded = true;
        self.high_watermark = record.high_watermark;
        let mut snapshot = self.backend.snapshot()?;

        let Some(marker) = record.marker else {
            if snapshot.guard_filters_installed || snapshot.redirect_filters_installed {
                bail!("orphaned strict filters require operator recovery");
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

        self.verifier.verify(&marker.policy)?;
        if snapshot.redirect_filters_installed {
            self.backend.remove_redirects()?;
            snapshot = self.backend.snapshot()?;
            if snapshot.redirect_filters_installed {
                bail!("strict redirect filters survived recovery removal");
            }
        }
        if !snapshot.guard_filters_installed {
            self.backend
                .install_guards(&marker.policy, &marker.policy_digest)?;
            snapshot = self.backend.snapshot()?;
        }
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
