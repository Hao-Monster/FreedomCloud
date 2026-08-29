use std::ffi::c_void;
use std::fmt;
use std::io;
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::Path;
use std::ptr::{null, null_mut};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{
    parse_broker_activation_request, parse_broker_activation_response, parse_broker_request,
    parse_broker_response, BrokerActivationErrorCode, BrokerActivationRequest,
    BrokerActivationResponse, BrokerResponse, MAX_BROKER_ACTIVATION_FRAME_BYTES,
    MAX_BROKER_FRAME_BYTES,
};
use windows_sys::Win32::Foundation::{
    LocalFree, ERROR_IO_PENDING, ERROR_MORE_DATA, ERROR_NOT_FOUND, ERROR_OPERATION_ABORTED,
    ERROR_PIPE_CONNECTED, INVALID_HANDLE_VALUE, WAIT_FAILED, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows_sys::Win32::Security::Authorization::{
    ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
    ConvertStringSidToSidW, SDDL_REVISION_1,
};
use windows_sys::Win32::Security::Cryptography::{
    BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG,
};
use windows_sys::Win32::Security::{
    CheckTokenMembership, CreateWellKnownSid, GetTokenInformation, RevertToSelf, TokenUser,
    WinBuiltinAdministratorsSid, PSECURITY_DESCRIPTOR, PSID, SECURITY_ATTRIBUTES, TOKEN_QUERY,
    TOKEN_USER,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, ReadFile, WriteFile, FILE_FLAG_FIRST_PIPE_INSTANCE, FILE_FLAG_OVERLAPPED,
    FILE_READ_ATTRIBUTES, FILE_READ_DATA, FILE_READ_EA, FILE_WRITE_ATTRIBUTES, FILE_WRITE_DATA,
    FILE_WRITE_EA, OPEN_EXISTING, PIPE_ACCESS_DUPLEX, READ_CONTROL, SECURITY_IDENTIFICATION,
    SECURITY_SQOS_PRESENT, SYNCHRONIZE,
};
use windows_sys::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, GetNamedPipeClientProcessId,
    GetNamedPipeClientSessionId, ImpersonateNamedPipeClient, PIPE_READMODE_MESSAGE,
    PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_MESSAGE,
};
use windows_sys::Win32::System::Threading::{
    CreateEventW, GetCurrentProcess, GetCurrentThread, OpenProcessToken, OpenThreadToken,
    WaitForSingleObject,
};
use windows_sys::Win32::System::IO::{CancelIoEx, GetOverlappedResult, OVERLAPPED};

use crate::{
    verify_windows_packaged_agent_process, verify_windows_packaged_agent_process_with_image,
    AuthorizedBrokerRequest, BrokerAuthenticator, ClientPrincipal, ClientRole,
    StrictPackageManifest, WindowsAgentImageTrustLease, WindowsAgentProcessTrustLease,
};

const PIPE_NAME_PREFIX: &str = r"\\.\pipe\FlClashX.StrictBroker.";
const ACTIVATION_PIPE_NAME_PREFIX: &str = r"\\.\pipe\FlClashX.StrictBroker.Activation.";
const PIPE_BUFFER_BYTES: u32 = 64 * 1024;
const MAX_PIPE_DEADLINE: Duration = Duration::from_secs(300);
const CLIENT_PIPE_ACCESS: u32 = FILE_READ_DATA
    | FILE_READ_ATTRIBUTES
    | FILE_READ_EA
    | FILE_WRITE_DATA
    | FILE_WRITE_ATTRIBUTES
    | FILE_WRITE_EA
    | READ_CONTROL
    | SYNCHRONIZE;

pub fn generate_windows_broker_session_pipe_name() -> Result<String> {
    let mut nonce = [0_u8; 16];
    // SAFETY: a null algorithm handle with the system-preferred flag is documented,
    // and nonce is a valid writable buffer for the supplied length.
    let status = unsafe {
        BCryptGenRandom(
            null_mut(),
            nonce.as_mut_ptr(),
            nonce.len() as u32,
            BCRYPT_USE_SYSTEM_PREFERRED_RNG,
        )
    };
    if status != 0 || nonce.iter().all(|byte| *byte == 0) {
        bail!("generate strict Broker session pipe identity failed with status 0x{status:08x}");
    }
    let mut suffix = String::with_capacity(nonce.len() * 2);
    use std::fmt::Write as _;
    for byte in nonce {
        write!(suffix, "{byte:02x}").expect("writing to a String cannot fail");
    }
    let pipe_name = format!(r"{PIPE_NAME_PREFIX}Session.{suffix}");
    validate_pipe_name(&pipe_name)?;
    Ok(pipe_name)
}

pub struct WindowsAuthenticatedRequest {
    pub authorized: AuthorizedBrokerRequest,
    pub client_process_id: u32,
    pub client_sid: String,
}

pub struct WindowsVerifiedActivationRequest {
    pub request: BrokerActivationRequest,
    pub client_sid: String,
    pub client_session_id: u32,
    pub agent: WindowsAgentProcessTrustLease,
}

pub enum WindowsBrokerActivationAttempt {
    Verified(WindowsVerifiedActivationRequest),
    Rejected(BrokerActivationResponse),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowsPipeDeadlines {
    connect: Duration,
    read: Duration,
    write: Duration,
}

impl WindowsPipeDeadlines {
    pub fn new(connect: Duration, read: Duration, write: Duration) -> Result<Self> {
        for (label, value) in [("connect", connect), ("read", read), ("write", write)] {
            if value.is_zero() || value > MAX_PIPE_DEADLINE {
                bail!("strict Broker pipe {label} deadline is invalid");
            }
        }
        Ok(Self {
            connect,
            read,
            write,
        })
    }

