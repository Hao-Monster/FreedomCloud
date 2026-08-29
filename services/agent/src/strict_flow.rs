use std::collections::BTreeSet;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{
    BrokerCommand, BrokerProof, StrictAction, StrictCapability, StrictIntent, StrictPolicyBundle,
    StrictState, StrictStatus,
};

use crate::core_ingress::{StrictIngressChange, StrictIngressCoordinator, StrictIngressCoreAction};
use crate::strict::{StrictController, StrictReason};

pub enum StrictOrchestrationAction {
    Broker(BrokerCommand),
    Core(StrictIngressCoreAction),
    Settled(StrictStatus),
}

enum Phase {
    Idle,
    AwaitPrepare {
        policy: StrictPolicyBundle,
        digest: String,
        target_groups: Vec<String>,
    },
    AwaitIngress {
        revision: u64,
        digest: String,
    },
    AwaitCommit {
        revision: u64,
    },
    Active {
        revision: u64,
    },
    AwaitBlocking {
        revision: u64,
    },
    AwaitBlockingRevoke {
        revision: u64,
    },
    Blocked {
        revision: u64,
    },
    AwaitDisable,
    AwaitDisableRevoke,
}

pub struct StrictPolicyOrchestrator {
    controller: StrictController,
    ingress: StrictIngressCoordinator,
    phase: Phase,
}

impl Default for StrictPolicyOrchestrator {
    fn default() -> Self {
        Self {
            controller: StrictController::default(),
            ingress: StrictIngressCoordinator::default(),
            phase: Phase::Idle,
        }
    }
}

impl StrictPolicyOrchestrator {
    pub fn status(&self) -> StrictStatus {
        self.controller.status()
    }

