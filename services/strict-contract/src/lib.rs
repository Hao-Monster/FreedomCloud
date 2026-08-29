use std::collections::BTreeSet;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub const STRICT_PROTOCOL_VERSION: u32 = 1;
pub const MAX_STRICT_APPLICATIONS: usize = 128;
pub const MAX_STRICT_CHILDREN: usize = 32;
pub const MAX_BROKER_FRAME_BYTES: usize = 1024 * 1024;
pub const MAX_BROKER_ACTIVATION_FRAME_BYTES: usize = 4 * 1024;
const BROKER_PIPE_NAME_PREFIX: &str = r"\\.\pipe\FlClashX.StrictBroker.";

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
    pub fn required_for_block_only() -> BTreeSet<Self> {
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

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
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

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StrictChildIdentity {
    pub canonical_path: String,
    pub wfp_app_id_sha256: String,
    pub publisher_certificate_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StrictIdentity {
    pub identity_id: String,
    pub canonical_path: String,
    pub wfp_app_id_sha256: String,
    pub publisher_certificate_sha256: String,
    pub verified_children: Vec<StrictChildIdentity>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum StrictAction {
    Proxy,
    Block,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StrictPolicyEntry {
    pub identity: StrictIdentity,
    pub action: StrictAction,
    pub target_group: Option<String>,
}

impl StrictPolicyEntry {
    pub fn try_new(
        identity: StrictIdentity,
        action: StrictAction,
        target_group: Option<String>,
    ) -> Result<Self> {
        let entry = Self {
            identity,
            action,
            target_group,
        };
        entry.validate()?;
        Ok(entry)
    }

    pub fn proxy(identity: StrictIdentity, target_group: String) -> Self {
        Self {
            identity,
            action: StrictAction::Proxy,
            target_group: Some(target_group),
        }
    }

    pub fn block(identity: StrictIdentity) -> Self {
        Self {
            identity,
            action: StrictAction::Block,
            target_group: None,
        }
    }

    pub fn validate(&self) -> Result<()> {
        validate_identity(&self.identity)?;
        match (&self.action, &self.target_group) {
            (StrictAction::Proxy, Some(target)) => validate_target_group(target),
            (StrictAction::Block, None) => Ok(()),
            (StrictAction::Proxy, None) => bail!("strict proxy action requires a target group"),
            (StrictAction::Block, Some(_)) => {
                bail!("strict block action cannot have a target group")
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StrictPolicyBundle {
    pub protocol: u32,
    pub revision: u64,
    pub entries: Vec<StrictPolicyEntry>,
}

impl StrictPolicyBundle {
    pub fn new(revision: u64, entries: Vec<StrictPolicyEntry>) -> Result<Self> {
        let bundle = Self {
            protocol: STRICT_PROTOCOL_VERSION,
            revision,
            entries,
        };
        bundle.validate()?;
        Ok(bundle)
    }

    pub fn validate(&self) -> Result<()> {
        if self.protocol != STRICT_PROTOCOL_VERSION {
            bail!("unsupported strict policy protocol");
        }
        if self.revision == 0 {
            bail!("strict policy revision must be positive");
        }
        if self.entries.is_empty() || self.entries.len() > MAX_STRICT_APPLICATIONS {
            bail!("strict policy must contain between 1 and {MAX_STRICT_APPLICATIONS} apps");
        }

        let mut identities = BTreeSet::new();
        let mut app_ids = BTreeSet::new();
        for entry in &self.entries {
            entry.validate()?;
            if !identities.insert(entry.identity.identity_id.to_ascii_lowercase()) {
                bail!("strict policy contains a duplicate identity ID");
            }
            if !app_ids.insert(entry.identity.wfp_app_id_sha256.to_ascii_lowercase()) {
                bail!("strict policy contains an ambiguous WFP application identity");
            }
            for child in &entry.identity.verified_children {
                if !app_ids.insert(child.wfp_app_id_sha256.to_ascii_lowercase()) {
                    bail!("strict policy contains an ambiguous child WFP application identity");
                }
            }
        }
        if self.canonical_bytes_unchecked()?.len() > MAX_BROKER_FRAME_BYTES {
            bail!("strict policy exceeds the Broker frame limit");
        }
        Ok(())
    }

    pub fn canonical_bytes(&self) -> Result<Vec<u8>> {
        self.validate()?;
        self.canonical_bytes_unchecked()
    }

    pub fn canonical_digest(&self) -> Result<String> {
        Ok(format!("{:x}", Sha256::digest(self.canonical_bytes()?)))
    }

    fn canonical_bytes_unchecked(&self) -> Result<Vec<u8>> {
        let mut normalized = self.clone();
        normalized.entries.sort_by(|left, right| {
            left.identity
                .identity_id
                .to_ascii_lowercase()
                .cmp(&right.identity.identity_id.to_ascii_lowercase())
        });
        for entry in &mut normalized.entries {
            entry.identity.verified_children.sort_by(|left, right| {
                left.wfp_app_id_sha256
                    .to_ascii_lowercase()
                    .cmp(&right.wfp_app_id_sha256.to_ascii_lowercase())
                    .then_with(|| {
                        left.canonical_path
                            .to_ascii_lowercase()
                            .cmp(&right.canonical_path.to_ascii_lowercase())
                    })
            });
        }
        Ok(serde_json::to_vec(&normalized)?)
    }
}

fn validate_identity(identity: &StrictIdentity) -> Result<()> {
    if !is_uuid(&identity.identity_id) {
        bail!("strict identity ID must be a canonical UUID");
    }
    validate_windows_executable_path(&identity.canonical_path)?;
    validate_sha256(&identity.wfp_app_id_sha256, "WFP application ID")?;
    validate_sha256(
        &identity.publisher_certificate_sha256,
        "publisher certificate",
    )?;
    if identity.verified_children.len() > MAX_STRICT_CHILDREN {
        bail!("strict application family exceeds {MAX_STRICT_CHILDREN} children");
    }
    let mut child_app_ids = BTreeSet::new();
    for child in &identity.verified_children {
        validate_windows_executable_path(&child.canonical_path)?;
        validate_sha256(&child.wfp_app_id_sha256, "child WFP application ID")?;
        validate_sha256(
            &child.publisher_certificate_sha256,
            "child publisher certificate",
        )?;
        if !child
            .publisher_certificate_sha256
            .eq_ignore_ascii_case(&identity.publisher_certificate_sha256)
        {
            bail!("strict child publisher does not match its primary identity");
        }
        if !child_app_ids.insert(child.wfp_app_id_sha256.to_ascii_lowercase()) {
            bail!("strict application family contains a duplicate child identity");
        }
    }
    Ok(())
}

fn validate_windows_executable_path(path: &str) -> Result<()> {
    if path.len() < 3
        || path.len() > 1024
        || path.contains(['\0', '\r', '\n', '/'])
        || !path.to_ascii_lowercase().ends_with(".exe")
    {
        bail!("strict executable path is not canonical");
    }
    let bytes = path.as_bytes();
    let drive_absolute =
        bytes.len() >= 3 && bytes[0].is_ascii_uppercase() && bytes[1] == b':' && bytes[2] == b'\\';
    let unc_absolute = path.starts_with(r"\\") && !path.starts_with(r"\\.\");
    if !drive_absolute && !unc_absolute {
        bail!("strict executable path must be an absolute Windows path");
    }
    if path.split('\\').any(|component| {
        component == "."
            || component == ".."
            || component.ends_with(' ')
            || component.ends_with('.')
    }) {
        bail!("strict executable path contains a non-canonical component");
    }
    Ok(())
}

fn validate_target_group(target: &str) -> Result<()> {
    if target.is_empty()
        || target.len() > 256
        || target.trim() != target
        || target.contains(['\0', '\r', '\n'])
    {
        bail!("strict proxy target group is invalid");
    }
    Ok(())
}

fn validate_sha256(value: &str, label: &str) -> Result<()> {
    if !is_sha256(value) {
        bail!("{label} must be a 64-character SHA-256 value");
    }
    Ok(())
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn is_uuid(value: &str) -> bool {
    value.len() == 36
        && value.bytes().enumerate().all(|(index, byte)| {
            if matches!(index, 8 | 13 | 18 | 23) {
                byte == b'-'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BrokerRequest {
    pub protocol: u32,
    pub request_id: String,
    pub session_capability: String,
    pub command: BrokerCommand,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BrokerActivationRequest {
    pub protocol: u32,
    pub request_id: String,
    pub session_capability: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum BrokerActivationErrorCode {
    Unauthorized,
    Busy,
    Internal,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BrokerActivationResponse {
    pub protocol: u32,
    pub request_id: String,
    pub body: BrokerActivationResponseBody,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "camelCase", deny_unknown_fields)]
pub enum BrokerActivationResponseBody {
    Activated { pipe_name: String },
    Error { code: BrokerActivationErrorCode },
}

impl BrokerActivationResponse {
    pub fn activated(request_id: impl Into<String>, pipe_name: impl Into<String>) -> Result<Self> {
        let response = Self {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: request_id.into(),
            body: BrokerActivationResponseBody::Activated {
                pipe_name: pipe_name.into(),
            },
        };
        response.validate()?;
        Ok(response)
    }

    pub fn error(request_id: impl Into<String>, code: BrokerActivationErrorCode) -> Result<Self> {
        let response = Self {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: request_id.into(),
            body: BrokerActivationResponseBody::Error { code },
        };
        response.validate()?;
        Ok(response)
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>> {
        self.validate()?;
        let encoded = serde_json::to_vec(self)?;
        if encoded.is_empty() || encoded.len() > MAX_BROKER_ACTIVATION_FRAME_BYTES {
            bail!("Broker activation response frame size is invalid");
        }
        Ok(encoded)
    }

    pub fn validate(&self) -> Result<()> {
        if self.protocol != STRICT_PROTOCOL_VERSION {
            bail!("unsupported Broker activation response protocol");
        }
        validate_request_id(&self.request_id)?;
        if let BrokerActivationResponseBody::Activated { pipe_name } = &self.body {
            validate_broker_pipe_name(pipe_name)?;
        }
        Ok(())
    }
}

pub fn parse_broker_activation_request(frame: &[u8]) -> Result<BrokerActivationRequest> {
    if frame.is_empty() || frame.len() > MAX_BROKER_ACTIVATION_FRAME_BYTES {
        bail!("Broker activation frame size is invalid");
    }
    let request: BrokerActivationRequest = serde_json::from_slice(frame)?;
    if request.protocol != STRICT_PROTOCOL_VERSION {
        bail!("unsupported Broker activation protocol");
    }
    validate_request_id(&request.request_id)?;
    validate_sha256(&request.session_capability, "Broker session capability")?;
    if request.session_capability.bytes().all(|byte| byte == b'0') {
        bail!("Broker session capability cannot be zero");
    }
    Ok(request)
}

pub fn parse_broker_activation_response(frame: &[u8]) -> Result<BrokerActivationResponse> {
    if frame.is_empty() || frame.len() > MAX_BROKER_ACTIVATION_FRAME_BYTES {
        bail!("Broker activation response frame size is invalid");
    }
    let response: BrokerActivationResponse = serde_json::from_slice(frame)?;
    response.validate()?;
    Ok(response)
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "camelCase", deny_unknown_fields)]
pub enum BrokerCommand {
    Status {},
    PreparePolicy {
        policy: StrictPolicyBundle,
    },
    CommitPolicy {
        revision: u64,
        policy_digest: String,
    },
    ForceBlocking {
        revision: u64,
    },
    DisablePolicy {
        revision: u64,
    },
    Diagnostics {},
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum BrokerErrorCode {
    InvalidRequest,
    Unauthorized,
    InvalidState,
    IdentityRejected,
    BackendUnavailable,
    PersistenceFailure,
    Internal,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BrokerResponse {
    pub protocol: u32,
    pub request_id: String,
    pub body: BrokerResponseBody,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "camelCase", deny_unknown_fields)]
pub enum BrokerResponseBody {
    Status { proof: BrokerProof },
    Error { code: BrokerErrorCode },
}

impl BrokerResponse {
    pub fn status(request_id: impl Into<String>, proof: BrokerProof) -> Result<Self> {
        let response = Self {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: request_id.into(),
            body: BrokerResponseBody::Status { proof },
        };
        response.validate()?;
        Ok(response)
    }

    pub fn error(request_id: impl Into<String>, code: BrokerErrorCode) -> Result<Self> {
        let response = Self {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: request_id.into(),
            body: BrokerResponseBody::Error { code },
        };
        response.validate()?;
        Ok(response)
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>> {
        self.validate()?;
        let encoded = serde_json::to_vec(self)?;
        if encoded.is_empty() || encoded.len() > MAX_BROKER_FRAME_BYTES {
            bail!("Broker response frame size is invalid");
        }
        Ok(encoded)
    }

    pub fn validate(&self) -> Result<()> {
        if self.protocol != STRICT_PROTOCOL_VERSION {
            bail!("unsupported Broker response protocol");
        }
        validate_request_id(&self.request_id)?;
        if let BrokerResponseBody::Status { proof } = &self.body {
            validate_broker_proof(proof)?;
        }
        Ok(())
    }
}

pub fn parse_broker_request(line: &str) -> Result<BrokerRequest> {
    if line.is_empty() || line.len() > MAX_BROKER_FRAME_BYTES {
        bail!("Broker frame size is invalid");
    }
    let request: BrokerRequest = serde_json::from_str(line)?;
    if request.protocol != STRICT_PROTOCOL_VERSION {
        bail!("unsupported Broker protocol");
    }
    validate_request_id(&request.request_id)?;
    validate_sha256(&request.session_capability, "Broker session capability")?;
    match &request.command {
        BrokerCommand::PreparePolicy { policy } => policy.validate()?,
        BrokerCommand::CommitPolicy {
            revision,
            policy_digest,
        } => {
            if *revision == 0 {
                bail!("strict policy revision must be positive");
            }
            validate_sha256(policy_digest, "strict policy digest")?;
        }
        BrokerCommand::ForceBlocking { revision } | BrokerCommand::DisablePolicy { revision } => {
            if *revision == 0 {
                bail!("strict policy revision must be positive");
            }
        }
        BrokerCommand::Status {} | BrokerCommand::Diagnostics {} => {}
    }
    Ok(request)
}

pub fn parse_broker_response(frame: &[u8]) -> Result<BrokerResponse> {
    if frame.is_empty() || frame.len() > MAX_BROKER_FRAME_BYTES {
        bail!("Broker response frame size is invalid");
    }
    let response: BrokerResponse = serde_json::from_slice(frame)?;
    response.validate()?;
    Ok(response)
}

fn validate_request_id(value: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        bail!("Broker request ID is invalid");
    }
    Ok(())
}

fn validate_broker_pipe_name(value: &str) -> Result<()> {
    let Some(suffix) = value.strip_prefix(BROKER_PIPE_NAME_PREFIX) else {
        bail!("Broker activation pipe name has an invalid namespace");
    };
    if suffix.is_empty()
        || value.len() > 240
        || !suffix
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        bail!("Broker activation pipe name is invalid");
    }
    Ok(())
}

fn validate_broker_proof(proof: &BrokerProof) -> Result<()> {
    validate_sha256(&proof.policy_digest, "Broker proof policy digest")?;
    if proof.revision == 0 {
        if proof.policy_digest != "0".repeat(64)
            || proof.filter_generation != 0
            || !proof.capabilities.is_empty()
            || proof.guard_filters_installed
            || proof.recovery_marker_present
            || proof.core_healthy
            || proof.relay_healthy
            || proof.dns_healthy
        {
            bail!("disabled Broker proof contains active strict state");
        }
        return Ok(());
    }
    if !proof.recovery_marker_present {
        bail!("active Broker proof is missing its recovery marker");
    }
    if proof.guard_filters_installed && proof.filter_generation == 0 {
        bail!("active Broker guard proof is missing its filter generation");
    }
    if (proof
        .capabilities
        .contains(&StrictCapability::PersistentFailClosed)
        || proof
            .capabilities
            .contains(&StrictCapability::RecoveryVerified))
        && !proof.guard_filters_installed
    {
        bail!("Broker fail-closed capability has no installed guard proof");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(character: char) -> String {
        std::iter::repeat_n(character, 64).collect()
    }

    fn identity(id: &str, path: &str, app_character: char) -> StrictIdentity {
        StrictIdentity {
            identity_id: id.to_owned(),
            canonical_path: path.to_owned(),
            wfp_app_id_sha256: hex(app_character),
            publisher_certificate_sha256: hex('f'),
            verified_children: Vec::new(),
        }
    }

    #[test]
    fn canonical_digest_is_independent_of_entry_and_child_order() {
        let mut first = identity(
            "10000000-0000-4000-8000-000000000001",
            r"C:\Apps\Alpha\alpha.exe",
            'a',
        );
        first.verified_children = vec![
            StrictChildIdentity {
                canonical_path: r"C:\Apps\Alpha\z.exe".into(),
                wfp_app_id_sha256: hex('b'),
                publisher_certificate_sha256: hex('f'),
            },
            StrictChildIdentity {
                canonical_path: r"C:\Apps\Alpha\a.exe".into(),
                wfp_app_id_sha256: hex('c'),
                publisher_certificate_sha256: hex('f'),
            },
        ];
        let second = identity(
            "20000000-0000-4000-8000-000000000002",
            r"C:\Apps\Beta\beta.exe",
            'd',
        );
        let left = StrictPolicyBundle::new(
            7,
            vec![
                StrictPolicyEntry::proxy(first.clone(), "GLOBAL".into()),
                StrictPolicyEntry::block(second.clone()),
            ],
        )
        .unwrap();
        first.verified_children.reverse();
        let right = StrictPolicyBundle::new(
            7,
            vec![
                StrictPolicyEntry::block(second),
                StrictPolicyEntry::proxy(first, "GLOBAL".into()),
            ],
        )
        .unwrap();

        assert_eq!(
            left.canonical_digest().unwrap(),
            right.canonical_digest().unwrap()
        );
        assert_eq!(
            left.canonical_bytes().unwrap(),
            right.canonical_bytes().unwrap()
        );
    }

    #[test]
    fn identities_are_bounded_canonical_and_unambiguous() {
        let relative = identity(
            "10000000-0000-4000-8000-000000000001",
            r"Apps\alpha.exe",
            'a',
        );
        assert!(StrictPolicyBundle::new(1, vec![StrictPolicyEntry::block(relative)]).is_err());

        let duplicate = identity(
            "10000000-0000-4000-8000-000000000001",
            r"C:\Apps\Alpha\alpha.exe",
            'a',
        );
        assert!(StrictPolicyBundle::new(
            1,
            vec![
                StrictPolicyEntry::block(duplicate.clone()),
                StrictPolicyEntry::block(duplicate),
            ],
        )
        .is_err());

        let mut too_many_children = identity(
            "10000000-0000-4000-8000-000000000001",
            r"C:\Apps\Alpha\alpha.exe",
            'a',
        );
        too_many_children.verified_children = (0..33)
            .map(|index| StrictChildIdentity {
                canonical_path: format!(r"C:\Apps\Alpha\child-{index}.exe"),
                wfp_app_id_sha256: format!("{index:064x}"),
                publisher_certificate_sha256: hex('f'),
            })
            .collect();
        assert!(
            StrictPolicyBundle::new(1, vec![StrictPolicyEntry::block(too_many_children)]).is_err()
        );
    }

    #[test]
    fn broker_frames_require_protocol_capability_and_bounded_payloads() {
        let request = format!(
            r#"{{"protocol":1,"requestId":"request-1","sessionCapability":"{}","command":{{"type":"status"}}}}"#,
            hex('1')
        );
        assert!(parse_broker_request(&request).is_ok());
        assert!(
            parse_broker_request(&request.replace("\"protocol\":1", "\"protocol\":2")).is_err()
        );
        assert!(parse_broker_request(&request.replace(&hex('1'), "short")).is_err());
        assert!(parse_broker_request(&request.replace(
            r#""command":{"type":"status"}"#,
            r#""command":{"type":"status","revision":1}"#,
        ))
        .is_err());
        assert!(parse_broker_request(&"x".repeat(MAX_BROKER_FRAME_BYTES + 1)).is_err());
    }

    #[test]
    fn broker_responses_are_correlated_bounded_and_fail_closed() {
        let proof = BrokerProof {
            revision: 7,
            policy_digest: hex('a'),
            filter_generation: 9,
            capabilities: StrictCapability::required_for_block_only(),
            guard_filters_installed: true,
            recovery_marker_present: true,
            core_healthy: false,
            relay_healthy: false,
            dns_healthy: false,
        };
        let response = BrokerResponse::status("request-1", proof.clone()).unwrap();
        let encoded = response.to_bytes().unwrap();
        assert_eq!(parse_broker_response(&encoded).unwrap(), response);
        assert!(parse_broker_response(
            &String::from_utf8(encoded)
                .unwrap()
                .replace(r#""proof":{"#, r#""extra":true,"proof":{"#)
                .into_bytes(),
        )
        .is_err());

        let mut inconsistent = proof;
        inconsistent.guard_filters_installed = false;
        assert!(BrokerResponse::status("request-2", inconsistent).is_err());
        assert!(BrokerResponse::error("request-3", BrokerErrorCode::Unauthorized).is_ok());
        assert!(parse_broker_response(&vec![b'x'; MAX_BROKER_FRAME_BYTES + 1]).is_err());
    }

    #[test]
    fn activation_frames_are_closed_bounded_and_pipe_scoped() {
        let request = format!(
            r#"{{"protocol":1,"requestId":"activate-1","sessionCapability":"{}"}}"#,
            hex('1')
        );
        assert!(parse_broker_activation_request(request.as_bytes()).is_ok());
        assert!(
            parse_broker_activation_request(request.replace(&hex('1'), &hex('0')).as_bytes())
                .is_err()
        );
        let unknown = format!(
            r#"{{"protocol":1,"requestId":"activate-1","sessionCapability":"{}","ownerSid":"S-1-5-18"}}"#,
            hex('1')
        );
        assert!(parse_broker_activation_request(unknown.as_bytes()).is_err());
        assert!(parse_broker_activation_request(&vec![
            b'x';
            MAX_BROKER_ACTIVATION_FRAME_BYTES + 1
        ])
        .is_err());

        let response = BrokerActivationResponse::activated(
            "activate-1",
            r"\\.\pipe\FlClashX.StrictBroker.1234.a1b2c3",
        )
        .unwrap();
        assert_eq!(
            parse_broker_activation_response(&response.to_bytes().unwrap()).unwrap(),
            response
        );
        assert!(BrokerActivationResponse::activated("activate-1", r"\\.\pipe\arbitrary").is_err());
        assert!(BrokerActivationResponse::error(
            "activate-1",
            BrokerActivationErrorCode::Unauthorized
        )
        .is_ok());
    }

    #[test]
    fn proxy_and_block_targets_cannot_be_confused() {
        let app = identity(
            "10000000-0000-4000-8000-000000000001",
            r"C:\Apps\Alpha\alpha.exe",
            'a',
        );
        assert!(StrictPolicyEntry::try_new(app.clone(), StrictAction::Proxy, None).is_err());
        assert!(StrictPolicyEntry::try_new(
            app.clone(),
            StrictAction::Block,
            Some("GLOBAL".into())
        )
        .is_err());
        assert!(StrictPolicyEntry::proxy(app, "GLOBAL".into())
            .validate()
            .is_ok());
    }
}
