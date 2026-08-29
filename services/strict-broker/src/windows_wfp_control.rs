use std::collections::BTreeSet;

use anyhow::{bail, Result};
use flclash_strict_contract::StrictCapability;

use crate::{WfpControlPlane, WfpControlSnapshot, WfpFilterSpec, WfpObjectKey, WfpPolicyPlan};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WindowsDriverPolicySnapshot {
    pub revision: Option<u64>,
    pub policy_digest: Option<String>,
    pub generation: u64,
    pub loaded: bool,
    pub capabilities: BTreeSet<StrictCapability>,
}

pub trait WindowsDriverPolicyChannel {
    fn upload(&mut self, plan: &WfpPolicyPlan) -> Result<()>;
    fn unload(&mut self) -> Result<()>;
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
    let has_metadata = snapshot.revision.is_some() && snapshot.policy_digest.is_some();
    if snapshot.loaded != has_metadata {
        bail!("strict driver snapshot metadata is inconsistent");
    }
    if !snapshot.loaded && !snapshot.capabilities.is_empty() {
        bail!("unloaded strict driver advertises active capabilities");
    }
    if let Some(digest) = &snapshot.policy_digest {
        if digest.len() != 64 || !digest.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            bail!("strict driver policy digest is invalid");
        }
    }
    Ok(())
}
