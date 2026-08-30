use std::collections::BTreeSet;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{StrictCapability, StrictPolicyBundle};

use crate::{
    BackendSnapshot, FilterBackend, VerifiedPolicyAppIds, WfpFilterSpec, WfpObjectKey,
    WfpPolicyPlan,
};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WfpControlSnapshot {
    pub revision: Option<u64>,
    pub policy_digest: Option<String>,
    pub filter_generation: u64,
    pub driver_snapshot_loaded: bool,
    pub guard_filter_keys: BTreeSet<WfpObjectKey>,
    pub data_plane_filter_keys: BTreeSet<WfpObjectKey>,
    pub datagram_path_active: bool,
    pub capabilities: BTreeSet<StrictCapability>,
}

pub trait WfpControlPlane {
    /// Uploads an immutable, bounded driver snapshot without activating any filter.
    fn upload_immutable_snapshot(&mut self, plan: &WfpPolicyPlan) -> Result<()>;
    fn unload_immutable_snapshot(&mut self) -> Result<()>;

    /// Each replace/remove method must be one WFP transaction scoped to our provider/sublayer.
    fn replace_guard_filters(&mut self, filters: &[WfpFilterSpec]) -> Result<()>;
    fn replace_data_plane_filters(&mut self, filters: &[WfpFilterSpec]) -> Result<()>;
    fn activate_datagram_path(&mut self) -> Result<()>;
    fn deactivate_datagram_path(&mut self) -> Result<()>;
    fn remove_data_plane_filters(&mut self) -> Result<()>;
    fn remove_guard_filters(&mut self) -> Result<()>;

    /// Must enumerate actual provider-owned objects; cached intended state is insufficient.
    fn snapshot(&mut self) -> Result<WfpControlSnapshot>;
}

pub struct PlannedWfpBackend<C> {
    control: C,
    active_plan: Option<WfpPolicyPlan>,
}

impl<C> PlannedWfpBackend<C> {
    pub fn new(control: C) -> Self {
        Self {
            control,
            active_plan: None,
        }
    }

    pub fn control(&self) -> &C {
        &self.control
    }

    pub fn control_mut(&mut self) -> &mut C {
        &mut self.control
    }
}

impl<C: WfpControlPlane> FilterBackend for PlannedWfpBackend<C> {
    fn install_guards(
        &mut self,
        policy: &StrictPolicyBundle,
        verified_app_ids: &VerifiedPolicyAppIds,
        digest: &str,
    ) -> Result<()> {
        let plan = checked_plan(policy, verified_app_ids, digest)?;
        self.control
            .upload_immutable_snapshot(&plan)
            .context("upload strict driver policy snapshot")?;
        if let Err(error) = self.control.replace_guard_filters(plan.guard_filters()) {
            if let Err(unload_error) = self.control.unload_immutable_snapshot() {
                bail!(
                    "atomic strict guard transaction failed: {error:#}; unused snapshot cleanup failed: {unload_error:#}"
                );
            }
            return Err(error).context("replace strict guard filters transactionally");
        }
        self.active_plan = Some(plan);
        let snapshot = self.control.snapshot()?;
        validate_inventory(
            &snapshot,
            self.active_plan.as_ref().expect("active plan was just set"),
            true,
            false,
            false,
        )?;
        Ok(())
    }

    fn install_data_plane(
        &mut self,
        policy: &StrictPolicyBundle,
        verified_app_ids: &VerifiedPolicyAppIds,
        digest: &str,
    ) -> Result<()> {
        let plan = checked_plan(policy, verified_app_ids, digest)?;
        let before = self.control.snapshot()?;
        validate_inventory(&before, &plan, true, false, false)?;
        self.control
            .replace_data_plane_filters(plan.data_plane_filters())
            .context("replace strict data-plane filters transactionally")?;
        self.active_plan = Some(plan);
        let after = self.control.snapshot()?;
        validate_inventory(
            &after,
            self.active_plan.as_ref().expect("active plan was just set"),
            true,
            true,
            false,
        )?;
        if let Err(error) = self.control.activate_datagram_path() {
            let cleanup = cleanup_failed_datagram_activation(&mut self.control);
            return match cleanup {
                Ok(()) => Err(error).context("activate strict datagram path"),
                Err(cleanup_error) => bail!(
                    "activate strict datagram path failed: {error:#}; fail-closed cleanup failed: {cleanup_error:#}"
                ),
            };
        }
        let active_attestation = self.control.snapshot().and_then(|active| {
            validate_inventory(
                &active,
                self.active_plan.as_ref().expect("active plan was just set"),
                true,
                true,
                true,
            )
        });
        if let Err(error) = active_attestation {
            let cleanup = cleanup_failed_datagram_activation(&mut self.control);
            return match cleanup {
                Ok(()) => Err(error).context("attest active strict datagram path"),
                Err(cleanup_error) => bail!(
                    "attest active strict datagram path failed: {error:#}; fail-closed cleanup failed: {cleanup_error:#}"
                ),
            };
        }
        Ok(())
    }

