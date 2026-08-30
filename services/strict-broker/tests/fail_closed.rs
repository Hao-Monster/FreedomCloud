use std::collections::BTreeSet;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use anyhow::{bail, Result};
use flclash_strict_broker::{
    BackendSnapshot, BrokerEngine, BrokerPhase, FilterBackend, ForwardingHealth,
    IdentityVerification, IdentityVerifier, RecoveryMarker, RecoveryRecord, RecoveryStore,
    VerifiedApplicationAppIds, VerifiedPolicyAppIds,
};
use flclash_strict_contract::{
    StrictCapability, StrictIdentity, StrictPolicyBundle, StrictPolicyEntry,
};

#[derive(Default)]
struct FakeBackend {
    events: Vec<&'static str>,
    snapshot: BackendSnapshot,
    fail_install_data_plane: bool,
    fail_remove_guards: bool,
}

impl FilterBackend for FakeBackend {
    fn install_guards(
        &mut self,
        policy: &StrictPolicyBundle,
        _verified_app_ids: &VerifiedPolicyAppIds,
        digest: &str,
    ) -> Result<()> {
        self.events.push("installGuards");
        self.snapshot.revision = Some(policy.revision);
        self.snapshot.policy_digest = Some(digest.to_owned());
        self.snapshot.guard_filters_installed = true;
        self.snapshot.filter_generation += 1;
        self.snapshot.capabilities.extend([
            StrictCapability::DriverSigned,
            StrictCapability::IdentityVerified,
            StrictCapability::PersistentFailClosed,
            StrictCapability::RecoveryVerified,
        ]);
        Ok(())
    }

    fn install_data_plane(
        &mut self,
        _policy: &StrictPolicyBundle,
        _verified_app_ids: &VerifiedPolicyAppIds,
        _digest: &str,
    ) -> Result<()> {
        self.events.push("installRedirects");
        if self.fail_install_data_plane {
            bail!("injected redirect failure");
        }
        self.snapshot.data_plane_filters_installed = true;
        self.snapshot.filter_generation += 1;
        self.snapshot
            .capabilities
            .extend(StrictCapability::required_for_proxy());
        Ok(())
    }

    fn remove_data_plane(&mut self) -> Result<()> {
        self.events.push("removeRedirects");
        self.snapshot.data_plane_filters_installed = false;
        self.snapshot.filter_generation += 1;
        Ok(())
    }

    fn remove_guards(&mut self) -> Result<()> {
        self.events.push("removeGuards");
        if self.fail_remove_guards {
            bail!("injected guard cleanup failure");
        }
        self.snapshot.guard_filters_installed = false;
        self.snapshot.revision = None;
        self.snapshot.policy_digest = None;
        self.snapshot.filter_generation += 1;
        Ok(())
    }

    fn snapshot(&mut self) -> Result<BackendSnapshot> {
        self.events.push("snapshot");
        Ok(self.snapshot.clone())
    }
}

#[derive(Default)]
struct FakeStore {
    events: Vec<&'static str>,
    marker: Option<RecoveryMarker>,
    high_watermark: u64,
}

impl RecoveryStore for FakeStore {
    fn load(&mut self) -> Result<RecoveryRecord> {
        self.events.push("loadMarker");
        Ok(RecoveryRecord {
            high_watermark: self.high_watermark,
            marker: self.marker.clone(),
        })
    }

    fn persist(&mut self, marker: &RecoveryMarker) -> Result<()> {
        self.events.push("persistMarker");
        self.high_watermark = self.high_watermark.max(marker.revision);
        self.marker = Some(marker.clone());
        Ok(())
    }

    fn clear_marker(&mut self) -> Result<()> {
        self.events.push("clearMarker");
        self.marker = None;
        Ok(())
    }
}

#[derive(Default)]
struct FakeVerifier {
    events: Vec<&'static str>,
    reject: bool,
}

impl IdentityVerifier for FakeVerifier {
    type VerificationLease = ();

    fn verify(
        &mut self,
        policy: &StrictPolicyBundle,
    ) -> Result<IdentityVerification<Self::VerificationLease>> {
        self.events.push("verifyIdentity");
        if self.reject {
            bail!("injected identity rejection");
        }
        Ok(IdentityVerification::new(fake_app_ids(policy)?, ()))
    }
}

