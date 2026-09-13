use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_AUTH_LINE_BYTES: usize = 4096;
pub const MAX_MESSAGE_LINE_BYTES: usize = 1024 * 1024;

/// Strict-capture status is a data contract only. Platform capture backends
/// must publish `armed` before selected flows are allowed to leave the host;
/// the Agent itself does not pretend to implement WFP or Network Extension.
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum StrictPolicyState {
    Disabled,
    Preparing,
    Armed,
    Degraded,
    Blocking,
    Recovering,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum StrictPolicyFailureReason {
    CaptureUnavailable,
    ProxyRouteUnavailable,
    IdentityUnavailable,
    CoreUnavailable,
    BrokerUnavailable,
    RecoveryExhausted,
    InvalidPolicy,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct StrictPolicyStatus {
    pub state: StrictPolicyState,
    pub generation: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failure_reason: Option<StrictPolicyFailureReason>,
}

impl StrictPolicyStatus {
    pub const fn disabled() -> Self {
        Self {
            state: StrictPolicyState::Disabled,
            generation: 0,
            failure_reason: None,
        }
    }

    pub fn fail_closed(&self) -> bool {
        self.state != StrictPolicyState::Armed
    }
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
pub struct AuthRequest {
    pub token: String,
    pub protocol: u32,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentCommand {
    RestartCore,
    StopCore,
    ShutdownAgent,
    Status,
    ApplyStrictBlock,
    ClearStrictBlock,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
pub struct ControlRequest {
    pub id: String,
    pub command: AgentCommand,
    pub path: Option<String>,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct AgentEnvelope<T> {
    #[serde(rename = "_agent")]
    pub agent: T,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ReadyResponse {
    pub protocol: u32,
    pub core_state: String,
    pub generation: u64,
}

pub fn authenticate(_line: &str, _expected_token: &str) -> bool {
    if _line.len() > MAX_AUTH_LINE_BYTES {
        return false;
    }
    let Ok(request) = serde_json::from_str::<AuthRequest>(_line) else {
        return false;
    };
    request.protocol == PROTOCOL_VERSION && constant_time_eq(&request.token, _expected_token)
}

pub fn parse_control(_line: &str) -> Option<ControlRequest> {
    if _line.len() > MAX_MESSAGE_LINE_BYTES {
        return None;
    }
    #[derive(Deserialize)]
    struct Envelope {
        #[serde(rename = "_agent")]
        agent: ControlRequest,
    }
    serde_json::from_str::<Envelope>(_line)
        .ok()
        .map(|value| value.agent)
}

pub(crate) fn constant_time_eq(left: &str, right: &str) -> bool {
    let left = left.as_bytes();
    let right = right.as_bytes();
    let mut difference = left.len() ^ right.len();
    let max_len = left.len().max(right.len());
    for index in 0..max_len {
        let left_byte = left.get(index).copied().unwrap_or_default();
        let right_byte = right.get(index).copied().unwrap_or_default();
        difference |= usize::from(left_byte ^ right_byte);
    }
    difference == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authentication_requires_exact_token_and_protocol() {
        let expected = "0123456789abcdef";
        assert!(authenticate(
            r#"{"token":"0123456789abcdef","protocol":1}"#,
            expected
        ));
        assert!(!authenticate(
            r#"{"token":"0123456789abcdee","protocol":1}"#,
            expected
        ));
        assert!(!authenticate(
            r#"{"token":"0123456789abcdef","protocol":2}"#,
            expected
        ));
        assert!(!authenticate("not-json", expected));
    }

    #[test]
    fn only_namespaced_agent_controls_are_intercepted() {
        let control = parse_control(r#"{"_agent":{"id":"request-1","command":"restartCore"}}"#)
            .expect("agent control");
        assert_eq!(control.id, "request-1");
        assert_eq!(control.command, AgentCommand::RestartCore);
        assert_eq!(control.path, None);
        assert!(parse_control(r#"{"id":"core-1","method":"updateConfig","data":"{}"}"#).is_none());
    }

    #[test]
    fn strict_control_carries_only_the_explicit_target_path() {
        let control = parse_control(
            r#"{"_agent":{"id":"request-2","command":"applyStrictBlock","path":"C:\\Apps\\edge.exe"}}"#,
        )
        .expect("strict control");
        assert_eq!(control.command, AgentCommand::ApplyStrictBlock);
        assert_eq!(control.path.as_deref(), Some(r#"C:\Apps\edge.exe"#));
    }

    #[test]
    fn strict_status_is_fail_closed_until_armed() {
        let status = StrictPolicyStatus {
            state: StrictPolicyState::Blocking,
            generation: 7,
            failure_reason: Some(StrictPolicyFailureReason::BrokerUnavailable),
        };
        assert!(status.fail_closed());
        let encoded = serde_json::to_string(&status).expect("strict status JSON");
        assert!(encoded.contains("brokerUnavailable"));
        let armed: StrictPolicyStatus =
            serde_json::from_str(r#"{"state":"armed","generation":8}"#).expect("armed status");
        assert!(!armed.fail_closed());
    }
}
