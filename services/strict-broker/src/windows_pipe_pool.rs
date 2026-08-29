use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{BrokerErrorCode, BrokerResponse};

use crate::windows_pipe::{is_connect_deadline, WindowsNamedPipeInstance};
use crate::{AuthorizedBrokerRequest, BrokerAuthenticator, WindowsPipeDeadlines};

const MAX_PIPE_WORKERS: usize = 64;
const MAX_IDLE_CONNECT_POLL: Duration = Duration::from_secs(1);
const DEFAULT_HANDLER_DEADLINE: Duration = Duration::from_secs(30);
const HANDLER_WAIT_SLICE: Duration = Duration::from_millis(50);

#[derive(Clone, Default)]
pub struct WindowsPipeShutdown {
    requested: Arc<AtomicBool>,
}

impl WindowsPipeShutdown {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn request(&self) {
        self.requested.store(true, Ordering::Release);
    }

    pub fn is_requested(&self) -> bool {
        self.requested.load(Ordering::Acquire)
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct WindowsPipeServiceReport {
    pub worker_count: usize,
    pub accepted_requests: u64,
    pub completed_requests: u64,
    pub rejected_requests: u64,
    pub io_failures: u64,
    pub handler_timeouts: u64,
    pub handler_panics: u64,
}

#[derive(Default)]
struct ServiceCounters {
    accepted_requests: AtomicU64,
    completed_requests: AtomicU64,
    rejected_requests: AtomicU64,
    io_failures: AtomicU64,
    handler_timeouts: AtomicU64,
    handler_panics: AtomicU64,
}

impl ServiceCounters {
    fn report(&self, worker_count: usize) -> WindowsPipeServiceReport {
        WindowsPipeServiceReport {
            worker_count,
            accepted_requests: self.accepted_requests.load(Ordering::Relaxed),
            completed_requests: self.completed_requests.load(Ordering::Relaxed),
            rejected_requests: self.rejected_requests.load(Ordering::Relaxed),
            io_failures: self.io_failures.load(Ordering::Relaxed),
            handler_timeouts: self.handler_timeouts.load(Ordering::Relaxed),
            handler_panics: self.handler_panics.load(Ordering::Relaxed),
        }
    }
}

pub struct WindowsNamedPipeWorkerPool<H> {
    instances: Vec<WindowsNamedPipeInstance>,
    authenticator: Arc<BrokerAuthenticator>,
    handler: Arc<H>,
    handler_deadline: Duration,
}

impl<H> WindowsNamedPipeWorkerPool<H>
where
    H: Fn(AuthorizedBrokerRequest) -> BrokerResponse + Send + Sync + 'static,
{
    pub fn create(
        pipe_name: &str,
        owner_sid: &str,
        authenticator: BrokerAuthenticator,
        deadlines: WindowsPipeDeadlines,
        worker_count: usize,
        handler: H,
    ) -> Result<Self> {
        Self::create_with_handler_deadline(
            pipe_name,
            owner_sid,
            authenticator,
            deadlines,
            worker_count,
            DEFAULT_HANDLER_DEADLINE,
            handler,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn create_with_handler_deadline(
        pipe_name: &str,
        owner_sid: &str,
        authenticator: BrokerAuthenticator,
        deadlines: WindowsPipeDeadlines,
        worker_count: usize,
        handler_deadline: Duration,
        handler: H,
    ) -> Result<Self> {
        if worker_count == 0 || worker_count > MAX_PIPE_WORKERS {
            bail!("strict Broker pipe worker count is invalid");
        }
        if deadlines.connect_timeout() > MAX_IDLE_CONNECT_POLL {
            bail!("strict Broker worker connect deadline exceeds the shutdown bound");
        }
        if handler_deadline.is_zero() || handler_deadline > Duration::from_secs(300) {
            bail!("strict Broker handler deadline is invalid");
        }

        let mut instances = Vec::with_capacity(worker_count);
        for index in 0..worker_count {
            instances.push(WindowsNamedPipeInstance::create_pool_instance(
                pipe_name,
                owner_sid,
                deadlines,
                index == 0,
                worker_count as u32,
            )?);
        }
        Ok(Self {
            instances,
            authenticator: Arc::new(authenticator),
            handler: Arc::new(handler),
            handler_deadline,
        })
    }

    pub fn run(self, shutdown: WindowsPipeShutdown) -> Result<WindowsPipeServiceReport> {
        let worker_count = self.instances.len();
        let counters = Arc::new(ServiceCounters::default());
        let mut workers = Vec::with_capacity(worker_count);
        for (index, instance) in self.instances.into_iter().enumerate() {
            let result = thread::Builder::new()
                .name(format!("flclash-strict-pipe-{index}"))
                .spawn({
                    let authenticator = Arc::clone(&self.authenticator);
                    let handler = Arc::clone(&self.handler);
                    let counters = Arc::clone(&counters);
                    let shutdown = shutdown.clone();
                    move || {
                        run_pipe_worker(
                            instance,
                            authenticator,
                            handler,
                            self.handler_deadline,
                            shutdown,
                            counters,
                        )
                    }
                });
            match result {
                Ok(worker) => workers.push(worker),
                Err(error) => {
                    shutdown.request();
                    join_workers(workers)?;
                    return Err(error).context("start strict Broker pipe worker");
                }
            }
        }
        join_workers(workers)?;
        Ok(counters.report(worker_count))
    }
}

fn run_pipe_worker<H>(
    instance: WindowsNamedPipeInstance,
    authenticator: Arc<BrokerAuthenticator>,
    handler: Arc<H>,
    handler_deadline: Duration,
    shutdown: WindowsPipeShutdown,
    counters: Arc<ServiceCounters>,
) where
    H: Fn(AuthorizedBrokerRequest) -> BrokerResponse + Send + Sync + 'static,
{
    let (job_sender, job_receiver) = mpsc::sync_channel(1);
    let handler_counters = Arc::clone(&counters);
    let executor = thread::Builder::new()
        .name("flclash-strict-dispatch".into())
        .spawn(move || run_handler_executor(job_receiver, handler, handler_counters));
    let Ok(executor) = executor else {
        counters.io_failures.fetch_add(1, Ordering::Relaxed);
        shutdown.request();
        return;
    };
    let mut executor = Some(executor);

    while !shutdown.is_requested() {
        let authenticated = instance.connect_and_authenticate(&authenticator);
        let request = match authenticated {
            Ok(request) => request,
            Err(error) => {
                if !is_connect_deadline(&error) {
                    counters.rejected_requests.fetch_add(1, Ordering::Relaxed);
                }
                instance.disconnect_for_reuse();
                continue;
            }
        };
        counters.accepted_requests.fetch_add(1, Ordering::Relaxed);
        let request_id = request.authorized.request().request_id.clone();
        let (response_sender, response_receiver) = mpsc::sync_channel(1);
        if job_sender
            .send(HandlerJob::Dispatch(request.authorized, response_sender))
            .is_err()
        {
            counters.handler_panics.fetch_add(1, Ordering::Relaxed);
            shutdown.request();
            write_stable_error(&instance, &request_id, &counters);
            instance.disconnect_for_reuse();
            break;
        }

        match wait_for_handler(&response_receiver, handler_deadline, &shutdown, &counters) {
            HandlerWait::Response(response) => {
                if instance.write_response(&response).is_ok() {
                    counters.completed_requests.fetch_add(1, Ordering::Relaxed);
                } else {
                    counters.io_failures.fetch_add(1, Ordering::Relaxed);
                }
            }
            HandlerWait::TimedOut => {
                shutdown.request();
                write_stable_error(&instance, &request_id, &counters);
                instance.disconnect_for_reuse();
                executor.take();
                break;
            }
            HandlerWait::ShuttingDown => {
                instance.disconnect_for_reuse();
                executor.take();
                break;
            }
            HandlerWait::ExecutorStopped => {
                shutdown.request();
                write_stable_error(&instance, &request_id, &counters);
                instance.disconnect_for_reuse();
                break;
            }
        }
        instance.disconnect_for_reuse();
    }

    if let Some(executor) = executor {
        let _ = job_sender.send(HandlerJob::Shutdown);
        let _ = executor.join();
    }
}

enum HandlerJob {
    Dispatch(AuthorizedBrokerRequest, SyncSender<BrokerResponse>),
    Shutdown,
}

fn run_handler_executor<H>(
    receiver: Receiver<HandlerJob>,
    handler: Arc<H>,
    counters: Arc<ServiceCounters>,
) where
    H: Fn(AuthorizedBrokerRequest) -> BrokerResponse + Send + Sync + 'static,
{
    while let Ok(job) = receiver.recv() {
        match job {
            HandlerJob::Dispatch(request, response_sender) => {
                let response = catch_unwind(AssertUnwindSafe(|| handler(request)));
                match response {
                    Ok(response) => {
                        let _ = response_sender.send(response);
                    }
                    Err(_) => {
                        counters.handler_panics.fetch_add(1, Ordering::Relaxed);
                    }
                }
            }
            HandlerJob::Shutdown => break,
        }
    }
}

enum HandlerWait {
    Response(BrokerResponse),
    TimedOut,
    ShuttingDown,
    ExecutorStopped,
}

fn wait_for_handler(
    receiver: &Receiver<BrokerResponse>,
    timeout: Duration,
    shutdown: &WindowsPipeShutdown,
    counters: &ServiceCounters,
) -> HandlerWait {
    let deadline = Instant::now() + timeout;
    loop {
        if shutdown.is_requested() {
            return HandlerWait::ShuttingDown;
        }
        let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
            counters.handler_timeouts.fetch_add(1, Ordering::Relaxed);
            return HandlerWait::TimedOut;
        };
        match receiver.recv_timeout(remaining.min(HANDLER_WAIT_SLICE)) {
            Ok(response) => return HandlerWait::Response(response),
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => return HandlerWait::ExecutorStopped,
        }
    }
}

fn write_stable_error(
    instance: &WindowsNamedPipeInstance,
    request_id: &str,
    counters: &ServiceCounters,
) {
    let response = BrokerResponse::error(request_id, BrokerErrorCode::BackendUnavailable);
    match response.and_then(|response| instance.write_response(&response)) {
        Ok(()) => {
            counters.completed_requests.fetch_add(1, Ordering::Relaxed);
        }
        Err(_) => {
            counters.io_failures.fetch_add(1, Ordering::Relaxed);
        }
    }
}

fn join_workers(workers: Vec<JoinHandle<()>>) -> Result<()> {
    for worker in workers {
        if worker.join().is_err() {
            bail!("strict Broker pipe worker panicked");
        }
    }
    Ok(())
}