struct CountingVerifier(Arc<AtomicUsize>);

struct CountingLease(Arc<AtomicUsize>);

impl Drop for CountingLease {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

impl IdentityVerifier for CountingVerifier {
    type VerificationLease = CountingLease;

    fn verify(
        &mut self,
        policy: &StrictPolicyBundle,
    ) -> Result<IdentityVerification<Self::VerificationLease>> {
        self.0.fetch_add(1, Ordering::SeqCst);
        Ok(IdentityVerification::new(
            fake_app_ids(policy)?,
            CountingLease(Arc::clone(&self.0)),
        ))
    }
}

fn fake_app_ids(policy: &StrictPolicyBundle) -> Result<VerifiedPolicyAppIds> {
    let applications = policy
        .entries
        .iter()
        .map(|entry| {
            let app_ids = std::iter::once(entry.identity.canonical_path.as_bytes().to_vec())
                .chain(
                    entry
                        .identity
                        .verified_children
                        .iter()
                        .map(|child| child.canonical_path.as_bytes().to_vec()),
                )
                .collect();
            VerifiedApplicationAppIds::new(&entry.identity.identity_id, app_ids)
        })
        .collect::<Result<Vec<_>>>()?;
    VerifiedPolicyAppIds::new(policy, applications)
}

fn hex(character: char) -> String {
    std::iter::repeat_n(character, 64).collect()
}

fn policy(revision: u64) -> StrictPolicyBundle {
    StrictPolicyBundle::new(
        revision,
        vec![StrictPolicyEntry::proxy(
            StrictIdentity {
                identity_id: "10000000-0000-4000-8000-000000000001".into(),
                canonical_path: r"C:\Apps\Electron\app.exe".into(),
                wfp_app_id_sha256: hex('a'),
                publisher_certificate_sha256: hex('b'),
                verified_children: Vec::new(),
            },
            "GLOBAL".into(),
        )],
    )
    .unwrap()
}

fn block_policy(revision: u64) -> StrictPolicyBundle {
    StrictPolicyBundle::new(
        revision,
        vec![StrictPolicyEntry::block(StrictIdentity {
            identity_id: "10000000-0000-4000-8000-000000000002".into(),
            canonical_path: r"C:\Apps\Blocked\blocked.exe".into(),
            wfp_app_id_sha256: hex('c'),
            publisher_certificate_sha256: hex('d'),
            verified_children: Vec::new(),
        })],
    )
    .unwrap()
}

fn complete_health() -> ForwardingHealth {
    ForwardingHealth {
        core_healthy: true,
        relay_healthy: true,
        dns_healthy: true,
        capabilities: StrictCapability::required_for_proxy(),
    }
}

#[test]
fn prepare_persists_recovery_intent_before_installing_guards() {
    let mut engine = BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier::default(),
    );

    let status = engine.prepare(policy(1)).unwrap();

    assert_eq!(status.phase, BrokerPhase::Blocking);
    assert!(status.proof.guard_filters_installed);
    assert!(status.proof.recovery_marker_present);
    assert_eq!(engine.verifier().events, ["verifyIdentity"]);
    assert_eq!(
        engine.store().events,
        ["loadMarker", "persistMarker", "persistMarker"]
    );
    assert_eq!(engine.backend().events, ["installGuards", "snapshot"]);
}

#[test]
fn runtime_cleanup_forces_an_active_policy_to_blocking_and_is_safe_when_disabled() {
    let mut engine = BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier::default(),
    );

    let disabled = engine.force_blocking_if_active().unwrap();
    assert_eq!(disabled.phase, BrokerPhase::Disabled);
    assert!(!disabled.proof.guard_filters_installed);
    assert_eq!(engine.backend().events, ["snapshot"]);

    let selected = policy(1);
    let digest = selected.canonical_digest().unwrap();
    engine.prepare(selected).unwrap();
    engine.commit(1, &digest, complete_health()).unwrap();

    let blocked = engine.force_blocking_if_active().unwrap();
    assert_eq!(blocked.phase, BrokerPhase::Blocking);
    assert!(blocked.proof.guard_filters_installed);
    assert!(!engine.backend().snapshot.data_plane_filters_installed);
    assert_eq!(
        engine.store().marker.as_ref().unwrap().phase,
        BrokerPhase::Blocking
    );
}