    pub(crate) fn connect_timeout(self) -> Duration {
        self.connect
    }
}

impl Default for WindowsPipeDeadlines {
    fn default() -> Self {
        Self {
            connect: Duration::from_secs(30),
            read: Duration::from_secs(5),
            write: Duration::from_secs(5),
        }
    }
}

pub struct WindowsNamedPipeInstance {
    handle: OwnedHandle,
    owner_sid: String,
    deadlines: WindowsPipeDeadlines,
}

impl WindowsNamedPipeInstance {
    pub fn create(pipe_name: &str, owner_sid: &str) -> Result<Self> {
        Self::create_with_deadlines(pipe_name, owner_sid, WindowsPipeDeadlines::default())
    }

    pub fn create_with_deadlines(
        pipe_name: &str,
        owner_sid: &str,
        deadlines: WindowsPipeDeadlines,
    ) -> Result<Self> {
        Self::create_internal(pipe_name, owner_sid, deadlines, true, 1)
    }

    pub(crate) fn create_pool_instance(
        pipe_name: &str,
        owner_sid: &str,
        deadlines: WindowsPipeDeadlines,
        first_instance: bool,
        maximum_instances: u32,
    ) -> Result<Self> {
        Self::create_internal(
            pipe_name,
            owner_sid,
            deadlines,
            first_instance,
            maximum_instances,
        )
    }

    fn create_internal(
        pipe_name: &str,
        owner_sid: &str,
        deadlines: WindowsPipeDeadlines,
        first_instance: bool,
        maximum_instances: u32,
    ) -> Result<Self> {
        validate_pipe_name(pipe_name)?;
        WindowsPipeDeadlines::new(deadlines.connect, deadlines.read, deadlines.write)?;
        if maximum_instances == 0 || maximum_instances > 255 {
            bail!("strict Broker pipe instance count is invalid");
        }
        let owner_sid = canonical_sid(owner_sid)?;
        let security_descriptor = PipeSecurityDescriptor::new(&owner_sid)?;
        let attributes = SECURITY_ATTRIBUTES {
            nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: security_descriptor.0,
            bInheritHandle: 0,
        };
        let pipe_name = wide_null(pipe_name);
        let open_mode = PIPE_ACCESS_DUPLEX
            | FILE_FLAG_OVERLAPPED
            | if first_instance {
                FILE_FLAG_FIRST_PIPE_INSTANCE
            } else {
                0
            };
        // SAFETY: all pointers reference initialized values for the duration of the call.
        let handle = unsafe {
            CreateNamedPipeW(
                pipe_name.as_ptr(),
                open_mode,
                PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_REJECT_REMOTE_CLIENTS,
                maximum_instances,
                PIPE_BUFFER_BYTES,
                PIPE_BUFFER_BYTES,
                0,
                &attributes,
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error()).context("create strict Broker named pipe");
        }
        // SAFETY: CreateNamedPipeW returned a unique, owned handle.
        let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
        Ok(Self {
            handle,
            owner_sid,
            deadlines,
        })
    }

    pub fn connect_and_authenticate(
        &self,
        authenticator: &BrokerAuthenticator,
    ) -> Result<WindowsAuthenticatedRequest> {
        self.connect()?;
        let frame = self.read_message()?;
        let identity = resolve_client_identity(raw_handle(&self.handle), &self.owner_sid)?;
        let frame = std::str::from_utf8(&frame).context("Broker request is not UTF-8")?;
        let authorized = authenticator.authenticate(&identity.principal, frame)?;
        Ok(WindowsAuthenticatedRequest {
            authorized,
            client_process_id: identity.process_id,
            client_sid: identity.sid,
        })
    }

    pub fn write_response(&self, response: &BrokerResponse) -> Result<()> {
        write_message(
            raw_handle(&self.handle),
            &response.to_bytes()?,
            "response",
            self.deadlines.write,
        )
    }

    fn connect(&self) -> Result<()> {
        match run_overlapped(
            raw_handle(&self.handle),
            self.deadlines.connect,
            "connect",
            |overlapped, _| {
                // SAFETY: the handle is a live server instance and overlapped remains live.
                unsafe { ConnectNamedPipe(raw_handle(&self.handle), overlapped) }
            },
        )? {
            IoCompletion::Complete(_) => Ok(()),
            IoCompletion::MoreData(_) => {
                bail!("strict Broker named-pipe connect returned message data")
            }
        }
    }

    fn read_message(&self) -> Result<Vec<u8>> {
        read_message(raw_handle(&self.handle), "request", self.deadlines.read)
    }

