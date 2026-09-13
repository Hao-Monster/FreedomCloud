use std::io::{self, Read, Write};
use std::net::{Shutdown, TcpStream};
use std::os::windows::io::AsRawSocket;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use windows_sys::Win32::Networking::WinSock::{
    WSAGetLastError, WSAPoll, POLLERR, POLLHUP, POLLIN, POLLNVAL, POLLOUT, SOCKET_ERROR, WSAPOLLFD,
};

use crate::WindowsPipeShutdown;

const RELAY_BUFFER_BYTES: usize = 16 * 1024;
const MAX_IDLE_TIMEOUT: Duration = Duration::from_secs(30 * 60);
const SHUTDOWN_POLL_SLICE: Duration = Duration::from_millis(100);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowsTcpRelayLimits {
    idle_timeout: Duration,
}

impl WindowsTcpRelayLimits {
    pub fn new(idle_timeout: Duration) -> Result<Self> {
        if idle_timeout.as_millis() == 0 || idle_timeout > MAX_IDLE_TIMEOUT {
            bail!("strict TCP relay idle timeout is invalid");
        }
        Ok(Self { idle_timeout })
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct WindowsTcpRelayReport {
    pub client_to_upstream_bytes: u64,
    pub upstream_to_client_bytes: u64,
}

pub fn relay_windows_tcp_bidirectional(
    mut client: TcpStream,
    mut upstream: TcpStream,
    shutdown: &WindowsPipeShutdown,
    limits: WindowsTcpRelayLimits,
) -> Result<WindowsTcpRelayReport> {
    WindowsTcpRelayLimits::new(limits.idle_timeout)?;
    client
        .set_nonblocking(true)
        .context("make strict relay client nonblocking")?;
    upstream
        .set_nonblocking(true)
        .context("make strict relay upstream nonblocking")?;
    client
        .set_nodelay(true)
        .context("enable strict relay client TCP no-delay")?;
    upstream
        .set_nodelay(true)
        .context("enable strict relay upstream TCP no-delay")?;

    let mut client_to_upstream = RelayBuffer::new();
    let mut upstream_to_client = RelayBuffer::new();
    let mut client_eof = false;
    let mut upstream_eof = false;
    let mut client_write_shutdown = false;
    let mut upstream_write_shutdown = false;
    let mut last_activity = Instant::now();
    let mut report = WindowsTcpRelayReport::default();

    loop {
        if shutdown.is_requested() {
            let _ = client.shutdown(Shutdown::Both);
            let _ = upstream.shutdown(Shutdown::Both);
            return Ok(report);
        }
        if client_eof && client_to_upstream.is_empty() && !upstream_write_shutdown {
            shutdown_write(&upstream)?;
            upstream_write_shutdown = true;
        }
        if upstream_eof && upstream_to_client.is_empty() && !client_write_shutdown {
            shutdown_write(&client)?;
            client_write_shutdown = true;
        }
        if client_eof
            && upstream_eof
            && client_to_upstream.is_empty()
            && upstream_to_client.is_empty()
        {
            return Ok(report);
        }

        client_to_upstream.compact();
        upstream_to_client.compact();
        let mut polls = [
            WSAPOLLFD {
                fd: client.as_raw_socket() as usize,
                events: (((!client_eof && client_to_upstream.has_capacity()) as i16) * POLLIN)
                    | (((!upstream_to_client.is_empty()) as i16) * POLLOUT),
                revents: 0,
            },
            WSAPOLLFD {
                fd: upstream.as_raw_socket() as usize,
                events: (((!upstream_eof && upstream_to_client.has_capacity()) as i16) * POLLIN)
                    | (((!client_to_upstream.is_empty()) as i16) * POLLOUT),
                revents: 0,
            },
        ];
        if polls.iter().all(|poll| poll.events == 0) {
            bail!("strict TCP relay reached an impossible stalled state");
        }

        let elapsed = last_activity.elapsed();
        if elapsed >= limits.idle_timeout {
            bail!("strict TCP relay idle deadline exceeded");
        }
        let poll_timeout = (limits.idle_timeout - elapsed).min(SHUTDOWN_POLL_SLICE);
        let poll_timeout = poll_timeout_millis(poll_timeout)?;
        // SAFETY: polls contains two initialized writable WSAPOLLFD values and
        // both sockets remain owned and live for the duration of this call.
        let result = unsafe { WSAPoll(polls.as_mut_ptr(), polls.len() as u32, poll_timeout) };
        if result == SOCKET_ERROR {
            // SAFETY: WSAPoll just failed on this thread.
            let error = unsafe { WSAGetLastError() };
            return Err(io::Error::from_raw_os_error(error)).context("poll strict TCP relay");
        }
        if polls.iter().any(|poll| poll.revents & POLLNVAL != 0) {
            bail!("strict TCP relay socket became invalid");
        }

        let mut progressed = false;
        if polls[0].revents & POLLOUT != 0 {
            let written = write_available(&mut client, &mut upstream_to_client)?;
            add_bytes(&mut report.upstream_to_client_bytes, written)?;
            progressed |= written != 0;
        }
        if polls[1].revents & POLLOUT != 0 {
            let written = write_available(&mut upstream, &mut client_to_upstream)?;
            add_bytes(&mut report.client_to_upstream_bytes, written)?;
            progressed |= written != 0;
        }

        let client_read_event = polls[0].revents & (POLLIN | POLLHUP | POLLERR);
        if !client_eof && client_to_upstream.has_capacity() && client_read_event != 0 {
            let read = read_available(
                &mut client,
                &mut client_to_upstream,
                client_read_event & POLLHUP != 0,
                &mut client_eof,
            )?;
            progressed |= read != 0;
        }
        let upstream_read_event = polls[1].revents & (POLLIN | POLLHUP | POLLERR);
        if !upstream_eof && upstream_to_client.has_capacity() && upstream_read_event != 0 {
            let read = read_available(
                &mut upstream,
                &mut upstream_to_client,
                upstream_read_event & POLLHUP != 0,
                &mut upstream_eof,
            )?;
            progressed |= read != 0;
        }
        if progressed {
            last_activity = Instant::now();
        }
    }
}

struct RelayBuffer {
    bytes: [u8; RELAY_BUFFER_BYTES],
    start: usize,
    end: usize,
}

impl RelayBuffer {
    fn new() -> Self {
        Self {
            bytes: [0_u8; RELAY_BUFFER_BYTES],
            start: 0,
            end: 0,
        }
    }

    fn is_empty(&self) -> bool {
        self.start == self.end
    }

    fn has_capacity(&self) -> bool {
        self.end < self.bytes.len()
    }

    fn compact(&mut self) {
        if self.is_empty() {
            self.start = 0;
            self.end = 0;
        } else if self.end == self.bytes.len() && self.start != 0 {
            self.bytes.copy_within(self.start..self.end, 0);
            self.end -= self.start;
            self.start = 0;
        }
    }

    fn writable(&mut self) -> &mut [u8] {
        &mut self.bytes[self.end..]
    }

    fn pending(&self) -> &[u8] {
        &self.bytes[self.start..self.end]
    }

    fn produced(&mut self, bytes: usize) {
        self.end += bytes;
        debug_assert!(self.end <= self.bytes.len());
    }

    fn consumed(&mut self, bytes: usize) {
        self.start += bytes;
        debug_assert!(self.start <= self.end);
    }
}

fn read_available(
    source: &mut TcpStream,
    buffer: &mut RelayBuffer,
    hung_up: bool,
    eof: &mut bool,
) -> Result<usize> {
    match source.read(buffer.writable()) {
        Ok(0) => {
            *eof = true;
            Ok(0)
        }
        Ok(bytes) => {
            buffer.produced(bytes);
            Ok(bytes)
        }
        Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
            if hung_up {
                *eof = true;
            }
            Ok(0)
        }
        Err(error) if error.kind() == io::ErrorKind::Interrupted => Ok(0),
        Err(error) => Err(error).context("read strict TCP relay source"),
    }
}

fn write_available(destination: &mut TcpStream, buffer: &mut RelayBuffer) -> Result<usize> {
    match destination.write(buffer.pending()) {
        Ok(0) => bail!("strict TCP relay destination accepted zero bytes"),
        Ok(bytes) => {
            buffer.consumed(bytes);
            Ok(bytes)
        }
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
            ) =>
        {
            Ok(0)
        }
        Err(error) => Err(error).context("write strict TCP relay destination"),
    }
}

fn shutdown_write(stream: &TcpStream) -> Result<()> {
    stream
        .shutdown(Shutdown::Write)
        .context("propagate strict TCP relay half-close")
}

fn add_bytes(total: &mut u64, bytes: usize) -> Result<()> {
    *total = total
        .checked_add(u64::try_from(bytes).context("strict TCP relay byte count exceeds u64")?)
        .ok_or_else(|| anyhow::anyhow!("strict TCP relay byte count overflow"))?;
    Ok(())
}

fn poll_timeout_millis(timeout: Duration) -> Result<i32> {
    let millis = timeout.as_millis();
    let rounded = millis + u128::from(timeout.subsec_nanos() % 1_000_000 != 0);
    i32::try_from(rounded.max(1)).context("strict TCP relay poll timeout exceeds Winsock range")
}