    fn remove_data_plane(&mut self) -> Result<()> {
        self.control
            .deactivate_datagram_path()
            .context("deactivate strict datagram path before filter removal")?;
        let inactive = self.control.snapshot()?;
        if inactive.datagram_path_active {
            bail!("strict datagram path remains active before filter removal");
        }
        self.control
            .remove_data_plane_filters()
            .context("remove strict data-plane filters transactionally")?;
        let snapshot = self.control.snapshot()?;
        if !snapshot.data_plane_filter_keys.is_empty() {
            bail!("strict data-plane filters remain after transactional removal");
        }
        Ok(())
    }

    fn remove_guards(&mut self) -> Result<()> {
        let before = self.control.snapshot()?;
        if !before.data_plane_filter_keys.is_empty() {
            bail!("strict guards cannot be removed while data-plane filters remain");
        }
        self.control
            .remove_guard_filters()
            .context("remove strict guard filters transactionally")?;
        let without_guards = self.control.snapshot()?;
        if !without_guards.guard_filter_keys.is_empty() {
            bail!("strict guard filters remain after transactional removal");
        }
        self.control
            .unload_immutable_snapshot()
            .context("unload inactive strict driver policy snapshot")?;
        let unloaded = self.control.snapshot()?;
        if unloaded.driver_snapshot_loaded {
            bail!("strict driver policy snapshot remains after guard cleanup");
        }
        self.active_plan = None;
        Ok(())
    }

    fn snapshot(&mut self) -> Result<BackendSnapshot> {
        let snapshot = self.control.snapshot()?;
        let capabilities = if let Some(plan) = &self.active_plan {
            validate_present_inventory(&snapshot, plan)?;
            snapshot.capabilities.clone()
        } else {
            BTreeSet::new()
        };
        Ok(BackendSnapshot {
            revision: snapshot.revision,
            policy_digest: snapshot.policy_digest,
            filter_generation: snapshot.filter_generation,
            guard_filters_installed: !snapshot.guard_filter_keys.is_empty(),
            data_plane_filters_installed: !snapshot.data_plane_filter_keys.is_empty(),
            capabilities,
        })
    }
}

fn checked_plan(
    policy: &StrictPolicyBundle,
    verified_app_ids: &VerifiedPolicyAppIds,
    digest: &str,
) -> Result<WfpPolicyPlan> {
    let plan = WfpPolicyPlan::new(policy, verified_app_ids)?;
    if !plan.policy_digest().eq_ignore_ascii_case(digest) {
        bail!("strict WFP plan digest does not match the Broker transaction");
    }
    Ok(plan)
}

fn validate_inventory(
    snapshot: &WfpControlSnapshot,
    plan: &WfpPolicyPlan,
    expect_guards: bool,
    expect_redirects: bool,
    expect_datagram_active: bool,
) -> Result<()> {
    validate_plan_metadata(snapshot, plan)?;
    let expected_guards = expected_keys(plan.guard_filters(), expect_guards);
    let expected_data_plane = expected_keys(plan.data_plane_filters(), expect_redirects);
    if snapshot.guard_filter_keys != expected_guards
        || snapshot.data_plane_filter_keys != expected_data_plane
        || snapshot.datagram_path_active != expect_datagram_active
    {
        bail!("enumerated WFP filters do not exactly match the strict policy plan");
    }
    Ok(())
}

fn validate_present_inventory(snapshot: &WfpControlSnapshot, plan: &WfpPolicyPlan) -> Result<()> {
    if snapshot.guard_filter_keys.is_empty() && snapshot.data_plane_filter_keys.is_empty() {
        if snapshot.datagram_path_active {
            bail!("strict datagram path is active without filters");
        }
        return Ok(());
    }
    validate_plan_metadata(snapshot, plan)?;
    let expected_guards = expected_keys(plan.guard_filters(), true);
    let expected_data_plane = expected_keys(plan.data_plane_filters(), true);
    if snapshot.guard_filter_keys != expected_guards
        || (!snapshot.data_plane_filter_keys.is_empty()
            && snapshot.data_plane_filter_keys != expected_data_plane)
        || snapshot.datagram_path_active == snapshot.data_plane_filter_keys.is_empty()
    {
        bail!("enumerated WFP filters contain missing or unknown strict objects");
    }
    Ok(())
}

fn cleanup_failed_datagram_activation<C: WfpControlPlane>(control: &mut C) -> Result<()> {
    control
        .deactivate_datagram_path()
        .context("deactivate uncertain datagram path")?;
    control
        .remove_data_plane_filters()
        .context("remove filters after datagram activation")
}

fn validate_plan_metadata(snapshot: &WfpControlSnapshot, plan: &WfpPolicyPlan) -> Result<()> {
    if !snapshot.driver_snapshot_loaded
        || snapshot.revision != Some(plan.revision())
        || snapshot
            .policy_digest
            .as_deref()
            .is_none_or(|digest| !digest.eq_ignore_ascii_case(plan.policy_digest()))
    {
        bail!("WFP control-plane snapshot does not match the strict policy plan");
    }
    Ok(())
}

fn expected_keys(filters: &[WfpFilterSpec], expected: bool) -> BTreeSet<WfpObjectKey> {
    if expected {
        filters.iter().map(WfpFilterSpec::key).collect()
    } else {
        BTreeSet::new()
    }
}