    pub fn begin(&mut self, policy: StrictPolicyBundle) -> Result<StrictOrchestrationAction> {
        if !matches!(self.phase, Phase::Idle) {
            bail!("strict policy orchestration is already active");
        }
        policy.validate()?;
        let digest = policy.canonical_digest()?;
        let proxy_application_count = policy
            .entries
            .iter()
            .filter(|entry| entry.action == StrictAction::Proxy)
            .count();
        let blocked_application_count = policy.entries.len() - proxy_application_count;
        let target_groups = policy
            .entries
            .iter()
            .filter(|entry| entry.action == StrictAction::Proxy)
            .filter_map(|entry| entry.target_group.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        self.controller.begin(StrictIntent::new(
            policy.revision,
            digest.clone(),
            proxy_application_count,
            blocked_application_count,
        )?)?;
        self.phase = Phase::AwaitPrepare {
            policy: policy.clone(),
            digest,
            target_groups,
        };
        Ok(StrictOrchestrationAction::Broker(
            BrokerCommand::PreparePolicy { policy },
        ))
    }

    pub fn accept_broker_proof(&mut self, proof: BrokerProof) -> Result<StrictOrchestrationAction> {
        let phase = std::mem::replace(&mut self.phase, Phase::Idle);
        match phase {
            Phase::AwaitPrepare {
                policy,
                digest,
                target_groups,
            } => {
                if let Err(error) = self.controller.apply_broker_proof(proof.clone()) {
                    self.phase = Phase::AwaitPrepare {
                        policy,
                        digest,
                        target_groups,
                    };
                    return Err(error);
                }
                if !proves_persistent_blocking_guard(&proof) {
                    self.phase = Phase::AwaitBlocking {
                        revision: policy.revision,
                    };
                    bail!("strict Broker did not prove persistent guards");
                }
                if target_groups.is_empty() {
                    if self.controller.status().state != StrictState::Armed {
                        self.phase = Phase::AwaitBlocking {
                            revision: policy.revision,
                        };
                        bail!("strict block-only policy did not arm");
                    }
                    self.phase = Phase::Active {
                        revision: policy.revision,
                    };
                    return Ok(StrictOrchestrationAction::Settled(self.status()));
                }
                if self.controller.status().state != StrictState::Blocking {
                    self.controller
                        .backend_lost(StrictReason::BackendUnavailable);
                    self.phase = Phase::AwaitBlocking {
                        revision: policy.revision,
                    };
                    bail!("strict Broker reported proxy policy armed before Core commit");
                }
                let ingress_change = match self.ingress.begin(target_groups) {
                    Ok(change) => change,
                    Err(error) => {
                        self.phase = Phase::AwaitBlocking {
                            revision: policy.revision,
                        };
                        return Err(error.context("prepare strict Core ingress"));
                    }
                };
                match ingress_change {
                    StrictIngressChange::Request(action) => {
                        self.phase = Phase::AwaitIngress {
                            revision: policy.revision,
                            digest,
                        };
                        Ok(StrictOrchestrationAction::Core(action))
                    }
                    StrictIngressChange::Unchanged => {
                        let ingress = match self
                            .ingress
                            .active()
                            .context("strict Core ingress descriptor is missing")
                            .and_then(|descriptor| descriptor.broker_ingress_set())
                        {
                            Ok(ingress) => ingress,
                            Err(error) => {
                                self.phase = Phase::AwaitBlocking {
                                    revision: policy.revision,
                                };
                                return Err(error.context("build strict Broker ingress set"));
                            }
                        };
                        self.phase = Phase::AwaitCommit {
                            revision: policy.revision,
                        };
                        Ok(StrictOrchestrationAction::Broker(
                            BrokerCommand::CommitPolicy {
                                revision: policy.revision,
                                policy_digest: digest,
                                ingress,
                            },
                        ))
                    }
                }
            }
            Phase::AwaitCommit { revision } => {
                if let Err(error) = self.controller.apply_broker_proof(proof) {
                    self.phase = Phase::AwaitBlocking { revision };
                    return Err(error);
                }
                if self.controller.status().state != StrictState::Armed {
                    self.phase = Phase::AwaitBlocking { revision };
                    bail!("strict proxy policy did not arm");
                }
                self.phase = Phase::Active { revision };
                Ok(StrictOrchestrationAction::Settled(self.status()))
            }
            Phase::AwaitBlocking { revision } => {
                if let Err(error) = self.controller.apply_broker_proof(proof.clone()) {
                    self.phase = Phase::AwaitBlocking { revision };
                    return Err(error);
                }
                if !proves_persistent_blocking_guard(&proof)
                    || proof.core_healthy
                    || proof.relay_healthy
                    || proof.dns_healthy
                {
                    self.controller
                        .backend_lost(StrictReason::BackendUnavailable);
                    self.phase = Phase::AwaitBlocking { revision };
                    bail!("strict Broker did not prove fail-closed blocking state");
                }
                let revoke = match self.ingress.force_revoke() {
                    Ok(revoke) => revoke,
                    Err(error) => {
                        self.phase = Phase::AwaitBlocking { revision };
                        return Err(error);
                    }
                };
                self.phase = Phase::AwaitBlockingRevoke { revision };
                Ok(StrictOrchestrationAction::Core(revoke))
            }
            Phase::AwaitDisable => {
                if proof.revision != 0
                    || proof.policy_digest != "0".repeat(64)
                    || proof.filter_generation != 0
                    || !proof.capabilities.is_empty()
                    || proof.guard_filters_installed
                    || proof.recovery_marker_present
                    || proof.core_healthy
                    || proof.relay_healthy
                    || proof.dns_healthy
                {
                    self.phase = Phase::AwaitDisable;
                    bail!("strict Broker retained policy state after disable");
                }
                let revoke = match self.ingress.force_revoke() {
                    Ok(revoke) => revoke,
                    Err(error) => {
                        self.phase = Phase::AwaitDisable;
                        return Err(error);
                    }
                };
                self.phase = Phase::AwaitDisableRevoke;
                Ok(StrictOrchestrationAction::Core(revoke))
            }
            other => {
                self.phase = other;
                bail!("strict Broker proof arrived in the wrong orchestration phase")
            }
        }
    }

    pub fn accept_core_response(
        &mut self,
        response_line: &str,
    ) -> Result<StrictOrchestrationAction> {
        let phase = std::mem::replace(&mut self.phase, Phase::Idle);
        match phase {
            Phase::AwaitIngress { revision, digest } => {
                let descriptor = match self.ingress.complete(response_line) {
                    Ok(Some(descriptor)) => descriptor,
                    Ok(None) => {
                        self.phase = Phase::AwaitBlocking { revision };
                        bail!("strict Core returned an empty proxy ingress")
                    }
                    Err(error) => {
                        self.phase = Phase::AwaitBlocking { revision };
                        return Err(error.context("configure strict Core ingress"));
                    }
                };
                let ingress = match descriptor.broker_ingress_set() {
                    Ok(ingress) => ingress,
                    Err(error) => {
                        self.phase = Phase::AwaitBlocking { revision };
                        return Err(error.context("build strict Broker ingress set"));
                    }
                };
                self.phase = Phase::AwaitCommit { revision };
                Ok(StrictOrchestrationAction::Broker(
                    BrokerCommand::CommitPolicy {
                        revision,
                        policy_digest: digest,
                        ingress,
                    },
                ))
            }
            Phase::AwaitBlockingRevoke { revision } => {
                if let Err(error) = self.ingress.complete(response_line) {
                    self.phase = Phase::AwaitBlockingRevoke { revision };
                    return Err(error.context("revoke strict Core ingress after blocking"));
                }
                self.phase = Phase::Blocked { revision };
                Ok(StrictOrchestrationAction::Settled(self.status()))
            }
            Phase::AwaitDisableRevoke => {
                if let Err(error) = self.ingress.complete(response_line) {
                    self.phase = Phase::AwaitDisableRevoke;
                    return Err(error.context("revoke strict Core ingress after disable"));
                }
                if !self.controller.confirm_disabled(false, false) {
                    self.phase = Phase::AwaitDisable;
                    bail!("strict controller rejected completed disable transition");
                }
                self.phase = Phase::Idle;
                Ok(StrictOrchestrationAction::Settled(self.status()))
            }
            other => {
                self.phase = other;
                bail!("strict Core response arrived in the wrong orchestration phase")
            }
        }
    }

    /// Starts fail-closed recovery after Core configuration or Broker commit
    /// becomes uncertain. Broker blocking always precedes Core ingress revoke.
    pub fn force_blocking(&mut self) -> Result<StrictOrchestrationAction> {
        let revision = match self.phase {
            Phase::AwaitIngress { revision, .. }
            | Phase::AwaitCommit { revision }
            | Phase::AwaitBlocking { revision }
            | Phase::Active { revision }
            | Phase::Blocked { revision } => revision,
            _ => bail!("strict policy is not in a blockable orchestration phase"),
        };
        self.controller
            .backend_lost(StrictReason::BackendUnavailable);
        self.phase = Phase::AwaitBlocking { revision };
        Ok(StrictOrchestrationAction::Broker(
            BrokerCommand::ForceBlocking { revision },
        ))
    }

    pub fn disable(&mut self) -> Result<StrictOrchestrationAction> {
        let revision = match self.phase {
            Phase::Active { revision } | Phase::Blocked { revision } => revision,
            _ => bail!("strict policy is not active"),
        };
        self.controller.request_disable();
        self.phase = Phase::AwaitDisable;
        Ok(StrictOrchestrationAction::Broker(
            BrokerCommand::DisablePolicy { revision },
        ))
    }

    pub fn retry_core_revoke(&mut self) -> Result<StrictOrchestrationAction> {
        match self.phase {
            Phase::AwaitBlockingRevoke { revision } => {
                let revoke = self.ingress.force_revoke()?;
                self.phase = Phase::AwaitBlockingRevoke { revision };
                Ok(StrictOrchestrationAction::Core(revoke))
            }
            Phase::AwaitDisableRevoke => {
                let revoke = self.ingress.force_revoke()?;
                self.phase = Phase::AwaitDisableRevoke;
                Ok(StrictOrchestrationAction::Core(revoke))
            }
            _ => bail!("strict Core revoke is not pending"),
        }
    }
}

fn proves_persistent_blocking_guard(proof: &BrokerProof) -> bool {
    proof.filter_generation > 0
        && proof.guard_filters_installed
        && proof.recovery_marker_present
        && StrictCapability::required_for_block_only().is_subset(&proof.capabilities)
}

#[cfg(test)]
mod tests {
    use serde_json::{json, Value};

