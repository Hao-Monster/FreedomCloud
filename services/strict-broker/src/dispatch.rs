use anyhow::Result;
use flclash_strict_contract::{
    BrokerCommand, BrokerErrorCode, BrokerResponse, BrokerResponseBody, StrictProxyIngressSet,
};

use crate::{
    AuthorizedBrokerRequest, BrokerEngine, BrokerStatus, FilterBackend, ForwardingHealth,
    IdentityVerifier, RecoveryStore,
};

pub trait ForwardingHealthProbe {
    /// Health is measured by the privileged Broker; Agent-supplied booleans are never trusted.
    fn measure(&mut self, ingress: &StrictProxyIngressSet) -> Result<ForwardingHealth>;
}

pub struct BrokerDispatcher<B, S, V: IdentityVerifier, H> {
    engine: BrokerEngine<B, S, V>,
    health_probe: H,
}

impl<B, S, V, H> BrokerDispatcher<B, S, V, H>
where
    B: FilterBackend,
    S: RecoveryStore,
    V: IdentityVerifier,
    H: ForwardingHealthProbe,
{
    pub fn new(engine: BrokerEngine<B, S, V>, health_probe: H) -> Self {
        Self {
            engine,
            health_probe,
        }
    }

    pub fn engine(&self) -> &BrokerEngine<B, S, V> {
        &self.engine
    }

    pub fn engine_mut(&mut self) -> &mut BrokerEngine<B, S, V> {
        &mut self.engine
    }

    pub fn dispatch(&mut self, authorized: AuthorizedBrokerRequest) -> BrokerResponse {
        let request = authorized.into_request();
        let request_id = request.request_id;
        let (result, failure_code) = match request.command {
            BrokerCommand::Status {} | BrokerCommand::Diagnostics {} => {
                (self.engine.status(), BrokerErrorCode::BackendUnavailable)
            }
            BrokerCommand::PreparePolicy { policy } => {
                (self.engine.prepare(policy), BrokerErrorCode::Internal)
            }
            BrokerCommand::CommitPolicy {
                revision,
                policy_digest,
                ingress,
            } => match self
                .engine
                .validate_forwarding_ingress(revision, &policy_digest, &ingress)
            {
                Err(error) => (Err(error), BrokerErrorCode::InvalidRequest),
                Ok(()) => match self.health_probe.measure(&ingress) {
                    Ok(health) => (
                        self.engine.commit(revision, &policy_digest, health),
                        BrokerErrorCode::Internal,
                    ),
                    Err(_) => (
                        Err(anyhow::anyhow!(
                            "strict forwarding health measurement failed"
                        )),
                        BrokerErrorCode::BackendUnavailable,
                    ),
                },
            },
            BrokerCommand::ForceBlocking { revision } => (
                self.engine.force_blocking(revision),
                BrokerErrorCode::Internal,
            ),
            BrokerCommand::DisablePolicy { revision } => {
                (self.engine.disable(revision), BrokerErrorCode::Internal)
            }
        };
        response_for_result(request_id, result, failure_code)
    }
}

fn response_for_result(
    request_id: String,
    result: Result<BrokerStatus>,
    failure_code: BrokerErrorCode,
) -> BrokerResponse {
    let response = match result {
        Ok(status) => BrokerResponse::status(&request_id, status.proof),
        Err(_) => BrokerResponse::error(&request_id, failure_code),
    };
    response.unwrap_or(BrokerResponse {
        protocol: flclash_strict_contract::STRICT_PROTOCOL_VERSION,
        request_id,
        body: BrokerResponseBody::Error {
            code: BrokerErrorCode::Internal,
        },
    })
}
