use std::collections::BTreeSet;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

pub const MAX_STRICT_APPLICATIONS: usize = 128;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum StrictState {
    Disabled,
    Preparing,
    Blocking,
    Armed,
    Recovering,
}

impl StrictState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::Preparing => "preparing",
            Self::Blocking => "blocking",
            Self::Armed => "armed",
            Self::Recovering => "recovering",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum StrictReason {
    None,
    Preparing,
    GuardNotInstalled,
    MissingCapability,
    CoreUnavailable,
    RelayUnavailable,
    DnsUnavailable,
    BackendUnavailable,
    CleanupPending,
}

impl StrictReason {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Preparing => "preparing",
            Self::GuardNotInstalled => "guardNotInstalled",
            Self::MissingCapability => "missingCapability",
            Self::CoreUnavailable => "coreUnavailable",
            Self::RelayUnavailable => "relayUnavailable",
            Self::DnsUnavailable => "dnsUnavailable",
            Self::BackendUnavailable => "backendUnavailable",
            Self::CleanupPending => "cleanupPending",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum StrictCapability {
    DriverSigned,
    IdentityVerified,
    Tcp4Redirect,
    Tcp6Redirect,
    Udp4Redirect,
    Udp6Redirect,
    DnsCaptured,
    QuicCaptured,
    RedirectLoopProtected,
    PersistentFailClosed,
    RecoveryVerified,
}

impl StrictCapability {
    fn required_for_block_only() -> BTreeSet<Self> {
        [
            Self::DriverSigned,
            Self::IdentityVerified,
            Self::PersistentFailClosed,
            Self::RecoveryVerified,
        ]
        .into_iter()
        .collect()
    }

