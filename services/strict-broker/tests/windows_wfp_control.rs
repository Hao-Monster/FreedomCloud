#![cfg(windows)]

use std::collections::BTreeSet;

use anyhow::Result;
use flclash_strict_broker::{
    VerifiedApplicationAppIds, VerifiedPolicyAppIds, WfpControlPlane, WfpFilterSpec, WfpPolicyPlan,
    WindowsDriverEndpointLeaseSnapshot, WindowsDriverPolicyChannel, WindowsDriverPolicySnapshot,
    WindowsWfpControl, WindowsWfpFilterInventory, WindowsWfpFilterStore,
};
use flclash_strict_contract::{
    StrictCapability, StrictIdentity, StrictPolicyBundle, StrictPolicyEntry,
};

#[derive(Default)]
struct FakeFilters {
    inventory: WindowsWfpFilterInventory,
}

impl WindowsWfpFilterStore for FakeFilters {
    fn replace_guards(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.inventory.guard_filter_keys = filters.iter().map(WfpFilterSpec::key).collect();
        Ok(())
    }

    fn replace_redirects(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.inventory.redirect_filter_keys = filters.iter().map(WfpFilterSpec::key).collect();
        Ok(())
    }

    fn remove_redirects(&mut self) -> Result<()> {
        self.inventory.redirect_filter_keys.clear();
        Ok(())
    }

    fn remove_guards(&mut self) -> Result<()> {
        self.inventory.guard_filter_keys.clear();
        Ok(())
    }

    fn inventory(&mut self) -> Result<WindowsWfpFilterInventory> {
        Ok(self.inventory.clone())
    }
}

#[derive(Default)]
struct FakeDriver {
    snapshot: WindowsDriverPolicySnapshot,
}

impl WindowsDriverPolicyChannel for FakeDriver {
    fn upload(&mut self, plan: &WfpPolicyPlan) -> Result<()> {
        self.snapshot = WindowsDriverPolicySnapshot {
            driver_build_id: Some("c".repeat(32)),
            revision: Some(plan.revision()),
            policy_digest: Some(plan.policy_digest().into()),
            rule_count: plan.rules().len(),
            generation: self.snapshot.generation + 1,
            loaded: true,
            capabilities: StrictCapability::required_for_proxy(),
            endpoint_lease: Some(WindowsDriverEndpointLeaseSnapshot {
                generation: 1,
                remaining_millis: 5_000,
                nonce: [1; 16],
            }),
            datagram_path_active: false,
        };
        Ok(())
    }

    fn unload(&mut self) -> Result<()> {
        self.snapshot.generation += 1;
        self.snapshot.loaded = false;
        self.snapshot.revision = None;
        self.snapshot.policy_digest = None;
        self.snapshot.rule_count = 0;
        self.snapshot.capabilities.clear();
        self.snapshot.endpoint_lease = None;
        self.snapshot.datagram_path_active = false;
        Ok(())
    }

    fn activate_datagram_path(&mut self) -> Result<()> {
        if !self.snapshot.loaded || self.snapshot.endpoint_lease.is_none() {
            anyhow::bail!("fake driver has no active policy lease");
        }
        self.snapshot.datagram_path_active = true;
        Ok(())
    }

    fn deactivate_datagram_path(&mut self) -> Result<()> {
        self.snapshot.datagram_path_active = false;
        Ok(())
    }

    fn snapshot(&mut self) -> Result<WindowsDriverPolicySnapshot> {
        Ok(self.snapshot.clone())
    }
}

fn plan() -> WfpPolicyPlan {
    let policy = StrictPolicyBundle::new(
        77,
        vec![StrictPolicyEntry::proxy(
            StrictIdentity {
                identity_id: "10000000-0000-4000-8000-000000000001".into(),
                canonical_path: r"C:\Apps\WfpControl\app.exe".into(),
                wfp_app_id_sha256: "a".repeat(64),
                publisher_certificate_sha256: "b".repeat(64),
                verified_children: Vec::new(),
            },
            "Proxy-A".into(),
        )],
    )
    .unwrap();
    let verified = VerifiedPolicyAppIds::new(
        &policy,
        vec![VerifiedApplicationAppIds::new(
            "10000000-0000-4000-8000-000000000001",
            vec![vec![1, 2, 3, 4]],
        )
        .unwrap()],
    )
    .unwrap();
    WfpPolicyPlan::new(&policy, &verified).unwrap()
}

#[test]
fn driver_attestation_and_enumerated_filters_form_one_snapshot() {
    let plan = plan();
    let mut control = WindowsWfpControl::new(FakeFilters::default(), FakeDriver::default());

    control.upload_immutable_snapshot(&plan).unwrap();
    control.replace_guard_filters(plan.guard_filters()).unwrap();
    control
        .replace_redirect_filters(plan.redirect_filters())
        .unwrap();
    control.activate_datagram_path().unwrap();
    let snapshot = control.snapshot().unwrap();

    assert_eq!(snapshot.revision, Some(77));
    assert_eq!(
        snapshot.policy_digest.as_deref(),
        Some(plan.policy_digest())
    );
    assert_eq!(
        snapshot.guard_filter_keys,
        plan.guard_filters()
            .iter()
            .map(WfpFilterSpec::key)
            .collect()
    );
    assert_eq!(
        snapshot.redirect_filter_keys,
        plan.redirect_filters()
            .iter()
            .map(WfpFilterSpec::key)
            .collect()
    );
    assert!(snapshot.filter_generation >= 3);
    assert!(snapshot.datagram_path_active);
}

#[test]
fn driver_generation_rollback_is_rejected() {
    let plan = plan();
    let mut control = WindowsWfpControl::new(FakeFilters::default(), FakeDriver::default());
    control.upload_immutable_snapshot(&plan).unwrap();
    control.driver_mut().snapshot.generation = 0;

    assert!(control.snapshot().is_err());
}

#[test]
fn unloaded_driver_cannot_advertise_capabilities() {
    let driver = FakeDriver {
        snapshot: WindowsDriverPolicySnapshot {
            capabilities: BTreeSet::from([StrictCapability::DriverSigned]),
            ..WindowsDriverPolicySnapshot::default()
        },
    };
    let mut control = WindowsWfpControl::new(FakeFilters::default(), driver);
    assert!(control.snapshot().is_err());
}

#[test]
fn redirect_capabilities_require_a_live_endpoint_lease() {
    let plan = plan();
    let mut control = WindowsWfpControl::new(FakeFilters::default(), FakeDriver::default());
    control.upload_immutable_snapshot(&plan).unwrap();
    control.driver_mut().snapshot.endpoint_lease = None;

    assert!(control.snapshot().is_err());
}

#[test]
fn active_datagram_path_requires_a_live_endpoint_lease() {
    let plan = plan();
    let mut control = WindowsWfpControl::new(FakeFilters::default(), FakeDriver::default());
    control.upload_immutable_snapshot(&plan).unwrap();
    control.driver_mut().snapshot.capabilities =
        BTreeSet::from([StrictCapability::PersistentFailClosed]);
    control.driver_mut().snapshot.endpoint_lease = None;
    control.driver_mut().snapshot.datagram_path_active = true;

    let error = control.snapshot().unwrap_err();
    assert!(error
        .to_string()
        .contains("datagram activation without policy and lease"));
}
