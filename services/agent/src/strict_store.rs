use std::fs::File;
use std::io::{Read, Write};
use std::mem::size_of;
use std::os::windows::{ffi::OsStrExt, io::{AsRawHandle, FromRawHandle, OwnedHandle}};
use std::path::{Path, PathBuf};
use std::ptr::{null, null_mut};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::StrictPolicyBundle;
use serde::{Deserialize, Serialize};
use windows_sys::Win32::Foundation::{LocalFree, ERROR_ALREADY_EXISTS, ERROR_FILE_NOT_FOUND, INVALID_HANDLE_VALUE};
use windows_sys::Win32::Security::Authorization::{ConvertSecurityDescriptorToStringSecurityDescriptorW, ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW, GetSecurityInfo, SE_FILE_OBJECT};
use windows_sys::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER, SECURITY_ATTRIBUTES, OWNER_SECURITY_INFORMATION, DACL_SECURITY_INFORMATION};
use windows_sys::Win32::Storage::FileSystem::{CreateDirectoryW, CreateFileW, GetFileInformationByHandle, MoveFileExW, BY_HANDLE_FILE_INFORMATION, CREATE_NEW, FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT, FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING, READ_CONTROL, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH};
use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

const MAX_INTENT_BYTES: u64 = 2 * 1024 * 1024;

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StoredStrictIntent {
    pub version: u32,
    pub enabled: bool,
    pub policy: StrictPolicyBundle,
}

struct PendingPath(PathBuf);
impl Drop for PendingPath {
    fn drop(&mut self) { let _ = std::fs::remove_file(&self.0); }
}

struct Descriptor(*mut std::ffi::c_void);
impl Drop for Descriptor {
    fn drop(&mut self) { unsafe { LocalFree(self.0); } }
}

/// Holds ancestor directories open without DELETE sharing, and uses explicit
/// current-user + SYSTEM protected DACLs. No credentials are serialized.
pub struct StrictIntentStore {
    directory: PathBuf,
    user_sid: String,
    _directories: Vec<OwnedHandle>,
}

impl StrictIntentStore {
    pub fn open(home: &Path) -> Result<Self> {
        let user_sid = current_user_sid()?;
        let mut directories = Vec::new();
        for ancestor in home.ancestors().collect::<Vec<_>>().into_iter().rev() {
            if ancestor.as_os_str().is_empty() { continue; }
            let handle = open_handle(ancestor, READ_CONTROL, FILE_SHARE_READ | FILE_SHARE_WRITE, OPEN_EXISTING, null())?;
            check_kind(&handle, true)?;
            directories.push(handle);
        }
        let directory = home.join("strict-intent");
        let descriptor = descriptor(&user_sid, true)?;
        let security = attributes(&descriptor);
        if unsafe { CreateDirectoryW(wide(&directory).as_ptr(), &security) } == 0
            && std::io::Error::last_os_error().raw_os_error() != Some(ERROR_ALREADY_EXISTS as i32) {
            return Err(std::io::Error::last_os_error()).context("create protected strict intent directory");
        }
        let handle = open_handle(&directory, READ_CONTROL, FILE_SHARE_READ | FILE_SHARE_WRITE, OPEN_EXISTING, null())?;
        check_kind(&handle, true)?;
        check_security(&handle, &descriptor)?;
        directories.push(handle);
        Ok(Self { directory, user_sid, _directories: directories })
    }