    pub(crate) fn disconnect_for_reuse(&self) {
        // SAFETY: this is a live server pipe. An idle/cancelled instance may already be detached.
        unsafe {
            DisconnectNamedPipe(raw_handle(&self.handle));
        }
    }
}

impl Drop for WindowsNamedPipeInstance {
    fn drop(&mut self) {
        // SAFETY: disconnecting an unconnected live pipe is harmless and the handle remains owned.
        unsafe {
            DisconnectNamedPipe(raw_handle(&self.handle));
        }
    }
}

pub struct WindowsBrokerActivationPipeInstance {
    handle: OwnedHandle,
    deadlines: WindowsPipeDeadlines,
}

impl WindowsBrokerActivationPipeInstance {
    pub fn create(pipe_name: &str, deadlines: WindowsPipeDeadlines) -> Result<Self> {
        validate_activation_pipe_name(pipe_name)?;
        WindowsPipeDeadlines::new(deadlines.connect, deadlines.read, deadlines.write)?;
        let security_descriptor = PipeSecurityDescriptor::new_activation()?;
        let attributes = SECURITY_ATTRIBUTES {
            nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: security_descriptor.0,
            bInheritHandle: 0,
        };
        let pipe_name = wide_null(pipe_name);
        // SAFETY: all pointers reference initialized values for the duration of the call.
        let handle = unsafe {
            CreateNamedPipeW(
                pipe_name.as_ptr(),
                PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_REJECT_REMOTE_CLIENTS,
                1,
                MAX_BROKER_ACTIVATION_FRAME_BYTES as u32,
                MAX_BROKER_ACTIVATION_FRAME_BYTES as u32,
                0,
                &attributes,
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error()).context("create strict Broker activation pipe");
        }
        // SAFETY: CreateNamedPipeW returned a unique, owned handle.
        let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
        Ok(Self { handle, deadlines })
    }

    pub fn connect_and_verify(
        &self,
        expected_agent_path: impl AsRef<Path>,
        package: &StrictPackageManifest,
    ) -> Result<WindowsVerifiedActivationRequest> {
        match self.connect_and_classify(expected_agent_path, package)? {
            WindowsBrokerActivationAttempt::Verified(activation) => Ok(activation),
            WindowsBrokerActivationAttempt::Rejected(_) => {
                bail!("strict Broker activation identity was rejected")
            }
        }
    }

    pub fn connect_and_classify(
        &self,
        expected_agent_path: impl AsRef<Path>,
        package: &StrictPackageManifest,
    ) -> Result<WindowsBrokerActivationAttempt> {
        let identity = self.connect_and_receive()?;
        let verification = (|| -> Result<WindowsAgentProcessTrustLease> {
            if identity.is_local_system {
                bail!("LocalSystem cannot activate an interactive Broker session");
            }
            if identity.client_session_id == 0 {
                bail!("session-zero clients cannot activate an interactive Broker session");
            }
            verify_windows_packaged_agent_process(
                identity.client_process_id,
                expected_agent_path,
                package,
            )
        })();
        classify_activation(identity, verification)
    }

    pub fn connect_and_classify_with_image(
        &self,
        image: &WindowsAgentImageTrustLease,
    ) -> Result<WindowsBrokerActivationAttempt> {
        let identity = self.connect_and_receive()?;
        let verification = (|| -> Result<WindowsAgentProcessTrustLease> {
            if identity.is_local_system {
                bail!("LocalSystem cannot activate an interactive Broker session");
            }
            if identity.client_session_id == 0 {
                bail!("session-zero clients cannot activate an interactive Broker session");
            }
            verify_windows_packaged_agent_process_with_image(identity.client_process_id, image)
        })();
        classify_activation(identity, verification)
    }

    fn connect_and_receive(&self) -> Result<PendingActivationRequest> {
        self.connect()?;
        let frame = read_message_bounded(
            raw_handle(&self.handle),
            "activation request",
            self.deadlines.read,
            MAX_BROKER_ACTIVATION_FRAME_BYTES,
        )?;
        let request = parse_broker_activation_request(&frame)?;
        let identity = resolve_local_client_identity(raw_handle(&self.handle))?;
        Ok(PendingActivationRequest {
            request,
            client_sid: identity.token.sid,
            client_process_id: identity.process_id,
            client_session_id: identity.session_id,
            is_local_system: identity.token.is_local_system,
        })
    }

    pub fn write_response(&self, response: &BrokerActivationResponse) -> Result<()> {
        write_message_bounded(
            raw_handle(&self.handle),
            &response.to_bytes()?,
            "activation response",
            self.deadlines.write,
            MAX_BROKER_ACTIVATION_FRAME_BYTES,
        )
    }

    pub fn disconnect_for_reuse(&self) {
        // SAFETY: this is a live server pipe. An idle/cancelled instance may already be detached.
        unsafe { DisconnectNamedPipe(raw_handle(&self.handle)) };
    }

