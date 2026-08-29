use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_AUTH_LINE_BYTES: usize = 4096;
pub const MAX_MESSAGE_LINE_BYTES: usize = 1024 * 1024;

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
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
pub struct ControlRequest {
    pub id: String,
    pub command: AgentCommand,
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

pub fn is_reserved_core_action(action: &Value) -> bool {
    action.get("method").and_then(Value::as_str) == Some("configureStrictIngress")
        || action
            .get("id")
            .and_then(Value::as_str)
            .is_some_and(|id| id.starts_with("_agent-"))
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
        assert!(parse_control(r#"{"id":"core-1","method":"updateConfig","data":"{}"}"#).is_none());
    }

    #[test]
    fn ui_cannot_invoke_agent_owned_core_actions() {
        let reserved: Value = serde_json::from_str(
            r#"{"id":"attack","method":"configureStrictIngress","data":"{}"}"#,
        )
        .unwrap();
        let normal: Value =
            serde_json::from_str(r#"{"id":"normal","method":"setupConfig","data":"{}"}"#).unwrap();
        let reserved_id: Value = serde_json::from_str(
            r#"{"id":"_agent-internal-collision","method":"setupConfig","data":"{}"}"#,
        )
        .unwrap();
        assert!(is_reserved_core_action(&reserved));
        assert!(is_reserved_core_action(&reserved_id));
        assert!(!is_reserved_core_action(&normal));
        assert!(!is_reserved_core_action(&Value::Null));
    }
}
