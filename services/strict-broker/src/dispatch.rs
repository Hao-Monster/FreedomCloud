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
    /// The immutable prepared-policy identity is supplied so every forwarding
    /// resource can be bound to exactly the transaction being committed.
    fn measure(
        &mut self,
        revision: u64,
        policy_digest: &str,
        ingress: &StrictProxyIngressSet,
    ) -> Result<ForwardingHealth>;

    /// Checks only already-owned runtime state. It must not perform network I/O
    /// or allocate on the engine actor's periodic supervision path.
    fn verify_active(&mut self) -> Result<()> {
        Ok(())
    }

    /// Marks a pending teardown before an external gate/lease revocation can
    /// complete a queued receive with a cancellation status.
    fn prepare_deactivation(&mut self) -> Result<()> {
        Ok(())
    }

    /// Revokes forwarding admission before listener resources are released.
    /// Implementations must be bounded and idempotent.
    fn deactivate(&mut self) -> Result<()>;
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

    pub fn health_probe(&self) -> &H {
        &self.health_probe
    }

    pub fn health_probe_mut(&mut self) -> &mut H {
        &mut self.health_probe
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
                Ok(()) => match self
                    .health_probe
                    .measure(revision, &policy_digest, &ingress)
                {
                    Ok(health) => {
                        let commit = self.engine.commit(revision, &policy_digest, health);
                        let result = match commit {
                            Ok(status) => Ok(status),
                            Err(error) => {
                                fail_after_deactivation(error, self.health_probe.deactivate())
                            }
                        };
                        (result, BrokerErrorCode::Internal)
                    }
                    Err(_) => {
                        let result = fail_after_deactivation(
                            anyhow::anyhow!("strict forwarding health measurement failed"),
                            self.health_probe.deactivate(),
                        );
                        (result, BrokerErrorCode::BackendUnavailable)
                    }
                },
            },
            BrokerCommand::ForceBlocking { revision } => {
                let deactivate = self.health_probe.deactivate();
                let block = self.engine.force_blocking(revision);
                (
                    combine_deactivation_with_transition(deactivate, block),
                    BrokerErrorCode::Internal,
                )
            }
            BrokerCommand::DisablePolicy { revision } => {
                let deactivate = self.health_probe.deactivate();
                let disable = self.engine.disable(revision);
                (
                    combine_deactivation_with_transition(deactivate, disable),
                    BrokerErrorCode::Internal,
                )
            }
        };
        response_for_result(request_id, result, failure_code)
    }
}

fn fail_after_deactivation<T>(failure: anyhow::Error, deactivate: Result<()>) -> Result<T> {
    match deactivate {
        Ok(()) => Err(failure),
        Err(cleanup) => Err(anyhow::anyhow!(
            "strict forwarding transition failed: {failure:#}; deactivation failed: {cleanup:#}"
        )),
    }
}

fn combine_deactivation_with_transition<T>(
    deactivate: Result<()>,
    transition: Result<T>,
) -> Result<T> {
    match (deactivate, transition) {
        (Ok(()), Ok(value)) => Ok(value),
        (Ok(()), Err(transition)) => Err(transition),
        (Err(deactivate), Ok(_)) => Err(deactivate),
        (Err(deactivate), Err(transition)) => Err(anyhow::anyhow!(
            "strict forwarding deactivation failed: {deactivate:#}; state transition failed: {transition:#}"
        )),
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
