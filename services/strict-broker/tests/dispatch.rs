use std::collections::BTreeSet;

use anyhow::{bail, Result};
use flclash_strict_broker::{
    BackendSnapshot, BrokerAuthenticator, BrokerDispatcher, ClientPrincipal, ClientRole,
    FilterBackend, ForwardingHealth, ForwardingHealthProbe, IdentityVerification, IdentityVerifier,
    RecoveryMarker, RecoveryRecord, RecoveryStore, VerifiedApplicationAppIds, VerifiedPolicyAppIds,
};
use flclash_strict_contract::{
    BrokerCommand, BrokerRequest, BrokerResponseBody, StrictCapability, StrictIdentity,
    StrictPolicyBundle, StrictPolicyEntry, StrictProxyIngressEntry, StrictProxyIngressSet,
    STRICT_PROTOCOL_VERSION,
};

#[derive(Default)]
struct FakeBackend {
    snapshot: BackendSnapshot,
    fail_guards_with_secret: bool,
}

impl FilterBackend for FakeBackend {
    fn install_guards(
        &mut self,
        policy: &StrictPolicyBundle,
        _verified_app_ids: &VerifiedPolicyAppIds,
        digest: &str,
    ) -> Result<()> {
        if self.fail_guards_with_secret {
            bail!("backend secret must never cross IPC");
        }
        self.snapshot.revision = Some(policy.revision);
        self.snapshot.policy_digest = Some(digest.to_owned());
        self.snapshot.filter_generation += 1;
        self.snapshot.guard_filters_installed = true;
        self.snapshot.capabilities = StrictCapability::required_for_proxy();
        Ok(())
    }

    fn install_redirects(
        &mut self,
        _policy: &StrictPolicyBundle,
        _verified_app_ids: &VerifiedPolicyAppIds,
        _digest: &str,
    ) -> Result<()> {
        self.snapshot.filter_generation += 1;
        self.snapshot.redirect_filters_installed = true;
        Ok(())
    }

    fn remove_redirects(&mut self) -> Result<()> {
        self.snapshot.filter_generation += 1;
        self.snapshot.redirect_filters_installed = false;
        Ok(())
    }

    fn remove_guards(&mut self) -> Result<()> {
        self.snapshot.filter_generation += 1;
        self.snapshot.guard_filters_installed = false;
        Ok(())
    }

    fn snapshot(&mut self) -> Result<BackendSnapshot> {
        Ok(self.snapshot.clone())
    }
}

#[derive(Default)]
struct FakeStore {
    high_watermark: u64,
    marker: Option<RecoveryMarker>,
}

impl RecoveryStore for FakeStore {
    fn load(&mut self) -> Result<RecoveryRecord> {
        Ok(RecoveryRecord {
            high_watermark: self.high_watermark,
            marker: self.marker.clone(),
        })
    }

    fn persist(&mut self, marker: &RecoveryMarker) -> Result<()> {
        self.high_watermark = self.high_watermark.max(marker.revision);
        self.marker = Some(marker.clone());
        Ok(())
    }

    fn clear_marker(&mut self) -> Result<()> {
        self.marker = None;
        Ok(())
    }
}

struct FakeVerifier;

impl IdentityVerifier for FakeVerifier {
    type VerificationLease = ();

