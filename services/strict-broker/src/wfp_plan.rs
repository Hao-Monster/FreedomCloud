use std::collections::BTreeSet;
use std::sync::Arc;

use anyhow::{bail, Result};
use flclash_strict_contract::{StrictAction, StrictPolicyBundle};
use sha2::{Digest, Sha256};

use crate::VerifiedPolicyAppIds;

const PROVIDER_KEY: WfpObjectKey = WfpObjectKey::from_bytes([
    0x8f, 0xcc, 0x2c, 0x06, 0x8e, 0xa4, 0x48, 0x9d, 0x9d, 0x7c, 0x84, 0x20, 0x67, 0x67, 0x44, 0x01,
]);
const SUBLAYER_KEY: WfpObjectKey = WfpObjectKey::from_bytes([
    0xb5, 0xa2, 0x7a, 0x68, 0x66, 0x3d, 0x4e, 0x23, 0x9d, 0x65, 0x75, 0xc4, 0x3a, 0xb7, 0x0a, 0x02,
]);
const GUARD_V4_CALLOUT_KEY: WfpObjectKey = WfpObjectKey::from_bytes([
    0x4e, 0x5d, 0x3f, 0x4c, 0x0e, 0xf1, 0x45, 0x36, 0xac, 0xf0, 0x21, 0x18, 0xce, 0x60, 0x40, 0x31,
]);
const GUARD_V6_CALLOUT_KEY: WfpObjectKey = WfpObjectKey::from_bytes([
    0x0b, 0x69, 0x9f, 0x20, 0x38, 0x67, 0x44, 0xa0, 0x93, 0x4b, 0x3e, 0xf8, 0x43, 0xc6, 0xf7, 0x32,
]);
const REDIRECT_V4_CALLOUT_KEY: WfpObjectKey = WfpObjectKey::from_bytes([
    0xfa, 0x8a, 0x9b, 0xa7, 0x64, 0x2c, 0x43, 0xee, 0xa6, 0xe6, 0x71, 0xd0, 0x76, 0xc9, 0x53, 0x41,
]);
const REDIRECT_V6_CALLOUT_KEY: WfpObjectKey = WfpObjectKey::from_bytes([
    0x9a, 0xd0, 0x4f, 0x4e, 0x33, 0x42, 0x46, 0xc0, 0xa1, 0xa2, 0xf1, 0x54, 0x4d, 0xc1, 0xaf, 0x42,
]);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct WfpObjectKey([u8; 16]);

impl WfpObjectKey {
    pub const fn from_bytes(bytes: [u8; 16]) -> Self {
        Self(bytes)
    }

