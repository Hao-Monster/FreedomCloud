use std::thread::{self, JoinHandle};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{BrokerActivationResponse, BrokerResponse};

use crate::{
    generate_windows_broker_session_pipe_name, AuthorizedBrokerRequest, BrokerAuthenticator,
    BrokerSessionResource, WindowsAgentProcessTrustLease, WindowsNamedPipeWorkerPool,
    WindowsPipeDeadlines, WindowsPipeServiceReport, WindowsPipeShutdown,
    WindowsVerifiedActivationRequest,
};

pub struct WindowsBrokerPipeSession {
    owner_sid: String,
    pipe_name: String,
    activation_request_id: String,
    agent: WindowsAgentProcessTrustLease,
    shutdown: WindowsPipeShutdown,
    worker: Option<JoinHandle<Result<WindowsPipeServiceReport>>>,
}

impl WindowsBrokerPipeSession {
    pub fn start<H>(
        activation: WindowsVerifiedActivationRequest,
        deadlines: WindowsPipeDeadlines,
        worker_count: usize,
        handler: H,
    ) -> Result<Self>
    where
        H: Fn(AuthorizedBrokerRequest) -> BrokerResponse + Send + Sync + 'static,
    {
        if !activation.agent.is_running()? {
            bail!("verified strict Agent exited before its Broker session started");
        }
        let authenticator = BrokerAuthenticator::from_hex(&activation.request.session_capability)?;
        let pipe_name = generate_windows_broker_session_pipe_name()?;
        let pool = WindowsNamedPipeWorkerPool::create(
            &pipe_name,
            &activation.client_sid,
            authenticator,
            deadlines,
            worker_count,
            handler,
        )?;
        let shutdown = WindowsPipeShutdown::new();
        let worker_shutdown = shutdown.clone();
        let worker = thread::Builder::new()
            .name("flclash-strict-session".into())
            .spawn(move || pool.run(worker_shutdown))
            .context("start strict Broker Agent session")?;
        Ok(Self {
            owner_sid: activation.client_sid,
            pipe_name,
            activation_request_id: activation.request.request_id,
            agent: activation.agent,
            shutdown,
            worker: Some(worker),
        })
    }

    pub fn owner_sid(&self) -> &str {
        &self.owner_sid
    }

    pub fn pipe_name(&self) -> &str {
        &self.pipe_name
    }

    pub fn activation_response(&self) -> Result<BrokerActivationResponse> {
        BrokerActivationResponse::activated(&self.activation_request_id, &self.pipe_name)
    }

    pub fn shutdown_with_report(&mut self) -> Result<Option<WindowsPipeServiceReport>> {
        self.shutdown.request();
        let Some(worker) = self.worker.take() else {
            return Ok(None);
        };
        let report = worker
            .join()
            .map_err(|_| anyhow::anyhow!("strict Broker Agent session panicked"))??;
        Ok(Some(report))
    }
}

impl BrokerSessionResource for WindowsBrokerPipeSession {
    fn is_alive(&self) -> Result<bool> {
        Ok(self.agent.is_running()?
            && self
                .worker
                .as_ref()
                .is_some_and(|worker| !worker.is_finished()))
    }

    fn shutdown(&mut self) -> Result<()> {
        self.shutdown_with_report().map(|_| ())
    }
}

impl Drop for WindowsBrokerPipeSession {
    fn drop(&mut self) {
        let _ = self.shutdown_with_report();
    }
}