    pub fn load(&self) -> Result<Option<StoredStrictIntent>> {
        let path = self.directory.join("desired.json");
        let handle = match open_handle(&path, READ_CONTROL | 0x80000000, FILE_SHARE_READ, OPEN_EXISTING, null()) {
            Ok(handle) => handle,
            Err(error) if error.downcast_ref::<std::io::Error>().and_then(|e| e.raw_os_error()) == Some(ERROR_FILE_NOT_FOUND as i32) => return Ok(None),
            Err(error) => return Err(error),
        };
        check_kind(&handle, false)?;
        check_security(&handle, &descriptor(&self.user_sid, false)?)?;
        let file = File::from(handle);
        if file.metadata()?.len() > MAX_INTENT_BYTES { bail!("strict intent file exceeds size limit"); }
        let mut bytes = Vec::new();
        file.take(MAX_INTENT_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > MAX_INTENT_BYTES { bail!("strict intent file exceeds size limit"); }
        let intent: StoredStrictIntent = serde_json::from_slice(&bytes)?;
        if intent.version != 1 { bail!("unsupported strict intent version"); }
        intent.policy.validate()?;
        Ok(Some(intent))
    }

    pub fn save(&self, enabled: bool, policy: &StrictPolicyBundle) -> Result<()> {
        policy.validate()?;
        let bytes = serde_json::to_vec(&StoredStrictIntent { version: 1, enabled, policy: policy.clone() })?;
        if bytes.len() as u64 > MAX_INTENT_BYTES { bail!("strict intent exceeds size limit"); }
        let pending = self.directory.join(format!("pending-{}.json", crate::endpoint::random_token()));
        let descriptor = descriptor(&self.user_sid, false)?;
        let security = attributes(&descriptor);
        let handle = open_handle(&pending, READ_CONTROL | 0x40000000, 0, CREATE_NEW, &security)?;
        let _pending_cleanup = PendingPath(pending.clone());
        check_kind(&handle, false)?;
        check_security(&handle, &descriptor)?;
        let mut file = File::from(handle);
        file.write_all(&bytes)?;
        file.sync_all()?;
        drop(file);
        // The directory is private and pinned; same-volume replacement is
        // atomic. WRITE_THROUGH requests durable completion before acknowledgement.
        let target = self.directory.join("desired.json");
        if unsafe { MoveFileExW(wide(&pending).as_ptr(), wide(&target).as_ptr(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) } == 0 {
            let error = std::io::Error::last_os_error();
            let _ = std::fs::remove_file(&pending);
            return Err(error).context("commit durable strict intent");
        }
        Ok(())
    }
}

fn wide(path: &Path) -> Vec<u16> { path.as_os_str().encode_wide().chain(Some(0)).collect() }
fn attributes(descriptor: &Descriptor) -> SECURITY_ATTRIBUTES {
    SECURITY_ATTRIBUTES { nLength: size_of::<SECURITY_ATTRIBUTES>() as u32, lpSecurityDescriptor: descriptor.0, bInheritHandle: 0 }
}
fn descriptor(sid: &str, directory: bool) -> Result<Descriptor> {
    let flags = if directory { "OICI" } else { "" };
    let text = format!("O:{sid}D:P(A;{flags};FA;;;SY)(A;{flags};FA;;;{sid})");
    let text: Vec<u16> = text.encode_utf16().chain(Some(0)).collect();
    let mut raw = null_mut();
    if unsafe { ConvertStringSecurityDescriptorToSecurityDescriptorW(text.as_ptr(), 1, &mut raw, null_mut()) } == 0 {
        return Err(std::io::Error::last_os_error()).context("create strict intent DACL");
    }
    Ok(Descriptor(raw))
}
fn open_handle(path: &Path, access: u32, share: u32, creation: u32, security: *const SECURITY_ATTRIBUTES) -> Result<OwnedHandle> {
    let raw = unsafe { CreateFileW(wide(path).as_ptr(), access, share, security, creation, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, null_mut()) };
    if raw == INVALID_HANDLE_VALUE { return Err(std::io::Error::last_os_error().into()); }
    Ok(unsafe { OwnedHandle::from_raw_handle(raw) })
}
fn check_kind(handle: &OwnedHandle, directory: bool) -> Result<()> {
    let mut information = BY_HANDLE_FILE_INFORMATION::default();
    if unsafe { GetFileInformationByHandle(handle.as_raw_handle(), &mut information) } == 0 { return Err(std::io::Error::last_os_error().into()); }
    if information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0 || (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY != 0) != directory || (!directory && information.nNumberOfLinks != 1) {
        bail!("strict intent object type, reparse point or hardlink rejected");
    }
    Ok(())
}
fn security_text(descriptor: &Descriptor) -> Result<String> {
    let mut raw = null_mut();
    if unsafe { ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor.0, 1, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &mut raw, null_mut()) } == 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    let owned = Descriptor(raw.cast());
    let mut length = 0;
    while unsafe { *raw.add(length) } != 0 { length += 1; if length > 8192 { bail!("oversized strict ACL"); } }
    let text = String::from_utf16(unsafe { std::slice::from_raw_parts(raw, length) })?;
    drop(owned);
    Ok(text)
}
fn check_security(handle: &OwnedHandle, expected: &Descriptor) -> Result<()> {
    let mut raw = null_mut();
    let status = unsafe { GetSecurityInfo(handle.as_raw_handle(), SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, null_mut(), null_mut(), null_mut(), null_mut(), &mut raw) };
    if status != 0 { return Err(std::io::Error::from_raw_os_error(status as i32).into()); }
    let actual = Descriptor(raw);
    if security_text(&actual)? != security_text(expected)? { bail!("strict intent owner or protected DACL does not match current user"); }
    Ok(())
}
fn current_user_sid() -> Result<String> {
    let mut token = null_mut();
    if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) } == 0 { return Err(std::io::Error::last_os_error().into()); }
    let token = unsafe { OwnedHandle::from_raw_handle(token) };
    let mut length = 0;
    unsafe { GetTokenInformation(token.as_raw_handle(), TokenUser, null_mut(), 0, &mut length); }
    if length == 0 || length > 65536 { bail!("invalid user token length"); }
    let mut buffer = vec![0usize; (length as usize + size_of::<usize>() - 1) / size_of::<usize>()];
    if unsafe { GetTokenInformation(token.as_raw_handle(), TokenUser, buffer.as_mut_ptr().cast(), length, &mut length) } == 0 { return Err(std::io::Error::last_os_error().into()); }
    let user = unsafe { &*buffer.as_ptr().cast::<TOKEN_USER>() };
    let mut raw = null_mut();
    if unsafe { ConvertSidToStringSidW(user.User.Sid, &mut raw) } == 0 { return Err(std::io::Error::last_os_error().into()); }
    let owned = Descriptor(raw.cast());
    let mut size = 0;
    while unsafe { *raw.add(size) } != 0 { size += 1; if size > 256 { bail!("invalid user SID length"); } }
    let sid = String::from_utf16(unsafe { std::slice::from_raw_parts(raw, size) })?;
    drop(owned);
    Ok(sid)
}
