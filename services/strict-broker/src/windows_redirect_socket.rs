use std::io;
use std::mem::size_of;
use std::net::{Ipv4Addr, SocketAddrV4, TcpStream};
use std::os::windows::io::{AsRawSocket, FromRawSocket, OwnedSocket};
use std::ptr::{null, null_mut};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use windows_sys::Win32::Foundation::ERROR_INSUFFICIENT_BUFFER;
use windows_sys::Win32::Networking::WinSock::{
    connect, getsockopt, ioctlsocket, WSAGetLastError, WSAIoctl, WSAPoll, WSASocketW, AF_INET,
    FIONBIO, INVALID_SOCKET, IPPROTO_TCP, POLLNVAL, POLLOUT,
    SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT, SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
    SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS, SOCKADDR, SOCKADDR_IN, SOCKET_ERROR, SOCK_STREAM,
    SOL_SOCKET, SO_ERROR, WSAEALREADY, WSAEINPROGRESS, WSAEWOULDBLOCK, WSAPOLLFD,
    WSA_FLAG_NO_HANDLE_INHERIT, WSA_FLAG_OVERLAPPED,
};

use crate::{
    parse_strict_redirect_context, StrictRedirectContext, StrictRedirectLeaseBinding,
    StrictRedirectTransport,
};

const INITIAL_REDIRECT_RECORD_BYTES: usize = 1024;
const MAX_REDIRECT_RECORD_BYTES: usize = 64 * 1024;
const REDIRECT_CONTEXT_BYTES: usize = 112;
const MAX_OUTBOUND_CONNECT_TIMEOUT: Duration = Duration::from_secs(30);

pub struct WindowsRedirectSocketMetadata {
    context: StrictRedirectContext,
    redirect_records: Vec<u8>,
}

impl WindowsRedirectSocketMetadata {
    pub fn context(&self) -> StrictRedirectContext {
        self.context
    }

    /// Opaque WFP data that must be applied to the new outbound socket before connect.
    pub fn redirect_records(&self) -> &[u8] {
        &self.redirect_records
    }
}

pub fn query_windows_redirect_socket(
    stream: &TcpStream,
    binding: &StrictRedirectLeaseBinding,
    expected_transport: StrictRedirectTransport,
) -> Result<WindowsRedirectSocketMetadata> {
    let context_bytes = query_wfp_redirect_bytes(
        stream,
        SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
        REDIRECT_CONTEXT_BYTES,
        REDIRECT_CONTEXT_BYTES,
        "context",
    )?;
    let context = parse_strict_redirect_context(&context_bytes, binding, expected_transport)?;
    let redirect_records = query_wfp_redirect_bytes(
        stream,
        SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
        INITIAL_REDIRECT_RECORD_BYTES,
        MAX_REDIRECT_RECORD_BYTES,
        "records",
    )?;
    Ok(WindowsRedirectSocketMetadata {
        context,
        redirect_records,
    })
}

pub fn connect_windows_redirected_outbound(
    endpoint: SocketAddrV4,
    redirect_records: &[u8],
    timeout: Duration,
) -> Result<TcpStream> {
    if endpoint.ip() != &Ipv4Addr::LOCALHOST || endpoint.port() == 0 {
        bail!("strict redirected outbound endpoint must be exact IPv4 loopback");
    }
    if redirect_records.is_empty() || redirect_records.len() > MAX_REDIRECT_RECORD_BYTES {
        bail!("strict WFP redirect record size is invalid");
    }
    if timeout.as_millis() == 0 || timeout > MAX_OUTBOUND_CONNECT_TIMEOUT {
        bail!("strict redirected outbound connect timeout is invalid");
    }

    // SAFETY: all optional protocol/group pointers are null and the requested
    // address family/type/protocol form a standard TCP socket.
    let socket = unsafe {
        WSASocketW(
            i32::from(AF_INET),
            SOCK_STREAM,
            IPPROTO_TCP,
            null(),
            0,
            WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT,
        )
    };
    if socket == INVALID_SOCKET {
        return Err(last_winsock_error()).context("create strict redirected outbound socket");
    }
    // SAFETY: WSASocketW returned one unique owned socket value.
    let owned = unsafe { OwnedSocket::from_raw_socket(socket as u64) };
    apply_redirect_records(socket, redirect_records)?;

    let mut nonblocking = 1_u32;
    // SAFETY: socket is live and `nonblocking` is a writable mode value.
    if unsafe { ioctlsocket(socket, FIONBIO, &mut nonblocking) } == SOCKET_ERROR {
        return Err(last_winsock_error()).context("make strict outbound socket nonblocking");
    }

    let mut address = SOCKADDR_IN {
        sin_family: AF_INET,
        sin_port: endpoint.port().to_be(),
        ..SOCKADDR_IN::default()
    };
    address.sin_addr.S_un.S_addr = u32::from_ne_bytes(endpoint.ip().octets());
    // SAFETY: address has the exact SOCKADDR_IN layout and socket is live.
    let connect_result = unsafe {
        connect(
            socket,
            (&raw const address).cast::<SOCKADDR>(),
            size_of::<SOCKADDR_IN>() as i32,
        )
    };
    if connect_result == SOCKET_ERROR {
        // SAFETY: connect just failed on this thread.
        let error = unsafe { WSAGetLastError() };
        if !matches!(error, WSAEWOULDBLOCK | WSAEINPROGRESS | WSAEALREADY) {
            return Err(io::Error::from_raw_os_error(error))
                .context("start strict redirected outbound connect");
        }
        wait_for_connect(socket, timeout)?;
    }

    let mut blocking = 0_u32;
    // SAFETY: socket is live and `blocking` is a writable mode value.
    if unsafe { ioctlsocket(socket, FIONBIO, &mut blocking) } == SOCKET_ERROR {
        return Err(last_winsock_error()).context("restore strict outbound socket blocking mode");
    }
    let stream = TcpStream::from(owned);
    stream
        .set_nodelay(true)
        .context("enable strict outbound TCP no-delay")?;
    Ok(stream)
}