    fn verify(
        &mut self,
        policy: &StrictPolicyBundle,
    ) -> Result<IdentityVerification<Self::VerificationLease>> {
        let applications = policy
            .entries
            .iter()
            .map(|entry| {
                VerifiedApplicationAppIds::new(
                    &entry.identity.identity_id,
                    std::iter::once(entry.identity.canonical_path.as_bytes().to_vec())
                        .chain(
                            entry
                                .identity
                                .verified_children
                                .iter()
                                .map(|child| child.canonical_path.as_bytes().to_vec()),
                        )
                        .collect(),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        Ok(IdentityVerification::new(
            VerifiedPolicyAppIds::new(policy, applications)?,
            (),
        ))
    }
}

struct FakeHealthProbe;

impl ForwardingHealthProbe for FakeHealthProbe {
    fn measure(&mut self, ingress: &StrictProxyIngressSet) -> Result<ForwardingHealth> {
        if ingress.entries.is_empty() {
            bail!("strict forwarding ingress is missing");
        }
        Ok(ForwardingHealth {
            core_healthy: true,
            relay_healthy: true,
            dns_healthy: true,
            capabilities: StrictCapability::required_for_proxy(),
        })
    }
}

fn ingress(target_group: &str) -> StrictProxyIngressSet {
    StrictProxyIngressSet::new(
        1,
        vec![StrictProxyIngressEntry::new(
            target_group.into(),
            "127.0.0.1:41001".parse().unwrap(),
            "c".repeat(64),
            "d".repeat(64),
        )
        .unwrap()],
    )
    .unwrap()
}

fn policy(revision: u64) -> StrictPolicyBundle {
    StrictPolicyBundle::new(
        revision,
        vec![StrictPolicyEntry::proxy(
            StrictIdentity {
                identity_id: "10000000-0000-4000-8000-000000000001".into(),
                canonical_path: r"C:\Apps\Alpha\alpha.exe".into(),
                wfp_app_id_sha256: "a".repeat(64),
                publisher_certificate_sha256: "b".repeat(64),
                verified_children: Vec::new(),
            },
            "GLOBAL".into(),
        )],
    )
    .unwrap()
}

fn authorize(command: BrokerCommand) -> flclash_strict_broker::AuthorizedBrokerRequest {
    let capability = [0x11; 32];
    let request = BrokerRequest {
        protocol: STRICT_PROTOCOL_VERSION,
        request_id: "request-1".into(),
        session_capability: "11".repeat(32),
        command,
    };
    BrokerAuthenticator::new(capability)
        .authenticate(
            &ClientPrincipal::new(true, ClientRole::Owner),
            &serde_json::to_string(&request).unwrap(),
        )
        .unwrap()
}

fn status_proof(body: BrokerResponseBody) -> flclash_strict_contract::BrokerProof {
    match body {
        BrokerResponseBody::Status { proof } => proof,
        BrokerResponseBody::Error { code } => panic!("unexpected Broker error: {code:?}"),
    }
}

#[test]
fn dispatcher_uses_internal_health_and_force_blocking_removes_redirects() {
    let engine = flclash_strict_broker::BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier,
    );
    let mut dispatcher = BrokerDispatcher::new(engine, FakeHealthProbe);
    let selected_policy = policy(7);
    let digest = selected_policy.canonical_digest().unwrap();

    let prepared = dispatcher.dispatch(authorize(BrokerCommand::PreparePolicy {
        policy: selected_policy,
    }));
    let prepared = status_proof(prepared.body);
    assert!(prepared.guard_filters_installed);
    assert!(!prepared.relay_healthy);

    let armed = dispatcher.dispatch(authorize(BrokerCommand::CommitPolicy {
        revision: 7,
        policy_digest: digest,
        ingress: ingress("GLOBAL"),
    }));
    let armed = status_proof(armed.body);
    assert!(armed.relay_healthy);
    assert!(armed.capabilities.contains(&StrictCapability::Tcp4Redirect));

    let blocked = dispatcher.dispatch(authorize(BrokerCommand::ForceBlocking { revision: 7 }));
    let blocked = status_proof(blocked.body);
    assert!(!blocked.relay_healthy);
    assert_eq!(
        blocked.capabilities,
        StrictCapability::required_for_block_only()
    );
}

#[test]
fn dispatcher_returns_only_a_stable_error_code() {
    let engine = flclash_strict_broker::BrokerEngine::new(
        FakeBackend {
            fail_guards_with_secret: true,
            ..FakeBackend::default()
        },
        FakeStore::default(),
        FakeVerifier,
    );
    let mut dispatcher = BrokerDispatcher::new(engine, FakeHealthProbe);
    let response = dispatcher.dispatch(authorize(BrokerCommand::PreparePolicy {
        policy: policy(1),
    }));
    assert!(matches!(response.body, BrokerResponseBody::Error { .. }));
    let encoded = String::from_utf8(response.to_bytes().unwrap()).unwrap();
    assert!(!encoded.contains("secret"));
}

#[test]
fn health_probe_contract_is_bounded_to_declared_capabilities() {
    let health = FakeHealthProbe.measure(&ingress("GLOBAL")).unwrap();
    let declared: BTreeSet<_> = health.capabilities.iter().copied().collect();
    assert_eq!(declared, StrictCapability::required_for_proxy());
}

#[test]
fn dispatcher_rejects_an_ingress_for_a_different_target_group() {
    let engine = flclash_strict_broker::BrokerEngine::new(
        FakeBackend::default(),
        FakeStore::default(),
        FakeVerifier,
    );
    let mut dispatcher = BrokerDispatcher::new(engine, FakeHealthProbe);
    let selected_policy = policy(8);
    let digest = selected_policy.canonical_digest().unwrap();
    dispatcher.dispatch(authorize(BrokerCommand::PreparePolicy {
        policy: selected_policy,
    }));

    let response = dispatcher.dispatch(authorize(BrokerCommand::CommitPolicy {
        revision: 8,
        policy_digest: digest,
        ingress: ingress("WORK"),
    }));

    assert!(matches!(
        response.body,
        BrokerResponseBody::Error {
            code: flclash_strict_contract::BrokerErrorCode::InvalidRequest
        }
    ));
    assert!(
        !dispatcher
            .engine_mut()
            .backend_mut()
            .snapshot()
            .unwrap()
            .redirect_filters_installed
    );
}