    pub const fn as_bytes(self) -> [u8; 16] {
        self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WfpLayer {
    AuthConnectV4,
    AuthConnectV6,
    ConnectRedirectV4,
    ConnectRedirectV6,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WfpCallout {
    FailClosedGuardV4,
    FailClosedGuardV6,
    ConnectRedirectV4,
    ConnectRedirectV6,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WfpFilterLifetime {
    Persistent,
    Dynamic,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WfpFilterSpec {
    key: WfpObjectKey,
    layer: WfpLayer,
    callout: WfpCallout,
    callout_key: WfpObjectKey,
    lifetime: WfpFilterLifetime,
    identity_id: String,
    app_id: Arc<[u8]>,
    action: StrictAction,
    indexed: bool,
    clear_action_right: bool,
}

impl WfpFilterSpec {
    pub fn key(&self) -> WfpObjectKey {
        self.key
    }

    pub fn layer(&self) -> WfpLayer {
        self.layer
    }

    pub fn callout(&self) -> WfpCallout {
        self.callout
    }

    pub fn callout_key(&self) -> WfpObjectKey {
        self.callout_key
    }

    pub fn lifetime(&self) -> WfpFilterLifetime {
        self.lifetime
    }

    pub fn identity_id(&self) -> &str {
        &self.identity_id
    }

    pub fn app_id(&self) -> &[u8] {
        &self.app_id
    }

    pub fn action(&self) -> StrictAction {
        self.action
    }

    pub fn is_indexed(&self) -> bool {
        self.indexed
    }

    pub fn clears_action_right(&self) -> bool {
        self.clear_action_right
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DriverIdentityRule {
    identity_id: String,
    family_index: u16,
    member_index: u8,
    app_id: Arc<[u8]>,
    action: StrictAction,
    target_group_index: Option<u16>,
}

impl DriverIdentityRule {
    pub fn identity_id(&self) -> &str {
        &self.identity_id
    }

    pub fn family_index(&self) -> u16 {
        self.family_index
    }

    pub fn member_index(&self) -> u8 {
        self.member_index
    }

    pub fn app_id(&self) -> &[u8] {
        &self.app_id
    }

    pub fn action(&self) -> StrictAction {
        self.action
    }

    pub fn target_group_index(&self) -> Option<u16> {
        self.target_group_index
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanInstallStep {
    UploadImmutableSnapshot,
    InstallPersistentGuards,
    InstallDynamicRedirects,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanRemoveStep {
    RemoveDynamicRedirects,
    RemovePersistentGuards,
    UnloadImmutableSnapshot,
}

pub struct WfpPolicyPlan {
    revision: u64,
    policy_digest: String,
    rules: Vec<DriverIdentityRule>,
    target_groups: Vec<String>,
    guard_filters: Vec<WfpFilterSpec>,
    redirect_filters: Vec<WfpFilterSpec>,
    install_steps: Vec<PlanInstallStep>,
    remove_steps: Vec<PlanRemoveStep>,
}

impl WfpPolicyPlan {
    pub const fn canonical_provider_key() -> WfpObjectKey {
        PROVIDER_KEY
    }

    pub const fn canonical_sublayer_key() -> WfpObjectKey {
        SUBLAYER_KEY
    }

    pub fn new(policy: &StrictPolicyBundle, verified: &VerifiedPolicyAppIds) -> Result<Self> {
        policy.validate()?;
        if verified.application_count() != policy.entries.len() {
            bail!("verified WFP application identities do not match the policy plan");
        }
        let target_groups: Vec<String> = policy
            .entries
            .iter()
            .filter_map(|entry| entry.target_group.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let mut rules = Vec::with_capacity(verified.app_id_count());
        for (family_index, (entry, verified_family)) in policy
            .entries
            .iter()
            .zip(verified.applications())
            .enumerate()
        {
            if entry.identity.identity_id != verified_family.identity_id() {
                bail!("verified WFP application family does not match the policy plan");
            }
            let target_group_index = entry
                .target_group
                .as_ref()
                .map(|target| {
                    target_groups
                        .binary_search(target)
                        .map(|index| index as u16)
                })
                .transpose()
                .map_err(|_| anyhow::anyhow!("strict target group is missing from its plan"))?;
            for (member_index, app_id) in verified_family.app_ids().iter().enumerate() {
                rules.push(DriverIdentityRule {
                    identity_id: entry.identity.identity_id.clone(),
                    family_index: family_index as u16,
                    member_index: member_index as u8,
                    app_id: Arc::from(app_id.clone()),
                    action: entry.action,
                    target_group_index,
                });
            }
        }
        rules.sort_unstable_by(|left, right| left.app_id.cmp(&right.app_id));

        let has_proxy = policy
            .entries
            .iter()
            .any(|entry| entry.action == StrictAction::Proxy);
        let mut guard_filters = Vec::with_capacity(rules.len() * 2);
        let proxy_rule_count = rules
            .iter()
            .filter(|rule| rule.action == StrictAction::Proxy)
            .count();
        let mut redirect_filters = Vec::with_capacity(proxy_rule_count * 2);
        // These filters intentionally carry exact App-ID conditions. Windows treats an
        // unavailable terminating callout as block; a global filter could therefore
        // block the whole host while per-identity filters fail closed only for selected apps.
        for rule in &rules {
            guard_filters.extend([
                filter(
                    rule,
                    0x11,
                    WfpLayer::AuthConnectV4,
                    WfpCallout::FailClosedGuardV4,
                    GUARD_V4_CALLOUT_KEY,
                    WfpFilterLifetime::Persistent,
                ),
                filter(
                    rule,
                    0x12,
                    WfpLayer::AuthConnectV6,
                    WfpCallout::FailClosedGuardV6,
                    GUARD_V6_CALLOUT_KEY,
                    WfpFilterLifetime::Persistent,
                ),
            ]);
            if rule.action == StrictAction::Proxy {
                redirect_filters.extend([
                    filter(
                        rule,
                        0x21,
                        WfpLayer::ConnectRedirectV4,
                        WfpCallout::ConnectRedirectV4,
                        REDIRECT_V4_CALLOUT_KEY,
                        WfpFilterLifetime::Dynamic,
                    ),
                    filter(
                        rule,
                        0x22,
                        WfpLayer::ConnectRedirectV6,
                        WfpCallout::ConnectRedirectV6,
                        REDIRECT_V6_CALLOUT_KEY,
                        WfpFilterLifetime::Dynamic,
                    ),
                ]);
            }
        }
        let mut install_steps = vec![
            PlanInstallStep::UploadImmutableSnapshot,
            PlanInstallStep::InstallPersistentGuards,
        ];
        let mut remove_steps = Vec::new();
        if has_proxy {
            install_steps.push(PlanInstallStep::InstallDynamicRedirects);
            remove_steps.push(PlanRemoveStep::RemoveDynamicRedirects);
        }
        remove_steps.extend([
            PlanRemoveStep::RemovePersistentGuards,
            PlanRemoveStep::UnloadImmutableSnapshot,
        ]);
        Ok(Self {
            revision: policy.revision,
            policy_digest: policy.canonical_digest()?,
            rules,
            target_groups,
            guard_filters,
            redirect_filters,
            install_steps,
            remove_steps,
        })
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn policy_digest(&self) -> &str {
        &self.policy_digest
    }

    pub fn provider_key(&self) -> WfpObjectKey {
        PROVIDER_KEY
    }

    pub fn sublayer_key(&self) -> WfpObjectKey {
        SUBLAYER_KEY
    }

    pub fn rules(&self) -> &[DriverIdentityRule] {
        &self.rules
    }

    pub fn target_groups(&self) -> &[String] {
        &self.target_groups
    }

    pub fn guard_filters(&self) -> &[WfpFilterSpec] {
        &self.guard_filters
    }

    pub fn redirect_filters(&self) -> &[WfpFilterSpec] {
        &self.redirect_filters
    }

    pub fn install_steps(&self) -> &[PlanInstallStep] {
        &self.install_steps
    }

    pub fn remove_steps(&self) -> &[PlanRemoveStep] {
        &self.remove_steps
    }

    pub fn owns_filter_key(&self, key: WfpObjectKey) -> bool {
        self.guard_filters
            .iter()
            .chain(&self.redirect_filters)
            .any(|filter| filter.key == key)
    }
}

fn filter(
    rule: &DriverIdentityRule,
    key_namespace: u8,
    layer: WfpLayer,
    callout: WfpCallout,
    callout_key: WfpObjectKey,
    lifetime: WfpFilterLifetime,
) -> WfpFilterSpec {
    WfpFilterSpec {
        key: derived_filter_key(key_namespace, &rule.app_id),
        layer,
        callout,
        callout_key,
        lifetime,
        identity_id: rule.identity_id.clone(),
        app_id: Arc::clone(&rule.app_id),
        action: rule.action,
        indexed: true,
        clear_action_right: true,
    }
}

fn derived_filter_key(namespace: u8, app_id: &[u8]) -> WfpObjectKey {
    let mut hash = Sha256::new();
    hash.update(PROVIDER_KEY.0);
    hash.update([namespace]);
    hash.update(app_id);
    let digest = hash.finalize();
    let mut bytes = [0_u8; 16];
    bytes.copy_from_slice(&digest[..16]);
    // UUIDv8 marks this as a deterministic custom key rather than a random UUID.
    bytes[6] = (bytes[6] & 0x0f) | 0x80;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    WfpObjectKey(bytes)
}

pub(crate) fn expected_filter_key(layer: WfpLayer, app_id: &[u8]) -> WfpObjectKey {
    let namespace = match layer {
        WfpLayer::AuthConnectV4 => 0x11,
        WfpLayer::AuthConnectV6 => 0x12,
        WfpLayer::ConnectRedirectV4 => 0x21,
        WfpLayer::ConnectRedirectV6 => 0x22,
    };
    derived_filter_key(namespace, app_id)
}

pub(crate) fn expected_callout_key(layer: WfpLayer) -> WfpObjectKey {
    match layer {
        WfpLayer::AuthConnectV4 => GUARD_V4_CALLOUT_KEY,
        WfpLayer::AuthConnectV6 => GUARD_V6_CALLOUT_KEY,
        WfpLayer::ConnectRedirectV4 => REDIRECT_V4_CALLOUT_KEY,
        WfpLayer::ConnectRedirectV6 => REDIRECT_V6_CALLOUT_KEY,
    }
}