fn apply_redirect_records(socket: usize, redirect_records: &[u8]) -> Result<()> {
    let mut returned = 0_u32;
    // SAFETY: socket is live and the opaque record bytes remain readable for
    // this synchronous call. WFP copies the records before returning.
    let result = unsafe {
        WSAIoctl(
            socket,
            SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS,
            redirect_records.as_ptr().cast(),
            redirect_records.len() as u32,
            null_mut(),
            0,
            &mut returned,
            null_mut(),
            None,
        )
    };
    if result == SOCKET_ERROR {
        return Err(last_winsock_error()).context("apply strict WFP redirect records");
    }
    if returned != 0 {
        bail!("setting strict WFP redirect records returned unexpected output");
    }
    Ok(())
}

fn wait_for_connect(socket: usize, timeout: Duration) -> Result<()> {
    let timeout_millis = i32::try_from(timeout.as_millis())
        .context("strict outbound connect timeout exceeds Winsock range")?;
    let mut poll = WSAPOLLFD {
        fd: socket,
        events: POLLOUT,
        revents: 0,
    };
    // SAFETY: poll points to one writable WSAPOLLFD and socket remains live.
    let result = unsafe { WSAPoll(&mut poll, 1, timeout_millis) };
    if result == SOCKET_ERROR {
        return Err(last_winsock_error()).context("poll strict redirected outbound connect");
    }
    if result == 0 {
        bail!("strict redirected outbound connect timed out");
    }
    if poll.revents & POLLNVAL != 0 {
        bail!("strict redirected outbound socket became invalid");
    }

    let mut socket_error = 0_i32;
    let mut option_bytes = size_of::<i32>() as i32;
    // SAFETY: output pointers describe one writable i32 socket option.
    if unsafe {
        getsockopt(
            socket,
            SOL_SOCKET,
            SO_ERROR,
            (&raw mut socket_error).cast::<u8>(),
            &mut option_bytes,
        )
    } == SOCKET_ERROR
    {
        return Err(last_winsock_error()).context("read strict outbound connect status");
    }
    if option_bytes as usize != size_of::<i32>() {
        bail!("strict outbound connect status size is invalid");
    }
    if socket_error != 0 {
        return Err(io::Error::from_raw_os_error(socket_error))
            .context("complete strict redirected outbound connect");
    }
    Ok(())
}

fn last_winsock_error() -> io::Error {
    // SAFETY: this helper is called immediately after a Winsock failure on the same thread.
    io::Error::from_raw_os_error(unsafe { WSAGetLastError() })
}

fn query_wfp_redirect_bytes(
    stream: &TcpStream,
    control_code: u32,
    initial_bytes: usize,
    maximum_bytes: usize,
    label: &str,
) -> Result<Vec<u8>> {
    if initial_bytes < size_of::<u32>()
        || initial_bytes > maximum_bytes
        || maximum_bytes > u32::MAX as usize
    {
        bail!("strict WFP redirect {label} buffer bound is invalid");
    }
    let socket = usize::try_from(stream.as_raw_socket())
        .context("strict redirected socket handle exceeds Winsock width")?;
    let mut bytes = vec![0_u8; initial_bytes];
    for attempt in 0..2 {
        let mut returned = 0_u32;
        // SAFETY: the socket is live; the output allocation and byte-count
        // pointer remain writable for the duration of this synchronous call.
        let result = unsafe {
            WSAIoctl(
                socket,
                control_code,
                null(),
                0,
                bytes.as_mut_ptr().cast(),
                bytes.len() as u32,
                &mut returned,
                null_mut(),
                None,
            )
        };
        if result != SOCKET_ERROR {
            let returned = returned as usize;
            if returned == 0 || returned > bytes.len() {
                bail!("strict WFP redirect {label} returned an invalid size");
            }
            bytes.truncate(returned);
            return Ok(bytes);
        }

        // SAFETY: WSAIoctl just failed on this thread.
        let error = unsafe { WSAGetLastError() };
        let required = returned as usize;
        if attempt == 0
            && error == ERROR_INSUFFICIENT_BUFFER as i32
            && required > bytes.len()
            && required <= maximum_bytes
        {
            bytes.resize(required, 0);
            continue;
        }
        return Err(io::Error::from_raw_os_error(error))
            .with_context(|| format!("query strict WFP redirect {label}"));
    }
    unreachable!("redirect query has a fixed attempt count")
}