    use flclash_strict_contract::{
        BrokerProof, StrictCapability, StrictIdentity, StrictPolicyEntry,
    };

    use super::*;

    fn identity(character: char) -> StrictIdentity {
        StrictIdentity {
            identity_id: format!("{character}0000000-0000-4000-8000-000000000001"),
            canonical_path: format!(r"C:\Apps\{character}.exe"),
            wfp_app_id_sha256: std::iter::repeat_n(character, 64).collect(),
            publisher_certificate_sha256: "b".repeat(64),
            verified_children: Vec::new(),
        }
    }

    fn policy() -> StrictPolicyBundle {
        StrictPolicyBundle::new(
            7,
            vec![StrictPolicyEntry::proxy(identity('a'), "GLOBAL".into())],
        )
        .unwrap()
    }

    fn blocking_proof(policy: &StrictPolicyBundle) -> BrokerProof {
        BrokerProof {
            revision: policy.revision,
            policy_digest: policy.canonical_digest().unwrap(),
            filter_generation: 3,
            capabilities: StrictCapability::required_for_block_only(),
            guard_filters_installed: true,
            recovery_marker_present: true,
            core_healthy: false,
            relay_healthy: false,
            dns_healthy: false,
        }
    }

    fn armed_proof(policy: &StrictPolicyBundle) -> BrokerProof {
        BrokerProof {
            capabilities: StrictCapability::required_for_proxy(),
            core_healthy: true,
            relay_healthy: true,
            dns_healthy: true,
            ..blocking_proof(policy)
        }
    }