    fn connect(&self) -> Result<()> {
        match run_overlapped(
            raw_handle(&self.handle),
            self.deadlines.connect,
            "activation connect",
            |overlapped, _| {
                // SAFETY: the handle is live and overlapped remains live until completion.
                unsafe { ConnectNamedPipe(raw_handle(&self.handle), overlapped) }
            },
        )? {
            IoCompletion::Complete(_) => Ok(()),
            IoCompletion::MoreData(_) => {
                bail!("strict Broker activation connect returned message data")
            }
        }
    }
}

fn classify_activation(
    identity: PendingActivationRequest,
    verification: Result<WindowsAgentProcessTrustLease>,
) -> Result<WindowsBrokerActivationAttempt> {
    let request_id = identity.request.request_id.clone();
    match verification {
        Ok(agent) => Ok(WindowsBrokerActivationAttempt::Verified(
            WindowsVerifiedActivationRequest {
                request: identity.request,
                client_sid: identity.client_sid,
                client_session_id: identity.client_session_id,
                agent,
            },
        )),
        Err(_) => Ok(WindowsBrokerActivationAttempt::Rejected(
            BrokerActivationResponse::error(request_id, BrokerActivationErrorCode::Unauthorized)?,
        )),
    }
}

struct PendingActivationRequest {
    request: BrokerActivationRequest,
    client_sid: String,
    client_process_id: u32,
    client_session_id: u32,
    is_local_system: bool,
}

impl Drop for WindowsBrokerActivationPipeInstance {
    fn drop(&mut self) {
        // SAFETY: disconnecting an unconnected live pipe is harmless.
        unsafe { DisconnectNamedPipe(raw_handle(&self.handle)) };
    }
}

pub fn exchange_windows_pipe_for_agent(pipe_name: &str, frame: &[u8]) -> Result<BrokerResponse> {
    validate_pipe_name(pipe_name)?;
    let request_frame = std::str::from_utf8(frame).context("Broker request is not UTF-8")?;
    let request = parse_broker_request(request_frame)?;
    let pipe_name = wide_null(pipe_name);
    // SECURITY_IDENTIFICATION lets the Broker inspect identity without obtaining delegation power.
    // SAFETY: the path pointer is NUL-terminated and all optional pointers are null.
    let handle = unsafe {
        CreateFileW(
            pipe_name.as_ptr(),
            CLIENT_PIPE_ACCESS,
            0,
            null(),
            OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
            null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error()).context("connect to strict Broker named pipe");
    }
    // SAFETY: CreateFileW returned a unique, owned handle.
    let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
    let deadlines = WindowsPipeDeadlines::default();
    write_message(raw_handle(&handle), frame, "request", deadlines.write)?;
    let response = parse_broker_response(&read_message(
        raw_handle(&handle),
        "response",
        deadlines.read,
    )?)?;
    if response.request_id != request.request_id {
        bail!("Broker response request ID does not match the request");
    }
    Ok(response)
}

pub fn exchange_windows_activation_for_agent(
    pipe_name: &str,
    frame: &[u8],
    deadlines: WindowsPipeDeadlines,
) -> Result<BrokerActivationResponse> {
    validate_activation_pipe_name(pipe_name)?;
    WindowsPipeDeadlines::new(deadlines.connect, deadlines.read, deadlines.write)?;
    let request = parse_broker_activation_request(frame)?;
    let pipe_name = wide_null(pipe_name);
    // SAFETY: the path pointer is NUL-terminated and optional pointers are null.
    let handle = unsafe {
        CreateFileW(
            pipe_name.as_ptr(),
            CLIENT_PIPE_ACCESS,
            0,
            null(),
            OPEN_EXISTING,
            FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
            null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error()).context("open strict Broker activation pipe");
    }
    // SAFETY: CreateFileW returned a unique, owned handle.
    let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
    write_message_bounded(
        raw_handle(&handle),
        frame,
        "activation request",
        deadlines.write,
        MAX_BROKER_ACTIVATION_FRAME_BYTES,
    )?;
    let response = parse_broker_activation_response(&read_message_bounded(
        raw_handle(&handle),
        "activation response",
        deadlines.read,
        MAX_BROKER_ACTIVATION_FRAME_BYTES,
    )?)?;
    if response.request_id != request.request_id {
        bail!("Broker activation response request ID does not match the request");
    }
    Ok(response)
}

fn write_message(handle: *mut c_void, frame: &[u8], label: &str, timeout: Duration) -> Result<()> {
    write_message_bounded(handle, frame, label, timeout, MAX_BROKER_FRAME_BYTES)
}

fn write_message_bounded(
    handle: *mut c_void,
    frame: &[u8],
    label: &str,
    timeout: Duration,
    maximum_bytes: usize,
) -> Result<()> {
    if frame.is_empty() || frame.len() > maximum_bytes {
        bail!("Broker {label} frame size is invalid");
    }
    let completion = run_overlapped(handle, timeout, label, |overlapped, transferred| {
        // SAFETY: frame remains readable and both output objects remain live until completion.
        unsafe {
            WriteFile(
                handle,
                frame.as_ptr(),
                frame.len() as u32,
                transferred,
                overlapped,
            )
        }
    })?;
    let IoCompletion::Complete(bytes_written) = completion else {
        bail!("strict Broker named-pipe {label} write returned message continuation");
    };
    if bytes_written as usize != frame.len() {
        bail!("strict Broker named-pipe {label} was partially written");
    }
    Ok(())
}

fn read_message(handle: *mut c_void, label: &str, timeout: Duration) -> Result<Vec<u8>> {
    read_message_bounded(handle, label, timeout, MAX_BROKER_FRAME_BYTES)
}

fn read_message_bounded(
    handle: *mut c_void,
    label: &str,
    timeout: Duration,
    maximum_bytes: usize,
) -> Result<Vec<u8>> {
    let mut message = Vec::with_capacity(maximum_bytes.min(PIPE_BUFFER_BYTES as usize));
    let deadline = Instant::now()
        .checked_add(timeout)
        .ok_or_else(|| anyhow::anyhow!("Broker {label} deadline is invalid"))?;
    loop {
        let remaining = maximum_bytes
            .checked_add(1)
            .and_then(|limit| limit.checked_sub(message.len()))
            .ok_or_else(|| anyhow::anyhow!("Broker {label} frame exceeds its size limit"))?;
        let chunk_size = remaining.min(PIPE_BUFFER_BYTES as usize);
        let start = message.len();
        message.resize(start + chunk_size, 0);
        let remaining_timeout = deadline
            .checked_duration_since(Instant::now())
            .ok_or_else(|| anyhow::anyhow!("strict Broker named-pipe {label} deadline exceeded"))?;
        let completion = run_overlapped(
            handle,
            remaining_timeout,
            label,
            |overlapped, transferred| {
                // SAFETY: the destination remains writable until the overlapped operation drains.
                unsafe {
                    ReadFile(
                        handle,
                        message[start..].as_mut_ptr(),
                        chunk_size as u32,
                        transferred,
                        overlapped,
                    )
                }
            },
        )?;
        let (bytes_read, more_data) = match completion {
            IoCompletion::Complete(bytes) => (bytes, false),
            IoCompletion::MoreData(bytes) => (bytes, true),
        };
        message.truncate(start + bytes_read as usize);
        if message.len() > maximum_bytes {
            bail!("Broker {label} frame exceeds its size limit");
        }
        if !more_data {
            if message.is_empty() {
                bail!("Broker {label} frame is empty");
            }
            return Ok(message);
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum IoCompletion {
    Complete(u32),
    MoreData(u32),
}

fn run_overlapped(
    handle: *mut c_void,
    timeout: Duration,
    label: &str,
    operation: impl FnOnce(*mut OVERLAPPED, *mut u32) -> i32,
) -> Result<IoCompletion> {
    // SAFETY: no custom security descriptor or name is supplied.
    let event = unsafe { CreateEventW(null(), 1, 0, null()) };
    if event.is_null() {
        return Err(io::Error::last_os_error()).context("create strict Broker I/O event");
    }
    // SAFETY: CreateEventW returned a unique owned handle.
    let event = unsafe { OwnedHandle::from_raw_handle(event) };
    let mut overlapped = OVERLAPPED {
        hEvent: raw_handle(&event),
        ..OVERLAPPED::default()
    };
    let mut immediate_bytes = 0_u32;
    let result = operation(&mut overlapped, &mut immediate_bytes);
    if result != 0 {
        return Ok(IoCompletion::Complete(immediate_bytes));
    }
    let error = io::Error::last_os_error();
    match error.raw_os_error().map(|value| value as u32) {
        Some(ERROR_PIPE_CONNECTED) => return Ok(IoCompletion::Complete(0)),
        Some(ERROR_MORE_DATA) => return Ok(IoCompletion::MoreData(immediate_bytes)),
        Some(ERROR_IO_PENDING) => {}
        _ => {
            return Err(error).with_context(|| format!("start strict Broker named-pipe {label}"));
        }
    }

    let wait_millis = timeout_to_millis(timeout)?;
    // SAFETY: the event remains live while the operation is pending.
    let wait_result = unsafe { WaitForSingleObject(raw_handle(&event), wait_millis) };
    if wait_result == WAIT_TIMEOUT {
        cancel_and_drain(handle, &overlapped)?;
        return Err(PipeDeadlineExceeded::new(label).into());
    }
    if wait_result != WAIT_OBJECT_0 {
        let wait_error = if wait_result == WAIT_FAILED {
            io::Error::last_os_error()
        } else {
            io::Error::other(format!("unexpected wait result 0x{wait_result:08x}"))
        };
        cancel_and_drain(handle, &overlapped)?;
        return Err(wait_error)
            .with_context(|| format!("wait for strict Broker named-pipe {label}"));
    }
    overlapped_completion(handle, &overlapped, label)
}

#[derive(Debug)]
struct PipeDeadlineExceeded {
    operation: String,
}

impl PipeDeadlineExceeded {
    fn new(operation: &str) -> Self {
        Self {
            operation: operation.to_owned(),
        }
    }
}

impl fmt::Display for PipeDeadlineExceeded {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "strict Broker named-pipe {} deadline exceeded",
            self.operation
        )
    }
}

impl std::error::Error for PipeDeadlineExceeded {}

pub(crate) fn is_connect_deadline(error: &anyhow::Error) -> bool {
    error
        .downcast_ref::<PipeDeadlineExceeded>()
        .is_some_and(|deadline| deadline.operation == "connect")
}

fn overlapped_completion(
    handle: *mut c_void,
    overlapped: &OVERLAPPED,
    label: &str,
) -> Result<IoCompletion> {
    let mut transferred = 0_u32;
    // SAFETY: the event was signalled and the OVERLAPPED remains live.
    if unsafe { GetOverlappedResult(handle, overlapped, &mut transferred, 0) } != 0 {
        return Ok(IoCompletion::Complete(transferred));
    }
    let error = io::Error::last_os_error();
    if error.raw_os_error() == Some(ERROR_MORE_DATA as i32) {
        Ok(IoCompletion::MoreData(transferred))
    } else {
        Err(error).with_context(|| format!("complete strict Broker named-pipe {label}"))
    }
}

fn cancel_and_drain(handle: *mut c_void, overlapped: &OVERLAPPED) -> Result<()> {
    // SAFETY: the OVERLAPPED belongs to a pending operation on this handle.
    let cancellation_error = if unsafe { CancelIoEx(handle, overlapped) } == 0 {
        let error = io::Error::last_os_error();
        if error.raw_os_error() != Some(ERROR_NOT_FOUND as i32) {
            Some(error)
        } else {
            None
        }
    } else {
        None
    };
    let mut transferred = 0_u32;
    // SAFETY: waiting drains completion before the OVERLAPPED and caller buffer are released.
    let drain_error =
        if unsafe { GetOverlappedResult(handle, overlapped, &mut transferred, 1) } == 0 {
            let error = io::Error::last_os_error();
            if !matches!(
                error.raw_os_error().map(|value| value as u32),
                Some(ERROR_OPERATION_ABORTED) | Some(ERROR_MORE_DATA)
            ) {
                Some(error)
            } else {
                None
            }
        } else {
            None
        };
    if let Some(error) = cancellation_error {
        return Err(error).context("cancel strict Broker named-pipe I/O");
    }
    if let Some(error) = drain_error {
        return Err(error).context("drain cancelled strict Broker named-pipe I/O");
    }
    Ok(())
}

fn timeout_to_millis(timeout: Duration) -> Result<u32> {
    if timeout.is_zero() || timeout > MAX_PIPE_DEADLINE {
        bail!("strict Broker pipe operation deadline is invalid");
    }
    let millis = timeout.as_millis();
    let rounded = millis + u128::from(timeout.subsec_nanos() % 1_000_000 != 0);
    u32::try_from(rounded).context("strict Broker pipe deadline exceeds Windows wait range")
}

pub fn current_process_user_sid() -> Result<String> {
    let mut token = null_mut();
    // SAFETY: the output pointer is valid and the pseudo process handle is always live.
    if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) } == 0 {
        return Err(io::Error::last_os_error()).context("open current process token");
    }
    // SAFETY: OpenProcessToken returned a unique, owned handle.
    let token = unsafe { OwnedHandle::from_raw_handle(token) };
    token_user_sid(raw_handle(&token))
}

