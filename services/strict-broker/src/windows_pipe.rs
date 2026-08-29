use std::ffi::c_void;
use std::io;
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::Path;
use std::ptr::{null, null_mut};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::MAX_BROKER_FRAME_BYTES;
use windows_sys::Win32::Foundation::{
    LocalFree, ERROR_MORE_DATA, ERROR_PIPE_CONNECTED, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Security::Authorization::{
    ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
    ConvertStringSidToSidW, SDDL_REVISION_1,
};
use windows_sys::Win32::Security::{
    CheckTokenMembership, CreateWellKnownSid, GetTokenInformation, RevertToSelf, TokenUser,
    WinBuiltinAdministratorsSid, PSECURITY_DESCRIPTOR, PSID, SECURITY_ATTRIBUTES, TOKEN_QUERY,
    TOKEN_USER,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, ReadFile, WriteFile, FILE_FLAG_FIRST_PIPE_INSTANCE, FILE_READ_ATTRIBUTES,
    FILE_READ_DATA, FILE_READ_EA, FILE_WRITE_ATTRIBUTES, FILE_WRITE_DATA, FILE_WRITE_EA,
    OPEN_EXISTING, PIPE_ACCESS_DUPLEX, READ_CONTROL, SECURITY_IDENTIFICATION,
    SECURITY_SQOS_PRESENT, SYNCHRONIZE,
};
use windows_sys::Win32::System::Pipes::{
    ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, GetNamedPipeClientProcessId,
    ImpersonateNamedPipeClient, PIPE_READMODE_MESSAGE, PIPE_REJECT_REMOTE_CLIENTS,
    PIPE_TYPE_MESSAGE,
};
use windows_sys::Win32::System::Threading::{
    GetCurrentProcess, GetCurrentThread, OpenProcessToken, OpenThreadToken,
};

use crate::{AuthorizedBrokerRequest, BrokerAuthenticator, ClientPrincipal, ClientRole};

const PIPE_NAME_PREFIX: &str = r"\\.\pipe\FlClashX.StrictBroker.";
const PIPE_BUFFER_BYTES: u32 = 64 * 1024;
const CLIENT_PIPE_ACCESS: u32 = FILE_READ_DATA
    | FILE_READ_ATTRIBUTES
    | FILE_READ_EA
    | FILE_WRITE_DATA
    | FILE_WRITE_ATTRIBUTES
    | FILE_WRITE_EA
    | READ_CONTROL
    | SYNCHRONIZE;

pub struct WindowsAuthenticatedRequest {
    pub authorized: AuthorizedBrokerRequest,
    pub client_process_id: u32,
    pub client_sid: String,
}

pub struct WindowsNamedPipeInstance {
    handle: OwnedHandle,
    owner_sid: String,
}

impl WindowsNamedPipeInstance {
    pub fn create(pipe_name: &str, owner_sid: &str) -> Result<Self> {
        validate_pipe_name(pipe_name)?;
        let owner_sid = canonical_sid(owner_sid)?;
        let security_descriptor = PipeSecurityDescriptor::new(&owner_sid)?;
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
                PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
                PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_REJECT_REMOTE_CLIENTS,
                1,
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
        Ok(Self { handle, owner_sid })
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

    fn connect(&self) -> Result<()> {
        // SAFETY: the handle is a live server-side named-pipe instance.
        if unsafe { ConnectNamedPipe(raw_handle(&self.handle), null_mut()) } != 0 {
            return Ok(());
        }
        let error = io::Error::last_os_error();
        if error.raw_os_error() == Some(ERROR_PIPE_CONNECTED as i32) {
            Ok(())
        } else {
            Err(error).context("connect strict Broker named-pipe client")
        }
    }

    fn read_message(&self) -> Result<Vec<u8>> {
        let mut message = Vec::with_capacity(PIPE_BUFFER_BYTES as usize);
        loop {
            let remaining = MAX_BROKER_FRAME_BYTES
                .checked_add(1)
                .and_then(|limit| limit.checked_sub(message.len()))
                .ok_or_else(|| anyhow::anyhow!("Broker frame exceeds its size limit"))?;
            let chunk_size = remaining.min(PIPE_BUFFER_BYTES as usize);
            let start = message.len();
            message.resize(start + chunk_size, 0);
            let mut bytes_read = 0_u32;
            // SAFETY: the writable slice is valid for chunk_size bytes and I/O is synchronous.
            let result = unsafe {
                ReadFile(
                    raw_handle(&self.handle),
                    message[start..].as_mut_ptr(),
                    chunk_size as u32,
                    &mut bytes_read,
                    null_mut(),
                )
            };
            message.truncate(start + bytes_read as usize);
            if message.len() > MAX_BROKER_FRAME_BYTES {
                bail!("Broker frame exceeds its size limit");
            }
            if result != 0 {
                if message.is_empty() {
                    bail!("Broker frame is empty");
                }
                return Ok(message);
            }
            let error = io::Error::last_os_error();
            if error.raw_os_error() != Some(ERROR_MORE_DATA as i32) {
                return Err(error).context("read strict Broker named-pipe request");
            }
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

pub fn connect_windows_pipe_for_agent(pipe_name: &str, frame: &[u8]) -> Result<()> {
    validate_pipe_name(pipe_name)?;
    if frame.is_empty() || frame.len() > MAX_BROKER_FRAME_BYTES {
        bail!("Broker frame size is invalid");
    }
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
            SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
            null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error()).context("connect to strict Broker named pipe");
    }
    // SAFETY: CreateFileW returned a unique, owned handle.
    let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
    let mut bytes_written = 0_u32;
    // SAFETY: frame is readable for its declared length and I/O is synchronous.
    let result = unsafe {
        WriteFile(
            raw_handle(&handle),
            frame.as_ptr(),
            frame.len() as u32,
            &mut bytes_written,
            null_mut(),
        )
    };
    if result == 0 {
        return Err(io::Error::last_os_error()).context("write strict Broker named-pipe request");
    }
    if bytes_written as usize != frame.len() {
        bail!("strict Broker named-pipe request was partially written");
    }
    Ok(())
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
    let mut process_id = 0_u32;
    // SAFETY: handle is a connected server-side named-pipe instance.
    if unsafe { GetNamedPipeClientProcessId(handle, &mut process_id) } == 0 || process_id == 0 {
        return Err(io::Error::last_os_error()).context("resolve Broker client process ID");
    }

    let impersonation = ImpersonationGuard::begin(handle)?;
    let mut token = null_mut();
    // SAFETY: the output pointer is valid; OpenAsSelf is required for a privileged server.
    if unsafe { OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, 1, &mut token) } == 0 {
        return Err(io::Error::last_os_error()).context("open Broker client token");
    }
    // SAFETY: OpenThreadToken returned a unique, owned handle.
    let token = unsafe { OwnedHandle::from_raw_handle(token) };
    let identity = token_identity(raw_handle(&token))?;
    impersonation.revert()?;

    let role = if identity.sid == owner_sid {
        ClientRole::Owner
    } else if identity.is_administrator || identity.is_local_system {
        ClientRole::RecoveryAdministrator
    } else {
        bail!("Broker client token is not an authorized owner or recovery administrator");
    };
    Ok(ResolvedClientIdentity {
        principal: ClientPrincipal::new(true, role),
        process_id,
        sid: identity.sid,
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
        let sddl = wide_null(&sddl);
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
