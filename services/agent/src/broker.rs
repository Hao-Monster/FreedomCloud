use anyhow::{bail, Context, Result};
use flclash_strict_broker::{
    exchange_windows_activation_for_agent, exchange_windows_pipe_for_agent, WindowsPipeDeadlines,
};
use flclash_strict_contract::{
    parse_broker_activation_request, parse_broker_request, BrokerActivationRequest,
    BrokerActivationResponseBody, BrokerCommand, BrokerProof, BrokerRequest, BrokerResponseBody,
    STRICT_PROTOCOL_VERSION, WINDOWS_STRICT_BROKER_ACTIVATION_PIPE_NAME,
};

use crate::endpoint::random_token;

const ACTIVATION_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(3);

pub struct WindowsStrictBrokerSession {
    pipe_name: String,
    session_capability: String,
    request_prefix: String,
    next_request: u64,
}

impl WindowsStrictBrokerSession {
    pub fn activate() -> Result<Self> {
        let session_capability = random_token();
        let request_prefix = random_token()[..16].to_owned();
        let request_id = format!("activate-{request_prefix}");
        let request = BrokerActivationRequest {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: request_id.clone(),
            session_capability: session_capability.clone(),
        };
        let frame = serde_json::to_vec(&request).context("encode strict Broker activation")?;
        parse_broker_activation_request(&frame)
            .context("validate strict Broker activation request")?;
        let deadlines =
            WindowsPipeDeadlines::new(ACTIVATION_TIMEOUT, ACTIVATION_TIMEOUT, ACTIVATION_TIMEOUT)?;
        let response = exchange_windows_activation_for_agent(
            WINDOWS_STRICT_BROKER_ACTIVATION_PIPE_NAME,
            &frame,
            deadlines,
        )?;
        if response.request_id != request_id {
            bail!("strict Broker activation correlation failed");
        }
        let pipe_name = match response.body {
            BrokerActivationResponseBody::Activated { pipe_name } => pipe_name,
            BrokerActivationResponseBody::Error { code } => {
                bail!("strict Broker activation failed with code {code:?}")
            }
        };
        Ok(Self {
            pipe_name,
            session_capability,
            request_prefix,
            next_request: 1,
        })
    }

    pub fn request(&mut self, command: BrokerCommand) -> Result<BrokerProof> {
        let request_id = self.next_request_id()?;
        let frame = build_request_frame(&request_id, &self.session_capability, command)?;
        let response = exchange_windows_pipe_for_agent(&self.pipe_name, &frame)?;
        if response.request_id != request_id {
            bail!("strict Broker response correlation failed");
        }
        match response.body {
            BrokerResponseBody::Status { proof } => Ok(proof),
            BrokerResponseBody::Error { code } => {
                return Err(BrokerDiagnostic(code).into());
            }
        }
    }

    fn next_request_id(&mut self) -> Result<String> {
        let sequence = self.next_request;
        self.next_request = self
            .next_request
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("strict Broker request sequence overflow"))?;
        Ok(format!("agent-{}-{sequence}", self.request_prefix))
    }
}

fn build_request_frame(
    request_id: &str,
    session_capability: &str,
    command: BrokerCommand,
) -> Result<Vec<u8>> {
    let request = BrokerRequest {
        protocol: STRICT_PROTOCOL_VERSION,
        request_id: request_id.to_owned(),
        session_capability: session_capability.to_owned(),
        command,
    };
    let frame = serde_json::to_vec(&request).context("encode strict Broker request")?;
    let line = std::str::from_utf8(&frame).expect("JSON Broker request is UTF-8");
    parse_broker_request(line).context("validate strict Broker request")?;
    Ok(frame)
}

#[cfg(test)]
mod tests {
    use flclash_strict_contract::BrokerCommand;

    use super::*;

    #[test]
    fn broker_frames_bind_a_command_to_the_private_session_capability() {
        let capability = "a".repeat(64);
        let frame = build_request_frame(
            "agent-test-1",
            &capability,
            BrokerCommand::ForceBlocking { revision: 7 },
        )
        .unwrap();
        let request = parse_broker_request(std::str::from_utf8(&frame).unwrap()).unwrap();

        assert_eq!(request.request_id, "agent-test-1");
        assert_eq!(request.session_capability, capability);
        assert!(matches!(
            request.command,
            BrokerCommand::ForceBlocking { revision: 7 }
        ));
    }

    #[test]
    fn invalid_capability_never_reaches_the_pipe_exchange() {
        assert!(build_request_frame("agent-test-2", "short", BrokerCommand::Status {},).is_err());
    }
}

#[derive(Debug)]
pub(crate) struct BrokerDiagnostic(pub flclash_strict_contract::BrokerErrorCode);
impl std::fmt::Display for BrokerDiagnostic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        use flclash_strict_contract::BrokerErrorCode;
        f.write_str(match self.0 {
            BrokerErrorCode::ForwardingDnsMapping => "严格代理 DNS 探测失败：Core 未返回可还原域名映射，请检查 DNS/Fake-IP 或 redir-host 配置。",
            BrokerErrorCode::ForwardingDnsRestoration => "严格代理 DNS 验证失败：Core 未观察到连接域名恢复，应用继续保持阻断。",
            BrokerErrorCode::ForwardingCanary => "严格代理链路探测失败：IPv4/IPv6 TCP、DNS 或 QUIC 未通过真实 WFP 转发，请检查目标策略和端点可达性。",
            BrokerErrorCode::ForwardingTimeout => "严格代理链路探测超过时间预算，应用继续保持阻断，请检查目标策略数量及网络连通性。",
            _ => "严格代理后端不可用，请检查 Broker、驱动及签名状态。",
        })
    }
}
impl std::error::Error for BrokerDiagnostic {}
impl BrokerDiagnostic {
    pub(crate) fn failure_reason(&self) -> crate::protocol::StrictPolicyFailureReason {
        use flclash_strict_contract::BrokerErrorCode;
        use crate::protocol::StrictPolicyFailureReason as Reason;
        match self.0 {
            BrokerErrorCode::ForwardingDnsMapping => Reason::ForwardingDnsMapping,
            BrokerErrorCode::ForwardingDnsRestoration => Reason::ForwardingDnsRestoration,
            BrokerErrorCode::ForwardingCanary => Reason::ForwardingCanary,
            BrokerErrorCode::ForwardingTimeout => Reason::ForwardingTimeout,
            _ => Reason::BrokerUnavailable,
        }
    }
}