    fn disabled_proof() -> BrokerProof {
        BrokerProof {
            revision: 0,
            policy_digest: "0".repeat(64),
            filter_generation: 0,
            capabilities: BTreeSet::new(),
            guard_filters_installed: false,
            recovery_marker_present: false,
            core_healthy: false,
            relay_healthy: false,
            dns_healthy: false,
        }
    }

    fn core_response(action: &StrictIngressCoreAction, ports: &[u16]) -> String {
        let line: Value = serde_json::from_str(action.line()).unwrap();
        let request: Value = serde_json::from_str(line["data"].as_str().unwrap()).unwrap();
        let entries = request["entries"]
            .as_array()
            .unwrap()
            .iter()
            .zip(ports)
            .map(|(entry, port)| {
                json!({
                    "targetGroup": entry["targetGroup"],
                    "endpoint": format!("127.0.0.1:{port}"),
                })
            })
            .collect::<Vec<_>>();
        json!({
            "id": action.id(),
            "method": "configureStrictIngress",
            "code": 0,
            "data": {
                "protocol": 1,
                "generation": action.generation(),
                "entries": entries,
            }
        })
        .to_string()
    }

    #[test]
    fn proxy_policy_orders_prepare_core_and_commit_before_armed() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        assert!(matches!(
            flow.begin(policy.clone()).unwrap(),
            StrictOrchestrationAction::Broker(BrokerCommand::PreparePolicy { .. })
        ));
        let StrictOrchestrationAction::Core(core) =
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap()
        else {
            panic!("expected Core ingress action");
        };
        let commit = flow
            .accept_core_response(&core_response(&core, &[41001]))
            .unwrap();
        assert!(matches!(
            commit,
            StrictOrchestrationAction::Broker(BrokerCommand::CommitPolicy { .. })
        ));
        assert!(matches!(
            flow.accept_broker_proof(armed_proof(&policy)).unwrap(),
            StrictOrchestrationAction::Settled(StrictStatus {
                state: StrictState::Armed,
                ..
            })
        ));
    }

    #[test]
    fn proxy_policy_cannot_arm_before_core_ingress_is_committed() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        flow.begin(policy.clone()).unwrap();