struct ResolvedClientIdentity {
    principal: ClientPrincipal,
    process_id: u32,
    sid: String,
}

fn resolve_client_identity(handle: *mut c_void, owner_sid: &str) -> Result<ResolvedClientIdentity> {
    let identity = resolve_local_client_identity(handle)?;
    let token = identity.token;
    let role = if token.sid == owner_sid {
        ClientRole::Owner
    } else if token.is_administrator || token.is_local_system {
        ClientRole::RecoveryAdministrator
    } else {
        bail!("Broker client token is not an authorized owner or recovery administrator");
    };
    Ok(ResolvedClientIdentity {
        principal: ClientPrincipal::new(true, role),
        process_id: identity.process_id,
        sid: token.sid,
    })
}

struct LocalClientIdentity {
    process_id: u32,
    session_id: u32,
    token: TokenIdentity,
}

fn resolve_local_client_identity(handle: *mut c_void) -> Result<LocalClientIdentity> {
    let mut process_id = 0_u32;
    // SAFETY: handle is a connected server-side named-pipe instance.
    if unsafe { GetNamedPipeClientProcessId(handle, &mut process_id) } == 0 || process_id == 0 {
        return Err(io::Error::last_os_error()).context("resolve Broker client process ID");
    }
    let mut session_id = 0_u32;
    // SAFETY: handle is a connected server-side named-pipe instance.
    if unsafe { GetNamedPipeClientSessionId(handle, &mut session_id) } == 0 {
        return Err(io::Error::last_os_error()).context("resolve Broker client session ID");
    }

    let impersonation = ImpersonationGuard::begin(handle)?;
    let mut token = null_mut();
    // SAFETY: the output pointer is valid; OpenAsSelf is required for a privileged server.
    if unsafe { OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, 1, &mut token) } == 0 {
        return Err(io::Error::last_os_error()).context("open Broker client token");
    }
    // SAFETY: OpenThreadToken returned a unique, owned handle.
    let token = unsafe { OwnedHandle::from_raw_handle(token) };
    let token = token_identity(raw_handle(&token))?;
    impersonation.revert()?;
    Ok(LocalClientIdentity {
        process_id,
        session_id,
        token,
    })
}

