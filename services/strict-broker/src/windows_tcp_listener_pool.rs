use std::io;
use std::net::{
    Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6, TcpListener, TcpStream,
};
use std::os::windows::io::AsRawSocket;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use windows_sys::Win32::Networking::WinSock::{
    WSAGetLastError, WSAPoll, POLLERR, POLLHUP, POLLIN, POLLNVAL, SOCKET_ERROR, WSAPOLLFD,
};

use crate::WindowsPipeShutdown;

const MAX_LISTENER_WORKERS: usize = 64;
const WORKER_QUEUE_CAPACITY: usize = 1;
const WORKER_STACK_BYTES: usize = 512 * 1024;
const SHUTDOWN_POLL_MILLIS: i32 = 100;
const WORKER_RECV_POLL: Duration = Duration::from_millis(100);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowsTcpListenerEndpoints {
    v4: SocketAddrV4,
    v6: SocketAddrV6,
}

impl WindowsTcpListenerEndpoints {
    pub fn v4(&self) -> SocketAddrV4 {
        self.v4
    }

    pub fn v6(&self) -> SocketAddrV6 {
        self.v6
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct WindowsTcpListenerReport {
    pub listener_count: usize,
    pub worker_count: usize,
    pub accepted_connections: u64,
    pub completed_connections: u64,
    pub rejected_connections: u64,
    pub handler_failures: u64,
    pub handler_panics: u64,
}

#[derive(Default)]
struct ListenerCounters {
    accepted_connections: AtomicU64,
    completed_connections: AtomicU64,
    rejected_connections: AtomicU64,
    handler_failures: AtomicU64,
    handler_panics: AtomicU64,
}

impl ListenerCounters {
    fn report(&self, listener_count: usize, worker_count: usize) -> WindowsTcpListenerReport {
        WindowsTcpListenerReport {
            listener_count,
            worker_count,
            accepted_connections: self.accepted_connections.load(Ordering::Relaxed),
            completed_connections: self.completed_connections.load(Ordering::Relaxed),
            rejected_connections: self.rejected_connections.load(Ordering::Relaxed),
            handler_failures: self.handler_failures.load(Ordering::Relaxed),
            handler_panics: self.handler_panics.load(Ordering::Relaxed),
        }
    }
}

pub struct WindowsTcpListenerPool<H> {
    listeners: [TcpListener; 2],
    endpoints: WindowsTcpListenerEndpoints,
    worker_count: usize,
    handler: Arc<H>,
}

pub struct WindowsTcpListenerBinding {
    listeners: [TcpListener; 2],
    endpoints: WindowsTcpListenerEndpoints,
}

impl WindowsTcpListenerBinding {
    pub fn bind() -> Result<Self> {
        let v4 = TcpListener::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
            .context("bind strict TCP IPv4 listener")?;
        let v6 = TcpListener::bind(SocketAddrV6::new(Ipv6Addr::LOCALHOST, 0, 0, 0))
            .context("bind strict TCP IPv6 listener")?;
        v4.set_nonblocking(true)
            .context("make strict TCP IPv4 listener nonblocking")?;
        v6.set_nonblocking(true)
            .context("make strict TCP IPv6 listener nonblocking")?;
        let v4_endpoint = match v4.local_addr()? {
            SocketAddr::V4(endpoint)
                if endpoint.ip() == &Ipv4Addr::LOCALHOST && endpoint.port() != 0 =>
            {
                endpoint
            }
            _ => bail!("strict TCP IPv4 listener bound an unsafe endpoint"),
        };
        let v6_endpoint = match v6.local_addr()? {
            SocketAddr::V6(endpoint)
                if endpoint.ip() == &Ipv6Addr::LOCALHOST && endpoint.port() != 0 =>
            {
                endpoint
            }
            _ => bail!("strict TCP IPv6 listener bound an unsafe endpoint"),
        };
        Ok(Self {
            listeners: [v4, v6],
            endpoints: WindowsTcpListenerEndpoints {
                v4: v4_endpoint,
                v6: v6_endpoint,
            },
        })
    }

    pub fn endpoints(&self) -> WindowsTcpListenerEndpoints {
        self.endpoints
    }

    /// Duplicates the bound socket handles so a supervisor can keep both
    /// endpoints alive until forwarding admission has been revoked, even if
    /// the accept loop exits unexpectedly.
    pub fn retention_handles(&self) -> Result<[TcpListener; 2]> {
        Ok([
            self.listeners[0]
                .try_clone()
                .context("retain strict TCP IPv4 listener endpoint")?,
            self.listeners[1]
                .try_clone()
                .context("retain strict TCP IPv6 listener endpoint")?,
        ])
    }

    pub fn into_pool<H>(self, worker_count: usize, handler: H) -> Result<WindowsTcpListenerPool<H>>
    where
        H: Fn(TcpStream, &WindowsPipeShutdown) -> Result<()> + Send + Sync + 'static,
    {
        if worker_count == 0 || worker_count > MAX_LISTENER_WORKERS {
            bail!("strict TCP listener worker count is invalid");
        }
        Ok(WindowsTcpListenerPool {
            listeners: self.listeners,
            endpoints: self.endpoints,
            worker_count,
            handler: Arc::new(handler),
        })
    }
}

impl<H> WindowsTcpListenerPool<H>
where
    H: Fn(TcpStream, &WindowsPipeShutdown) -> Result<()> + Send + Sync + 'static,
{
    pub fn bind(worker_count: usize, handler: H) -> Result<Self> {
        WindowsTcpListenerBinding::bind()?.into_pool(worker_count, handler)
    }

    pub fn endpoints(&self) -> WindowsTcpListenerEndpoints {
        self.endpoints
    }

    pub fn run(self, shutdown: WindowsPipeShutdown) -> Result<WindowsTcpListenerReport> {
        let counters = Arc::new(ListenerCounters::default());
        let mut senders = Vec::with_capacity(self.worker_count);
        let mut workers = Vec::with_capacity(self.worker_count);
        for index in 0..self.worker_count {
            let (sender, receiver) = mpsc::sync_channel(WORKER_QUEUE_CAPACITY);
            match spawn_worker(
                index,
                receiver,
                Arc::clone(&self.handler),
                shutdown.clone(),
                Arc::clone(&counters),
            ) {
                Ok(worker) => {
                    senders.push(sender);
                    workers.push(worker);
                }
                Err(error) => {
                    shutdown.request();
                    drop(senders);
                    let _ = join_workers(workers);
                    return Err(error);
                }
            }
        }

        let accept_result = run_accept_loop(&self.listeners, &senders, &shutdown, &counters);
        shutdown.request();
        drop(senders);
        let join_result = join_workers(workers);
        match (accept_result, join_result) {
            (Ok(()), Ok(())) => Ok(counters.report(self.listeners.len(), self.worker_count)),
            (Err(accept), Ok(())) => Err(accept),
            (Ok(()), Err(join)) => Err(join),
            (Err(accept), Err(join)) => {
                bail!("strict TCP listener failed: {accept:#}; worker shutdown failed: {join:#}")
            }
        }
    }
}

fn spawn_worker<H>(
    index: usize,
    receiver: Receiver<TcpStream>,
    handler: Arc<H>,
    shutdown: WindowsPipeShutdown,
    counters: Arc<ListenerCounters>,
) -> Result<JoinHandle<()>>
where
    H: Fn(TcpStream, &WindowsPipeShutdown) -> Result<()> + Send + Sync + 'static,
{
    thread::Builder::new()
        .name(format!("flclash-strict-tcp-{index}"))
        .stack_size(WORKER_STACK_BYTES)
        .spawn(move || run_worker(receiver, handler, shutdown, counters))
        .context("start strict TCP listener worker")
}

fn run_worker<H>(
    receiver: Receiver<TcpStream>,
    handler: Arc<H>,
    shutdown: WindowsPipeShutdown,
    counters: Arc<ListenerCounters>,
) where
    H: Fn(TcpStream, &WindowsPipeShutdown) -> Result<()> + Send + Sync + 'static,
{
    loop {
        if shutdown.is_requested() {
            break;
        }
        let stream = match receiver.recv_timeout(WORKER_RECV_POLL) {
            Ok(stream) => stream,
            Err(RecvTimeoutError::Timeout) => continue,
            Err(RecvTimeoutError::Disconnected) => break,
        };
        if shutdown.is_requested() {
            break;
        }
        match catch_unwind(AssertUnwindSafe(|| handler(stream, &shutdown))) {
            Ok(Ok(())) => increment(&counters.completed_connections),
            Ok(Err(_)) => increment(&counters.handler_failures),
            Err(_) => increment(&counters.handler_panics),
        }
    }
}

fn run_accept_loop(
    listeners: &[TcpListener; 2],
    senders: &[SyncSender<TcpStream>],
    shutdown: &WindowsPipeShutdown,
    counters: &ListenerCounters,
) -> Result<()> {
    let mut next_worker = 0;
    while !shutdown.is_requested() {
        let mut polls: [WSAPOLLFD; 2] = std::array::from_fn(|index| WSAPOLLFD {
            fd: listeners[index].as_raw_socket() as usize,
            events: POLLIN,
            revents: 0,
        });
        // SAFETY: polls holds two initialized writable records and both listener
        // sockets remain owned and live for this synchronous call.
        let result =
            unsafe { WSAPoll(polls.as_mut_ptr(), polls.len() as u32, SHUTDOWN_POLL_MILLIS) };
        if result == SOCKET_ERROR {
            // SAFETY: WSAPoll just failed on this thread.
            let error = unsafe { WSAGetLastError() };
            return Err(io::Error::from_raw_os_error(error)).context("poll strict TCP listeners");
        }
        for (listener, poll) in listeners.iter().zip(polls) {
            if poll.revents & POLLNVAL != 0 {
                bail!("strict TCP listener socket became invalid");
            }
            if poll.revents & (POLLERR | POLLHUP) != 0 && poll.revents & POLLIN == 0 {
                bail!("strict TCP listener socket failed");
            }
            if poll.revents & POLLIN == 0 {
                continue;
            }
            loop {
                match listener.accept() {
                    Ok((stream, peer)) => {
                        increment(&counters.accepted_connections);
                        if !peer.ip().is_loopback() || peer.port() == 0 {
                            increment(&counters.rejected_connections);
                            continue;
                        }
                        if !dispatch_connection(stream, senders, &mut next_worker) {
                            increment(&counters.rejected_connections);
                        }
                    }
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => break,
                    Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                    Err(error) => return Err(error).context("accept strict TCP relay connection"),
                }
            }
        }
    }
    Ok(())
}

fn dispatch_connection(
    stream: TcpStream,
    senders: &[SyncSender<TcpStream>],
    next_worker: &mut usize,
) -> bool {
    let mut pending = Some(stream);
    for offset in 0..senders.len() {
        let index = (*next_worker + offset) % senders.len();
        let stream = pending.take().expect("one strict TCP stream is pending");
        match senders[index].try_send(stream) {
            Ok(()) => {
                *next_worker = (index + 1) % senders.len();
                return true;
            }
            Err(TrySendError::Full(stream) | TrySendError::Disconnected(stream)) => {
                pending = Some(stream);
            }
        }
    }
    false
}

fn join_workers(workers: Vec<JoinHandle<()>>) -> Result<()> {
    for worker in workers {
        worker
            .join()
            .map_err(|_| anyhow::anyhow!("strict TCP listener worker panicked outside handler"))?;
    }
    Ok(())
}

fn increment(counter: &AtomicU64) {
    let _ = counter.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
        Some(value.saturating_add(1))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn connected_stream() -> TcpStream {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (_server, _) = listener.accept().unwrap();
        client
    }

    #[test]
    fn one_slot_per_worker_is_a_hard_queue_bound() {
        let (first_tx, first_rx) = mpsc::sync_channel(WORKER_QUEUE_CAPACITY);
        let (second_tx, second_rx) = mpsc::sync_channel(WORKER_QUEUE_CAPACITY);
        let senders = [first_tx, second_tx];
        let mut next_worker = 0;

        assert!(dispatch_connection(
            connected_stream(),
            &senders,
            &mut next_worker
        ));
        assert!(dispatch_connection(
            connected_stream(),
            &senders,
            &mut next_worker
        ));
        assert!(!dispatch_connection(
            connected_stream(),
            &senders,
            &mut next_worker
        ));
        assert!(first_rx.try_recv().is_ok());
        assert!(second_rx.try_recv().is_ok());
    }

    #[test]
    fn listener_binding_preserves_exact_endpoints_until_handler_installation() {
        let binding = WindowsTcpListenerBinding::bind().unwrap();
        let endpoints = binding.endpoints();
        let retained = binding.retention_handles().unwrap();
        let pool = binding.into_pool(2, |_, _| Ok(())).unwrap();

        assert_eq!(pool.endpoints(), endpoints);
        drop(pool);
        assert!(TcpStream::connect(endpoints.v4()).is_ok());
        assert!(TcpStream::connect(endpoints.v6()).is_ok());
        drop(retained);
        assert_eq!(endpoints.v4().ip(), &Ipv4Addr::LOCALHOST);
        assert_eq!(endpoints.v6().ip(), &Ipv6Addr::LOCALHOST);
    }
}