#[test]
fn redirect_failure_stays_persistently_blocking() {
    let backend = FakeBackend {
        fail_install_data_plane: true,
        ..FakeBackend::default()
    };
    let mut engine = BrokerEngine::new(backend, FakeStore::default(), FakeVerifier::default());
    let prepared = engine.prepare(policy(2)).unwrap();

    assert!(engine
        .commit(2, &prepared.proof.policy_digest, complete_health())
        .is_err());
    let status = engine.status().unwrap();
    assert_eq!(status.phase, BrokerPhase::Blocking);
    assert!(status.proof.guard_filters_installed);
    assert!(status.proof.recovery_marker_present);
    assert!(!status.proof.relay_healthy);
}

#[test]
fn stale_commit_and_incomplete_capabilities_cannot_arm() {
    let mut engine = BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier::default(),
    );
    let prepared = engine.prepare(policy(3)).unwrap();
    assert!(engine
        .commit(2, &prepared.proof.policy_digest, complete_health())
        .is_err());

    let mut incomplete = complete_health();
    incomplete
        .capabilities
        .remove(&StrictCapability::QuicCaptured);
    assert!(engine
        .commit(3, &prepared.proof.policy_digest, incomplete)
        .is_err());
    assert_eq!(engine.status().unwrap().phase, BrokerPhase::Blocking);
}

#[test]
fn disable_removes_redirects_before_guards_and_clears_marker_last() {
    let mut engine = BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier::default(),
    );
    let prepared = engine.prepare(policy(4)).unwrap();
    engine
        .commit(4, &prepared.proof.policy_digest, complete_health())
        .unwrap();

    let status = engine.disable(4).unwrap();

    assert_eq!(status.phase, BrokerPhase::Disabled);
    assert_eq!(
        engine.backend().events,
        [
            "installGuards",
            "snapshot",
            "installRedirects",
            "snapshot",
            "removeRedirects",
            "snapshot",
            "removeGuards",
            "snapshot"
        ]
    );
    assert_eq!(
        engine.store().events,
        [
            "loadMarker",
            "persistMarker",
            "persistMarker",
            "persistMarker",
            "persistMarker",
            "clearMarker"
        ]
    );
    assert!(engine.prepare(policy(4)).is_err());
}

#[test]
fn failed_guard_cleanup_keeps_recovery_marker() {
    let backend = FakeBackend {
        fail_remove_guards: true,
        ..FakeBackend::default()
    };
    let mut engine = BrokerEngine::new(backend, FakeStore::default(), FakeVerifier::default());
    let prepared = engine.prepare(policy(5)).unwrap();
    engine
        .commit(5, &prepared.proof.policy_digest, complete_health())
        .unwrap();

    assert!(engine.disable(5).is_err());
    assert!(engine.store().marker.is_some());
    assert!(engine.backend().snapshot.guard_filters_installed);
    assert!(!engine.backend().snapshot.data_plane_filters_installed);
}

#[test]
fn startup_downgrades_dynamic_redirect_state_to_blocking() {
    let desired = policy(6);
    let digest = desired.canonical_digest().unwrap();
    let backend = FakeBackend {
        snapshot: BackendSnapshot {
            revision: Some(6),
            policy_digest: Some(digest.clone()),
            filter_generation: 9,
            guard_filters_installed: true,
            data_plane_filters_installed: true,
            capabilities: BTreeSet::new(),
        },
        ..FakeBackend::default()
    };
    let store = FakeStore {
        marker: Some(RecoveryMarker::blocking(desired, digest, 9)),
        high_watermark: 6,
        ..FakeStore::default()
    };
    let mut engine = BrokerEngine::new(backend, store, FakeVerifier::default());

    let status = engine.recover().unwrap();

    assert_eq!(status.phase, BrokerPhase::Blocking);
    assert!(status.proof.guard_filters_installed);
    assert!(!engine.backend().snapshot.data_plane_filters_installed);
    assert!(engine.store().marker.is_some());
}

