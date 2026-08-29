use std::collections::BTreeSet;

use anyhow::{bail, Result};
use flclash_strict_broker::{
    FilterBackend, PlannedWfpBackend, VerifiedApplicationAppIds, VerifiedPolicyAppIds,
    WfpControlPlane, WfpControlSnapshot, WfpFilterSpec, WfpObjectKey, WfpPolicyPlan,
};
use flclash_strict_contract::{
    StrictCapability, StrictIdentity, StrictPolicyBundle, StrictPolicyEntry,
};

#[derive(Default)]
struct FakeControl {
    events: Vec<&'static str>,
    snapshot: WfpControlSnapshot,
    fail_guards: bool,
}

impl WfpControlPlane for FakeControl {
    fn upload_immutable_snapshot(&mut self, plan: &WfpPolicyPlan) -> Result<()> {
        self.events.push("uploadSnapshot");
        self.snapshot.driver_snapshot_loaded = true;
        self.snapshot.revision = Some(plan.revision());
        self.snapshot.policy_digest = Some(plan.policy_digest().into());
        self.snapshot.capabilities = StrictCapability::required_for_proxy();
        Ok(())
    }

    fn unload_immutable_snapshot(&mut self) -> Result<()> {
        self.events.push("unloadSnapshot");
        self.snapshot.driver_snapshot_loaded = false;
        Ok(())
    }

    fn replace_guard_filters(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.events.push("replaceGuards");
        if self.fail_guards {
            bail!("injected atomic guard failure");
        }
        self.snapshot.guard_filter_keys = filters.iter().map(WfpFilterSpec::key).collect();
        self.snapshot.filter_generation += 1;
        Ok(())
    }

    fn replace_redirect_filters(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.events.push("replaceRedirects");
        self.snapshot.redirect_filter_keys = filters.iter().map(WfpFilterSpec::key).collect();
        self.snapshot.filter_generation += 1;
        Ok(())
    }

    fn remove_redirect_filters(&mut self) -> Result<()> {
        self.events.push("removeRedirects");
        self.snapshot.redirect_filter_keys.clear();
        self.snapshot.filter_generation += 1;
        Ok(())
    }

    fn remove_guard_filters(&mut self) -> Result<()> {
        self.events.push("removeGuards");
        self.snapshot.guard_filter_keys.clear();
        self.snapshot.filter_generation += 1;
        Ok(())
    }

    fn snapshot(&mut self) -> Result<WfpControlSnapshot> {
        self.events.push("snapshot");
        Ok(self.snapshot.clone())
    }
}

fn policy() -> StrictPolicyBundle {
    StrictPolicyBundle::new(
        12,
        vec![StrictPolicyEntry::proxy(
            StrictIdentity {
                identity_id: "10000000-0000-4000-8000-000000000001".into(),
                canonical_path: r"C:\Apps\Alpha\alpha.exe".into(),
                wfp_app_id_sha256: "a".repeat(64),
                publisher_certificate_sha256: "b".repeat(64),
                verified_children: Vec::new(),
            },
            "Proxy-A".into(),
        )],
    )
    .unwrap()
}

fn verified(policy: &StrictPolicyBundle) -> VerifiedPolicyAppIds {
    VerifiedPolicyAppIds::new(
        policy,
        vec![VerifiedApplicationAppIds::new(
            "10000000-0000-4000-8000-000000000001",
            vec![vec![1, 2, 3, 4]],
        )
        .unwrap()],
    )
    .unwrap()
}

#[test]
fn guards_upload_snapshot_before_atomic_filter_install() {
    let desired = policy();
    let digest = desired.canonical_digest().unwrap();
    let mut backend = PlannedWfpBackend::new(FakeControl::default());

    backend
        .install_guards(&desired, &verified(&desired), &digest)
        .unwrap();
    let state = backend.snapshot().unwrap();

    assert!(state.guard_filters_installed);
    assert!(!state.redirect_filters_installed);
    assert_eq!(
        backend.control().events,
        ["uploadSnapshot", "replaceGuards", "snapshot", "snapshot"]
    );
}

#[test]
fn atomic_guard_failure_unloads_the_unused_snapshot() {
    let desired = policy();
    let digest = desired.canonical_digest().unwrap();
    let mut backend = PlannedWfpBackend::new(FakeControl {
        fail_guards: true,
        ..FakeControl::default()
    });

    assert!(backend
        .install_guards(&desired, &verified(&desired), &digest)
        .is_err());
    assert_eq!(
        backend.control().events,
        ["uploadSnapshot", "replaceGuards", "unloadSnapshot"]
    );
    assert!(!backend.control().snapshot.driver_snapshot_loaded);
    assert!(backend.control().snapshot.guard_filter_keys.is_empty());
}

#[test]
fn redirects_are_removed_before_guards_and_snapshot_unloads_last() {
    let desired = policy();
    let digest = desired.canonical_digest().unwrap();
    let mut backend = PlannedWfpBackend::new(FakeControl::default());
    let app_ids = verified(&desired);
    backend.install_guards(&desired, &app_ids, &digest).unwrap();
    backend
        .install_redirects(&desired, &app_ids, &digest)
        .unwrap();

    backend.remove_redirects().unwrap();
    backend.remove_guards().unwrap();

    let tail = &backend.control().events[backend.control().events.len() - 7..];
    assert_eq!(
        tail,
        [
            "removeRedirects",
            "snapshot",
            "snapshot",
            "removeGuards",
            "snapshot",
            "unloadSnapshot",
            "snapshot",
        ]
    );
    assert_eq!(
        backend.control().snapshot.guard_filter_keys,
        BTreeSet::new()
    );
}

#[test]
fn unknown_filter_keys_are_never_treated_as_a_complete_plan() {
    let desired = policy();
    let digest = desired.canonical_digest().unwrap();
    let mut backend = PlannedWfpBackend::new(FakeControl::default());
    backend
        .install_guards(&desired, &verified(&desired), &digest)
        .unwrap();
    backend
        .control_mut()
        .snapshot
        .guard_filter_keys
        .insert(WfpObjectKey::from_bytes([0xee; 16]));

    assert!(backend.snapshot().is_err());
}