struct TokenIdentity {
    sid: String,
    is_administrator: bool,
    is_local_system: bool,
}

fn token_identity(token: *mut c_void) -> Result<TokenIdentity> {
    let sid = token_user_sid(token)?;
    Ok(TokenIdentity {
        is_administrator: token_has_well_known_sid(token, WinBuiltinAdministratorsSid)?,
        is_local_system: sid == "S-1-5-18",
        sid,
    })
}

fn token_user_sid(token: *mut c_void) -> Result<String> {
    let mut required = 0_u32;
    // SAFETY: the first call intentionally supplies no buffer to obtain the required size.
    unsafe {
        GetTokenInformation(token, TokenUser, null_mut(), 0, &mut required);
    }
    if required < size_of::<TOKEN_USER>() as u32 {
        return Err(io::Error::last_os_error()).context("size Broker client token identity");
    }
    let words = (required as usize).div_ceil(size_of::<usize>());
    let mut buffer = vec![0_usize; words];
    // SAFETY: the aligned buffer has at least required writable bytes.
    if unsafe {
        GetTokenInformation(
            token,
            TokenUser,
            buffer.as_mut_ptr().cast(),
            required,
            &mut required,
        )
    } == 0
    {
        return Err(io::Error::last_os_error()).context("read Broker client token identity");
    }
    // SAFETY: GetTokenInformation initialized a TOKEN_USER at the aligned buffer start.
    let user_sid = unsafe { (*(buffer.as_ptr().cast::<TOKEN_USER>())).User.Sid };
    sid_to_string(user_sid)
}