#[test]
fn startup_rejects_an_orphaned_driver_snapshot_without_a_recovery_marker() {
    let backend = FakeBackend {
        snapshot: BackendSnapshot {
            revision: Some(99),
            policy_digest: Some(hex('a')),
            filter_generation: 1,
            ..BackendSnapshot::default()
        },
        ..FakeBackend::default()
    };
    let mut engine = BrokerEngine::new(backend, FakeStore::default(), FakeVerifier::default());

    assert!(engine.recover().is_err());
    assert!(engine.store().marker.is_none());
    assert_eq!(engine.backend().events, ["snapshot"]);
}

#[test]
fn block_only_policy_arms_without_claiming_forwarding_health() {
    let mut engine = BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier::default(),
    );

    let status = engine.prepare(block_policy(7)).unwrap();

    assert_eq!(status.phase, BrokerPhase::Armed);
    assert_eq!(
        status.proof.capabilities,
        StrictCapability::required_for_block_only()
    );
    assert!(!status.proof.core_healthy);
    assert!(!status.proof.relay_healthy);
    assert!(!status.proof.dns_healthy);
    assert!(!engine.backend().snapshot.data_plane_filters_installed);
}

#[test]
fn identity_rejection_has_no_filter_or_recovery_side_effect() {
    let verifier = FakeVerifier {
        reject: true,
        ..FakeVerifier::default()
    };
    let mut engine = BrokerEngine::new(FakeBackend::default(), FakeStore::default(), verifier);

    assert!(engine.prepare(policy(8)).is_err());

    assert_eq!(engine.verifier().events, ["verifyIdentity"]);
    assert_eq!(engine.store().events, ["loadMarker"]);
    assert!(engine.store().marker.is_none());
    assert!(engine.backend().events.is_empty());
}

#[test]
fn recovery_finishes_disable_if_guards_were_already_removed() {
    let desired = policy(9);
    let digest = desired.canonical_digest().unwrap();
    let store = FakeStore {
        marker: Some(RecoveryMarker::disabling(desired, digest, 12)),
        high_watermark: 9,
        ..FakeStore::default()
    };
    let mut engine = BrokerEngine::new(FakeBackend::default(), store, FakeVerifier::default());

    let status = engine.recover().unwrap();

    assert_eq!(status.phase, BrokerPhase::Disabled);
    assert!(engine.store().marker.is_none());
    assert_eq!(engine.store().high_watermark, 9);
}

#[test]
fn tampered_recovery_digest_is_rejected_without_mutating_filters() {
    let desired = policy(10);
    let digest = desired.canonical_digest().unwrap();
    let backend = FakeBackend {
        snapshot: BackendSnapshot {
            revision: Some(10),
            policy_digest: Some(digest),
            filter_generation: 13,
            guard_filters_installed: true,
            ..BackendSnapshot::default()
        },
        ..FakeBackend::default()
    };
    let store = FakeStore {
        marker: Some(RecoveryMarker::blocking(desired, hex('0'), 13)),
        high_watermark: 10,
        ..FakeStore::default()
    };
    let mut engine = BrokerEngine::new(backend, store, FakeVerifier::default());

    assert!(engine.recover().is_err());

    assert_eq!(engine.backend().events, ["snapshot"]);
    assert!(engine.backend().snapshot.guard_filters_installed);
}

#[test]
fn executable_verification_lease_lives_until_filter_cleanup_completes() {
    let active_leases = Arc::new(AtomicUsize::new(0));
    let mut engine = BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        CountingVerifier(Arc::clone(&active_leases)),
    );

    let prepared = engine.prepare(policy(11)).unwrap();
    assert_eq!(active_leases.load(Ordering::SeqCst), 1);
    engine
        .commit(11, &prepared.proof.policy_digest, complete_health())
        .unwrap();
    assert_eq!(active_leases.load(Ordering::SeqCst), 1);

    engine.disable(11).unwrap();
    assert_eq!(active_leases.load(Ordering::SeqCst), 0);
}
