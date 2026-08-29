use std::collections::BTreeSet;

use anyhow::{bail, Result};
use flclash_strict_contract::StrictCapability;

use crate::{WfpControlPlane, WfpControlSnapshot, WfpFilterSpec, WfpObjectKey, WfpPolicyPlan};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WindowsDriverEndpointLeaseSnapshot {
    pub generation: u64,
    pub remaining_millis: u32,
    pub nonce: [u8; 16],
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct WindowsDriverDatagramHealthSnapshot {
    pub injection_attempts: u64,
    pub injection_succeeded: u64,
    pub injection_failed: u64,
    pub partial_batch_failures: u64,
    pub injection_in_flight: u32,
    pub last_failure_status: u32,
}

impl WindowsDriverDatagramHealthSnapshot {
    pub fn validate(&self) -> Result<()> {
        if self.injection_in_flight > 256 {
            bail!("strict driver datagram in-flight count exceeds its hard limit");
        }
        let finished = self
            .injection_succeeded
            .checked_add(self.injection_failed)
            .and_then(|count| count.checked_add(u64::from(self.injection_in_flight)))
            .ok_or_else(|| anyhow::anyhow!("strict driver datagram health counters overflow"))?;
        if finished != self.injection_attempts {
            bail!("strict driver datagram health counters are inconsistent");
        }
        let has_failure = self.injection_failed != 0 || self.partial_batch_failures != 0;
        if has_failure != (self.last_failure_status != 0) {
            bail!("strict driver datagram failure status is inconsistent");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WindowsDriverPolicySnapshot {
    pub driver_build_id: Option<String>,
    pub revision: Option<u64>,
    pub policy_digest: Option<String>,
    pub rule_count: usize,
    pub generation: u64,
    pub loaded: bool,
    pub capabilities: BTreeSet<StrictCapability>,
    pub endpoint_lease: Option<WindowsDriverEndpointLeaseSnapshot>,
    pub datagram_path_active: bool,
    pub datagram_health: WindowsDriverDatagramHealthSnapshot,
}

pub trait WindowsDriverPolicyChannel {
    fn upload(&mut self, plan: &WfpPolicyPlan) -> Result<()>;
    fn unload(&mut self) -> Result<()>;
    fn activate_datagram_path(&mut self) -> Result<()>;
    fn deactivate_datagram_path(&mut self) -> Result<()>;
    fn snapshot(&mut self) -> Result<WindowsDriverPolicySnapshot>;
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WindowsWfpFilterInventory {
    pub guard_filter_keys: BTreeSet<WfpObjectKey>,
    pub redirect_filter_keys: BTreeSet<WfpObjectKey>,
}

pub trait WindowsWfpFilterStore {
    fn replace_guards(&mut self, filters: &[WfpFilterSpec]) -> Result<()>;
    fn replace_redirects(&mut self, filters: &[WfpFilterSpec]) -> Result<()>;
    fn remove_redirects(&mut self) -> Result<()>;
    fn remove_guards(&mut self) -> Result<()>;
    fn inventory(&mut self) -> Result<WindowsWfpFilterInventory>;
}

pub struct WindowsWfpControl<S, D> {
    filters: S,
    driver: D,
    observed_driver_generation: u64,
    filter_generation: u64,
}

impl<S, D> WindowsWfpControl<S, D> {
    pub fn new(filters: S, driver: D) -> Self {
        Self {
            filters,
            driver,
            observed_driver_generation: 0,
            filter_generation: 0,
        }
    }

    pub fn filters(&self) -> &S {
        &self.filters
    }

    pub fn driver(&self) -> &D {
        &self.driver
    }

    pub fn filters_mut(&mut self) -> &mut S {
        &mut self.filters
    }

    pub fn driver_mut(&mut self) -> &mut D {
        &mut self.driver
    }

    fn record_mutation(&mut self) -> Result<()> {
        self.filter_generation = self
            .filter_generation
            .max(self.observed_driver_generation)
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("strict WFP filter generation overflow"))?;
        Ok(())
    }
}

impl<S, D> WfpControlPlane for WindowsWfpControl<S, D>
where
    S: WindowsWfpFilterStore,
    D: WindowsDriverPolicyChannel,
{
    fn upload_immutable_snapshot(&mut self, plan: &WfpPolicyPlan) -> Result<()> {
        self.driver.upload(plan)?;
        let snapshot = self.driver.snapshot()?;
        validate_loaded_driver_snapshot(&snapshot, plan)?;
        self.observe_driver_generation(snapshot.generation)?;
        self.record_mutation()
    }

    fn unload_immutable_snapshot(&mut self) -> Result<()> {
        self.driver.unload()?;
        let snapshot = self.driver.snapshot()?;
        validate_driver_snapshot_shape(&snapshot)?;
        if snapshot.loaded {
            bail!("strict driver policy snapshot remains loaded after unload");
        }
        self.observe_driver_generation(snapshot.generation)?;
        self.record_mutation()
    }

    fn replace_guard_filters(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.filters.replace_guards(filters)?;
        self.record_mutation()
    }

    fn replace_redirect_filters(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.filters.replace_redirects(filters)?;
        self.record_mutation()
    }

    fn activate_datagram_path(&mut self) -> Result<()> {
        self.driver.activate_datagram_path()?;
        let snapshot = self.driver.snapshot()?;
        validate_driver_snapshot_shape(&snapshot)?;
        if !snapshot.datagram_path_active {
            bail!("strict driver did not attest datagram activation");
        }
        self.observe_driver_generation(snapshot.generation)?;
        self.record_mutation()
    }

    fn deactivate_datagram_path(&mut self) -> Result<()> {
        self.driver.deactivate_datagram_path()?;
        let snapshot = self.driver.snapshot()?;
        validate_driver_snapshot_shape(&snapshot)?;
        if snapshot.datagram_path_active {
            bail!("strict driver retained datagram activation after revocation");
        }
        self.observe_driver_generation(snapshot.generation)?;
        self.record_mutation()
    }

    fn remove_redirect_filters(&mut self) -> Result<()> {
        self.filters.remove_redirects()?;
        self.record_mutation()
    }

    fn remove_guard_filters(&mut self) -> Result<()> {
        self.filters.remove_guards()?;
        self.record_mutation()
    }

    fn snapshot(&mut self) -> Result<WfpControlSnapshot> {
        let driver = self.driver.snapshot()?;
        validate_driver_snapshot_shape(&driver)?;
        self.observe_driver_generation(driver.generation)?;
        let inventory = self.filters.inventory()?;
        Ok(WfpControlSnapshot {
            revision: driver.revision,
            policy_digest: driver.policy_digest,
            filter_generation: self.filter_generation.max(self.observed_driver_generation),
            driver_snapshot_loaded: driver.loaded,
            guard_filter_keys: inventory.guard_filter_keys,
            redirect_filter_keys: inventory.redirect_filter_keys,
            datagram_path_active: driver.datagram_path_active,
            capabilities: driver.capabilities,
        })
    }
}

impl<S, D> WindowsWfpControl<S, D> {
    fn observe_driver_generation(&mut self, generation: u64) -> Result<()> {
        if generation < self.observed_driver_generation {
            bail!("strict driver policy generation rolled back");
        }
        self.observed_driver_generation = generation;
        Ok(())
    }
}

fn validate_loaded_driver_snapshot(
    snapshot: &WindowsDriverPolicySnapshot,
    plan: &WfpPolicyPlan,
) -> Result<()> {
    validate_driver_snapshot_shape(snapshot)?;
    if !snapshot.loaded
        || snapshot.revision != Some(plan.revision())
        || snapshot.rule_count != plan.rules().len()
        || snapshot
            .policy_digest
            .as_deref()
            .is_none_or(|digest| !digest.eq_ignore_ascii_case(plan.policy_digest()))
    {
        bail!("driver did not attest the uploaded strict policy snapshot");
    }
    Ok(())
}

fn validate_driver_snapshot_shape(snapshot: &WindowsDriverPolicySnapshot) -> Result<()> {
    if snapshot.driver_build_id.as_deref().is_none_or(|build_id| {
        build_id.len() != 32 || !build_id.bytes().all(|byte| byte.is_ascii_hexdigit())
    }) {
        bail!("strict driver build identity is invalid");
    }
    let has_metadata =
        snapshot.revision.is_some() && snapshot.policy_digest.is_some() && snapshot.rule_count != 0;
    if snapshot.loaded != has_metadata {
        bail!("strict driver snapshot metadata is inconsistent");
    }
    if !snapshot.loaded && !snapshot.capabilities.is_empty() {
        bail!("unloaded strict driver advertises active capabilities");
    }
    if !snapshot.loaded && snapshot.endpoint_lease.is_some() {
        bail!("unloaded strict driver retains an endpoint lease");
    }
    if snapshot.datagram_path_active && (!snapshot.loaded || snapshot.endpoint_lease.is_none()) {
        bail!("strict driver retains datagram activation without policy and lease");
    }
    snapshot.datagram_health.validate()?;
    if let Some(lease) = &snapshot.endpoint_lease {
        if lease.generation == 0
            || lease.remaining_millis == 0
            || lease.remaining_millis > 30_000
            || lease.nonce.iter().all(|byte| *byte == 0)
        {
            bail!("strict driver endpoint lease metadata is invalid");
        }
    }
    let advertises_redirect = [
        StrictCapability::Tcp4Redirect,
        StrictCapability::Tcp6Redirect,
        StrictCapability::Udp4Redirect,
        StrictCapability::Udp6Redirect,
        StrictCapability::DnsCaptured,
        StrictCapability::QuicCaptured,
        StrictCapability::RedirectLoopProtected,
    ]
    .into_iter()
    .any(|capability| snapshot.capabilities.contains(&capability));
    if advertises_redirect && snapshot.endpoint_lease.is_none() {
        bail!("strict driver advertises redirect without a live endpoint lease");
    }
    if !snapshot.loaded && snapshot.rule_count != 0 {
        bail!("unloaded strict driver retains a policy rule count");
    }
    if let Some(digest) = &snapshot.policy_digest {
        if digest.len() != 64 || !digest.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            bail!("strict driver policy digest is invalid");
        }
    }
    Ok(())
}