fn token_has_well_known_sid(token: *mut c_void, sid_type: i32) -> Result<bool> {
    let mut storage = well_known_sid(sid_type)?;
    let sid = storage.as_mut_ptr().cast();
    let mut is_member = 0;
    // SAFETY: token and SID are valid for the duration of the call.
    let result = unsafe { CheckTokenMembership(token, sid, &mut is_member) };
    std::hint::black_box(&mut storage);
    if result == 0 {
        Err(io::Error::last_os_error()).context("check Broker client token membership")
    } else {
        Ok(is_member != 0)
    }
}

fn well_known_sid(sid_type: i32) -> Result<[usize; 9]> {
    let mut storage = [0_usize; 9];
    let mut size = (storage.len() * size_of::<usize>()) as u32;
    let sid = storage.as_mut_ptr().cast();
    // SAFETY: storage is aligned and large enough for SECURITY_MAX_SID_SIZE bytes.
    if unsafe { CreateWellKnownSid(sid_type, null_mut(), sid, &mut size) } == 0 {
        return Err(io::Error::last_os_error()).context("create Windows well-known SID");
    }
    Ok(storage)
}

fn canonical_sid(value: &str) -> Result<String> {
    if value.is_empty() || value.len() > 184 || !value.is_ascii() || !value.starts_with("S-1-") {
        bail!("Broker owner SID is invalid");
    }
    let value = wide_null(value);
    let mut sid = null_mut();
    // SAFETY: value is NUL-terminated and sid is a valid output pointer.
    if unsafe { ConvertStringSidToSidW(value.as_ptr(), &mut sid) } == 0 {
        return Err(io::Error::last_os_error()).context("parse Broker owner SID");
    }
    let owned = LocalAllocation(sid.cast());
    sid_to_string(owned.0)
}

fn sid_to_string(sid: PSID) -> Result<String> {
    let mut output = null_mut();
    // SAFETY: sid is valid and output is a valid pointer for the allocated string.
    if unsafe { ConvertSidToStringSidW(sid, &mut output) } == 0 {
        return Err(io::Error::last_os_error()).context("format Windows SID");
    }
    let output = LocalWideString(output);
    let mut length = 0;
    // SAFETY: ConvertSidToStringSidW returns a NUL-terminated allocation.
    unsafe {
        while *output.0.add(length) != 0 {
            length += 1;
        }
        String::from_utf16(std::slice::from_raw_parts(output.0, length))
            .context("Windows SID is not UTF-16")
    }
}

struct PipeSecurityDescriptor(PSECURITY_DESCRIPTOR);

impl PipeSecurityDescriptor {
    fn new(owner_sid: &str) -> Result<Self> {
        let sddl =
            format!("D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x{CLIENT_PIPE_ACCESS:x};;;{owner_sid})");
        Self::from_sddl(&sddl)
    }

    fn new_activation() -> Result<Self> {
        let sddl = format!("D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x{CLIENT_PIPE_ACCESS:x};;;AU)");
        Self::from_sddl(&sddl)
    }

    fn from_sddl(sddl: &str) -> Result<Self> {
        let sddl = wide_null(sddl);
        let mut descriptor = null_mut();
        // SAFETY: sddl is NUL-terminated and descriptor is a valid output pointer.
        if unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.as_ptr(),
                SDDL_REVISION_1,
                &mut descriptor,
                null_mut(),
            )
        } == 0
        {
            return Err(io::Error::last_os_error())
                .context("create strict Broker pipe security descriptor");
        }
        Ok(Self(descriptor))
    }
}

impl Drop for PipeSecurityDescriptor {
    fn drop(&mut self) {
        // SAFETY: the descriptor was allocated by a LocalAlloc-compatible Windows API.
        unsafe {
            LocalFree(self.0);
        }
    }
}

struct LocalAllocation(*mut c_void);

impl Drop for LocalAllocation {
    fn drop(&mut self) {
        // SAFETY: the pointer was allocated by a LocalAlloc-compatible Windows API.
        unsafe {
            LocalFree(self.0);
        }
    }
}

struct LocalWideString(*mut u16);

impl Drop for LocalWideString {
    fn drop(&mut self) {
        // SAFETY: the pointer was allocated by a LocalAlloc-compatible Windows API.
        unsafe {
            LocalFree(self.0.cast());
        }
    }
}

struct ImpersonationGuard {
    active: bool,
}

impl ImpersonationGuard {
    fn begin(pipe: *mut c_void) -> Result<Self> {
        // SAFETY: pipe is a connected server-side named-pipe handle.
        if unsafe { ImpersonateNamedPipeClient(pipe) } == 0 {
            return Err(io::Error::last_os_error()).context("impersonate Broker pipe client");
        }
        Ok(Self { active: true })
    }

    fn revert(mut self) -> Result<()> {
        // SAFETY: this thread is impersonating the pipe client.
        if unsafe { RevertToSelf() } == 0 {
            return Err(io::Error::last_os_error()).context("revert Broker client impersonation");
        }
        self.active = false;
        Ok(())
    }
}

impl Drop for ImpersonationGuard {
    fn drop(&mut self) {
        if self.active {
            // SAFETY: best-effort restoration during an error path.
            unsafe {
                RevertToSelf();
            }
        }
    }
}