        assert!(flow.accept_broker_proof(armed_proof(&policy)).is_err());
        assert_eq!(flow.status().state, StrictState::Blocking);
        assert!(matches!(
            flow.force_blocking().unwrap(),
            StrictOrchestrationAction::Broker(BrokerCommand::ForceBlocking { revision: 7 })
        ));
    }

    #[test]
    fn prepare_requires_every_persistent_blocking_capability() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        flow.begin(policy.clone()).unwrap();
        let mut incomplete = blocking_proof(&policy);
        incomplete
            .capabilities
            .remove(&StrictCapability::RecoveryVerified);

        assert!(flow.accept_broker_proof(incomplete).is_err());
        assert!(matches!(
            flow.force_blocking().unwrap(),
            StrictOrchestrationAction::Broker(BrokerCommand::ForceBlocking { revision: 7 })
        ));
    }

    #[test]
    fn ambiguous_core_result_blocks_broker_before_revoking_core() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        flow.begin(policy.clone()).unwrap();
        let StrictOrchestrationAction::Core(_) =
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap()
        else {
            panic!("expected Core ingress action");
        };
        assert!(flow.accept_core_response(r#"{"id":"wrong"}"#).is_err());
        assert!(matches!(
            flow.force_blocking().unwrap(),
            StrictOrchestrationAction::Broker(BrokerCommand::ForceBlocking { revision: 7 })
        ));
        let StrictOrchestrationAction::Core(revoke) =
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap()
        else {
            panic!("expected explicit Core revoke");
        };
        assert!(matches!(
            flow.accept_core_response(&core_response(&revoke, &[]))
                .unwrap(),
            StrictOrchestrationAction::Settled(StrictStatus {
                state: StrictState::Blocking,
                ..
            })
        ));
    }

    #[test]
    fn armed_proof_cannot_bypass_force_blocking_before_core_revoke() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        flow.begin(policy.clone()).unwrap();
        let StrictOrchestrationAction::Core(core) =
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap()
        else {
            panic!("expected Core ingress action");
        };
        flow.accept_core_response(&core_response(&core, &[41001]))
            .unwrap();
        flow.accept_broker_proof(armed_proof(&policy)).unwrap();

        flow.force_blocking().unwrap();
        assert!(flow.accept_broker_proof(armed_proof(&policy)).is_err());
        assert_eq!(flow.status().state, StrictState::Blocking);
        assert!(matches!(
            flow.force_blocking().unwrap(),
            StrictOrchestrationAction::Broker(BrokerCommand::ForceBlocking { revision: 7 })
        ));
        assert!(matches!(
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap(),
            StrictOrchestrationAction::Core(_)
        ));
    }

    #[test]
    fn disable_removes_broker_policy_before_core_ingress() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        flow.begin(policy.clone()).unwrap();
        let StrictOrchestrationAction::Core(core) =
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap()
        else {
            panic!("expected Core action");
        };
        flow.accept_core_response(&core_response(&core, &[41001]))
            .unwrap();
        flow.accept_broker_proof(armed_proof(&policy)).unwrap();

        assert!(matches!(
            flow.disable().unwrap(),
            StrictOrchestrationAction::Broker(BrokerCommand::DisablePolicy { revision: 7 })
        ));
        let StrictOrchestrationAction::Core(revoke) =
            flow.accept_broker_proof(disabled_proof()).unwrap()
        else {
            panic!("expected Core revoke after Broker disable");
        };
        assert_eq!(flow.status().state, StrictState::Blocking);
        assert_eq!(flow.status().reason, StrictReason::CleanupPending);
        assert!(flow.accept_core_response(r#"{"id":"wrong"}"#).is_err());
        let StrictOrchestrationAction::Core(retry) = flow.retry_core_revoke().unwrap() else {
            panic!("expected a fresh Core revoke retry");
        };
        assert!(retry.generation() > revoke.generation());
        assert!(matches!(
            flow.accept_core_response(&core_response(&retry, &[]))
                .unwrap(),
            StrictOrchestrationAction::Settled(StrictStatus {
                state: StrictState::Disabled,
                ..
            })
        ));
    }

    #[test]
    fn disable_rejects_any_residual_broker_capability_before_core_revoke() {
        let policy = policy();
        let mut flow = StrictPolicyOrchestrator::default();
        flow.begin(policy.clone()).unwrap();
        let StrictOrchestrationAction::Core(core) =
            flow.accept_broker_proof(blocking_proof(&policy)).unwrap()
        else {
            panic!("expected Core action");
        };
        flow.accept_core_response(&core_response(&core, &[41001]))
            .unwrap();
        flow.accept_broker_proof(armed_proof(&policy)).unwrap();
        flow.disable().unwrap();

        let mut residual = disabled_proof();
        residual.capabilities.insert(StrictCapability::DriverSigned);
        assert!(flow.accept_broker_proof(residual).is_err());
        assert!(matches!(
            flow.accept_broker_proof(disabled_proof()).unwrap(),
            StrictOrchestrationAction::Core(_)
        ));
    }
}