    pub fn required_for_proxy() -> BTreeSet<Self> {
        [
            Self::DriverSigned,
            Self::IdentityVerified,
            Self::Tcp4Redirect,
            Self::Tcp6Redirect,
            Self::Udp4Redirect,
            Self::Udp6Redirect,
            Self::DnsCaptured,
            Self::QuicCaptured,
            Self::RedirectLoopProtected,
            Self::PersistentFailClosed,
            Self::RecoveryVerified,
        ]
        .into_iter()
        .collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StrictIntent {
    pub revision: u64,
    pub policy_digest: String,
    pub proxy_application_count: usize,
    pub blocked_application_count: usize,
    pub required_capabilities: BTreeSet<StrictCapability>,
}

impl StrictIntent {
    pub fn new(
        revision: u64,
        policy_digest: String,
        proxy_application_count: usize,
        blocked_application_count: usize,
    ) -> Result<Self> {
        let application_count = proxy_application_count
            .checked_add(blocked_application_count)
            .ok_or_else(|| anyhow::anyhow!("strict application count overflow"))?;
        if revision == 0 {
            bail!("strict policy revision must be positive");
        }
        if !is_sha256(&policy_digest) {
            bail!("strict policy digest must be a 64-character SHA-256 value");
        }
        if application_count == 0 || application_count > MAX_STRICT_APPLICATIONS {
            bail!("strict policy must contain between 1 and {MAX_STRICT_APPLICATIONS} apps");
        }
        let required_capabilities = if proxy_application_count == 0 {
            StrictCapability::required_for_block_only()
        } else {
            StrictCapability::required_for_proxy()
        };
        Ok(Self {
            revision,
            policy_digest: policy_digest.to_ascii_lowercase(),
            proxy_application_count,
            blocked_application_count,
            required_capabilities,
        })
    }
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BrokerProof {
    pub revision: u64,
    pub policy_digest: String,
    pub filter_generation: u64,
    pub capabilities: BTreeSet<StrictCapability>,
    pub guard_filters_installed: bool,
    pub recovery_marker_present: bool,
    pub core_healthy: bool,
    pub relay_healthy: bool,
    pub dns_healthy: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StrictStatus {
    pub state: StrictState,
    pub reason: StrictReason,
    pub revision: Option<u64>,
    pub filter_generation: Option<u64>,
}

#[derive(Debug)]
pub struct StrictController {
    desired: Option<StrictIntent>,
    state: StrictState,
    reason: StrictReason,
    filter_generation: Option<u64>,
    disabling: bool,
}

impl Default for StrictController {
    fn default() -> Self {
        Self {
            desired: None,
            state: StrictState::Disabled,
            reason: StrictReason::None,
            filter_generation: None,
            disabling: false,
        }
    }
}

impl StrictController {
    pub fn status(&self) -> StrictStatus {
        StrictStatus {
            state: self.state,
            reason: self.reason,
            revision: self.desired.as_ref().map(|intent| intent.revision),
            filter_generation: self.filter_generation,
        }
    }

    pub fn begin(&mut self, intent: StrictIntent) -> Result<()> {
        if self.disabling {
            bail!("strict policy cleanup is still pending");
        }
        if let Some(current) = &self.desired {
            if intent.revision < current.revision {
                bail!("strict policy revision rollback rejected");
            }
            if intent.revision == current.revision {
                if &intent != current {
                    bail!("strict policy revision has different content");
                }
                self.state = StrictState::Preparing;
                self.reason = StrictReason::Preparing;
                self.filter_generation = None;
                return Ok(());
            }
        }
        self.desired = Some(intent);
        self.state = StrictState::Preparing;
        self.reason = StrictReason::Preparing;
        self.filter_generation = None;
        Ok(())
    }

    pub fn apply_broker_proof(&mut self, proof: BrokerProof) -> Result<()> {
        let Some(desired) = self.desired.as_ref() else {
            bail!("strict policy proof received without desired policy");
        };
        if proof.revision != desired.revision
            || !proof
                .policy_digest
                .eq_ignore_ascii_case(&desired.policy_digest)
        {
            bail!("strict policy proof does not match desired revision and digest");
        }

        self.filter_generation = (proof.filter_generation > 0).then_some(proof.filter_generation);
        if proof.filter_generation == 0
            || !proof.guard_filters_installed
            || !proof.recovery_marker_present
        {
            self.block(StrictReason::GuardNotInstalled);
        } else if !desired.required_capabilities.is_subset(&proof.capabilities) {
            self.block(StrictReason::MissingCapability);
        } else if desired.proxy_application_count > 0 && !proof.core_healthy {
            self.block(StrictReason::CoreUnavailable);
        } else if desired.proxy_application_count > 0 && !proof.relay_healthy {
            self.block(StrictReason::RelayUnavailable);
        } else if desired.proxy_application_count > 0 && !proof.dns_healthy {
            self.block(StrictReason::DnsUnavailable);
        } else {
            self.state = StrictState::Armed;
            self.reason = StrictReason::None;
        }
        Ok(())
    }

    pub fn backend_lost(&mut self, reason: StrictReason) {
        if self.desired.is_some() {
            self.block(if reason == StrictReason::None {
                StrictReason::BackendUnavailable
            } else {
                reason
            });
        }
    }

    pub fn begin_recovery(&mut self) {
        if self.desired.is_some() {
            self.state = StrictState::Recovering;
            self.reason = StrictReason::BackendUnavailable;
        }
    }

    pub fn request_disable(&mut self) {
        if self.desired.is_none() {
            return;
        }
        self.disabling = true;
        self.block(StrictReason::CleanupPending);
    }

    pub fn confirm_disabled(
        &mut self,
        provider_filters_remaining: bool,
        recovery_marker_present: bool,
    ) -> bool {
        if !self.disabling {
            return false;
        }
        if provider_filters_remaining || recovery_marker_present {
            self.block(StrictReason::CleanupPending);
            return false;
        }
        self.desired = None;
        self.state = StrictState::Disabled;
        self.reason = StrictReason::None;
        self.filter_generation = None;
        self.disabling = false;
        true
    }

    fn block(&mut self, reason: StrictReason) {
        self.state = StrictState::Blocking;
        self.reason = reason;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn digest(character: char) -> String {
        std::iter::repeat_n(character, 64).collect()
    }

    fn complete_proof(intent: &StrictIntent) -> BrokerProof {
        BrokerProof {
            revision: intent.revision,
            policy_digest: intent.policy_digest.clone(),
            filter_generation: 7,
            capabilities: StrictCapability::required_for_proxy(),
            guard_filters_installed: true,
            recovery_marker_present: true,
            core_healthy: true,
            relay_healthy: true,
            dns_healthy: true,
        }
    }

    #[test]
    fn intent_is_bounded_and_requires_a_canonical_digest() {
        assert!(StrictIntent::new(0, digest('a'), 1, 0).is_err());
        assert!(StrictIntent::new(1, "not-a-digest".into(), 1, 0).is_err());
        assert!(StrictIntent::new(1, digest('a'), 0, 0).is_err());
        assert!(StrictIntent::new(1, digest('a'), 129, 0).is_err());
        assert!(StrictIntent::new(1, digest('a'), 64, 64).is_ok());
    }

    #[test]
    fn strict_mode_cannot_arm_before_the_persistent_guard_exists() {
        let intent = StrictIntent::new(1, digest('a'), 1, 0).unwrap();
        let mut controller = StrictController::default();
        controller.begin(intent.clone()).unwrap();
        let mut proof = complete_proof(&intent);
        proof.guard_filters_installed = false;

        controller.apply_broker_proof(proof).unwrap();

        assert_eq!(controller.status().state, StrictState::Blocking);
        assert_eq!(controller.status().reason, StrictReason::GuardNotInstalled);
    }

    #[test]
    fn complete_matching_capabilities_are_required_to_arm() {
        let intent = StrictIntent::new(3, digest('b'), 1, 1).unwrap();
        let mut controller = StrictController::default();
        controller.begin(intent.clone()).unwrap();
        let mut proof = complete_proof(&intent);
        proof.capabilities.remove(&StrictCapability::QuicCaptured);

        controller.apply_broker_proof(proof).unwrap();

        assert_eq!(controller.status().state, StrictState::Blocking);
        assert_eq!(controller.status().reason, StrictReason::MissingCapability);

        controller
            .apply_broker_proof(complete_proof(&intent))
            .unwrap();
        assert_eq!(controller.status().state, StrictState::Armed);
        assert_eq!(controller.status().filter_generation, Some(7));
    }

    #[test]
    fn every_proxy_capability_is_mandatory() {
        let intent = StrictIntent::new(4, digest('9'), 1, 0).unwrap();
        for missing in StrictCapability::required_for_proxy() {
            let mut controller = StrictController::default();
            controller.begin(intent.clone()).unwrap();
            let mut proof = complete_proof(&intent);
            proof.capabilities.remove(&missing);
            controller.apply_broker_proof(proof).unwrap();
            assert_eq!(
                controller.status().state,
                StrictState::Blocking,
                "removing {missing:?} must fail closed"
            );
        }
    }

    #[test]
    fn block_only_policy_does_not_claim_proxy_capabilities() {
        let intent = StrictIntent::new(2, digest('8'), 0, 1).unwrap();
        let mut controller = StrictController::default();
        controller.begin(intent.clone()).unwrap();
        let mut proof = complete_proof(&intent);
        proof.capabilities = StrictCapability::required_for_block_only();
        proof.core_healthy = false;
        proof.relay_healthy = false;
        proof.dns_healthy = false;

        controller.apply_broker_proof(proof).unwrap();

        assert_eq!(controller.status().state, StrictState::Armed);
    }

    #[test]
    fn stale_or_mismatched_attestation_cannot_replace_desired_policy() {
        let first = StrictIntent::new(5, digest('c'), 1, 0).unwrap();
        let second = StrictIntent::new(6, digest('d'), 1, 0).unwrap();
        let mut controller = StrictController::default();
        controller.begin(first.clone()).unwrap();
        controller.begin(second.clone()).unwrap();

        assert!(controller
            .apply_broker_proof(complete_proof(&first))
            .is_err());
        assert_eq!(controller.status().revision, Some(6));
        assert_eq!(controller.status().state, StrictState::Preparing);

        let rollback = StrictIntent::new(5, digest('e'), 1, 0).unwrap();
        assert!(controller.begin(rollback).is_err());

        let conflicting = StrictIntent::new(6, digest('d'), 0, 1).unwrap();
        assert!(controller.begin(conflicting).is_err());
    }

    #[test]
    fn backend_or_core_loss_is_fail_closed() {
        let intent = StrictIntent::new(1, digest('e'), 1, 0).unwrap();
        let mut controller = StrictController::default();
        controller.begin(intent.clone()).unwrap();
        controller
            .apply_broker_proof(complete_proof(&intent))
            .unwrap();
        assert_eq!(controller.status().state, StrictState::Armed);

        controller.backend_lost(StrictReason::CoreUnavailable);

        assert_eq!(controller.status().state, StrictState::Blocking);
        assert_eq!(controller.status().reason, StrictReason::CoreUnavailable);
    }

    #[test]
    fn disable_is_not_complete_while_filters_or_marker_remain() {
        let intent = StrictIntent::new(1, digest('f'), 1, 0).unwrap();
        let mut controller = StrictController::default();
        controller.begin(intent).unwrap();
        assert!(!controller.confirm_disabled(false, false));
        controller.request_disable();
        assert_eq!(controller.status().state, StrictState::Blocking);
        assert_eq!(controller.status().reason, StrictReason::CleanupPending);

        assert!(!controller.confirm_disabled(false, true));
        assert!(!controller.confirm_disabled(true, false));
        assert!(controller.confirm_disabled(false, false));
        assert_eq!(controller.status().state, StrictState::Disabled);
        assert_eq!(controller.status().revision, None);
    }
}