fn validate_pipe_name(value: &str) -> Result<()> {
    let Some(suffix) = value.strip_prefix(PIPE_NAME_PREFIX) else {
        bail!("strict Broker pipe name has an invalid namespace");
    };
    if suffix.is_empty()
        || value.len() > 240
        || !suffix
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        bail!("strict Broker pipe name is invalid");
    }
    Ok(())
}

fn validate_activation_pipe_name(value: &str) -> Result<()> {
    let Some(suffix) = value.strip_prefix(ACTIVATION_PIPE_NAME_PREFIX) else {
        bail!("strict Broker activation pipe name has an invalid namespace");
    };
    if suffix.is_empty()
        || value.len() > 240
        || !suffix
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        bail!("strict Broker activation pipe name is invalid");
    }
    Ok(())
}

fn wide_null(value: impl AsRef<Path>) -> Vec<u16> {
    value
        .as_ref()
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect()
}

fn raw_handle(handle: &OwnedHandle) -> *mut c_void {
    handle.as_raw_handle()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    use flclash_strict_contract::{BrokerActivationErrorCode, BrokerActivationResponseBody};
    use sha2::{Digest, Sha256};

    use super::*;

    fn activation_pipe_name() -> String {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos();
        format!(
            r"\\.\pipe\FlClashX.StrictBroker.Activation.Test.{}.{}",
            std::process::id(),
            nonce
        )
    }

    #[test]
    fn activation_pipe_uses_kernel_client_identity_and_correlated_frames() {
        let pipe_name = activation_pipe_name();
        let deadlines = WindowsPipeDeadlines::new(
            Duration::from_secs(2),
            Duration::from_secs(2),
            Duration::from_secs(2),
        )
        .unwrap();
        let server = WindowsBrokerActivationPipeInstance::create(&pipe_name, deadlines).unwrap();
        let frame = format!(
            r#"{{"protocol":1,"requestId":"activation-test","sessionCapability":"{}"}}"#,
            "11".repeat(32)
        )
        .into_bytes();
        let client_name = pipe_name.clone();
        let client = std::thread::spawn(move || {
            exchange_windows_activation_for_agent(&client_name, &frame, deadlines).unwrap()
        });

        let request = server.connect_and_receive().unwrap();
        assert_eq!(request.request.request_id, "activation-test");
        assert_eq!(request.client_process_id, std::process::id());
        assert_eq!(request.client_sid, current_process_user_sid().unwrap());
        assert!(request.client_session_id > 0);
        assert!(!request.is_local_system);
        let response = BrokerActivationResponse::activated(
            "activation-test",
            r"\\.\pipe\FlClashX.StrictBroker.Session.test",
        )
        .unwrap();
        server.write_response(&response).unwrap();

        assert!(matches!(
            client.join().unwrap().body,
            BrokerActivationResponseBody::Activated { .. }
        ));
    }

    #[test]
    fn activation_identity_rejection_returns_only_the_stable_unauthorized_code() {
        let pipe_name = activation_pipe_name();
        let deadlines = WindowsPipeDeadlines::new(
            Duration::from_secs(2),
            Duration::from_secs(2),
            Duration::from_secs(2),
        )
        .unwrap();
        let server = WindowsBrokerActivationPipeInstance::create(&pipe_name, deadlines).unwrap();
        let frame = format!(
            r#"{{"protocol":1,"requestId":"rejected-activation","sessionCapability":"{}"}}"#,
            "11".repeat(32)
        )
        .into_bytes();
        let client_name = pipe_name.clone();
        let client = std::thread::spawn(move || {
            exchange_windows_activation_for_agent(&client_name, &frame, deadlines).unwrap()
        });
        let unexpected_path = Path::new(r"C:\Windows\System32\cmd.exe");
        let inspected = crate::inspect_windows_executable(unexpected_path).unwrap();
        let file_sha256 = format!("{:x}", Sha256::digest(fs::read(unexpected_path).unwrap()));
        let manifest = StrictPackageManifest::parse(
            format!(
                r#"{{"protocol":1,"packageVersion":"rejection-test","driverBuildId":"{}","driverFileSha256":"{}","driverPublisherCertificateSha256":"{}","agentFileSha256":"{}","agentPublisherCertificateSha256":"{}"}}"#,
                "12".repeat(16),
                "23".repeat(32),
                "34".repeat(32),
                file_sha256,
                inspected.publisher_certificate_sha256,
            )
            .as_bytes(),
        )
        .unwrap();
        let image = crate::verify_windows_packaged_agent_image(unexpected_path, &manifest).unwrap();

        let response = match server.connect_and_classify_with_image(&image).unwrap() {
            WindowsBrokerActivationAttempt::Verified(_) => panic!("identity must be rejected"),
            WindowsBrokerActivationAttempt::Rejected(response) => response,
        };
        server.write_response(&response).unwrap();

        assert!(matches!(
            client.join().unwrap().body,
            BrokerActivationResponseBody::Error {
                code: BrokerActivationErrorCode::Unauthorized
            }
        ));
    }

    #[test]
    fn session_pipe_names_use_fresh_system_randomness() {
        let first = generate_windows_broker_session_pipe_name().unwrap();
        let second = generate_windows_broker_session_pipe_name().unwrap();
        validate_pipe_name(&first).unwrap();
        validate_pipe_name(&second).unwrap();
        assert_ne!(first, second);
        assert!(first.starts_with(r"\\.\pipe\FlClashX.StrictBroker.Session."));
    }
}
