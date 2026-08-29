use std::ffi::c_void;
use std::fmt::Write;
use std::fs::File;
use std::io;
use std::io::{Read, Seek, SeekFrom};
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::Path;
use std::ptr::{null, null_mut};
use std::sync::Arc;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{StrictIdentity, StrictPolicyBundle};
use sha2::{Digest, Sha256};
use windows_sys::Win32::Foundation::{
    INVALID_HANDLE_VALUE, TRUST_E_NOSIGNATURE, WAIT_FAILED, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows_sys::Win32::NetworkManagement::WindowsFilteringPlatform::{
    FwpmFreeMemory0, FwpmGetAppIdFromFileName0, FWP_BYTE_BLOB,
};
use windows_sys::Win32::Security::Cryptography::Catalog::{
    CryptCATAdminAcquireContext2, CryptCATAdminCalcHashFromFileHandle2,
    CryptCATAdminEnumCatalogFromHash, CryptCATAdminReleaseCatalogContext,
    CryptCATAdminReleaseContext, CryptCATCatalogInfoFromContext, CATALOG_INFO,
};
use windows_sys::Win32::Security::Cryptography::BCRYPT_SHA256_ALGORITHM;
use windows_sys::Win32::Security::WinTrust::{
    WTHelperGetProvSignerFromChain, WTHelperProvDataFromStateData, WinVerifyTrust,
    WINTRUST_ACTION_GENERIC_VERIFY_V2, WINTRUST_CATALOG_INFO, WINTRUST_DATA, WINTRUST_FILE_INFO,
    WTD_CACHE_ONLY_URL_RETRIEVAL, WTD_CHOICE_CATALOG, WTD_CHOICE_FILE,
    WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT, WTD_REVOKE_WHOLECHAIN, WTD_STATEACTION_CLOSE,
    WTD_STATEACTION_VERIFY, WTD_UICONTEXT_EXECUTE, WTD_UI_NONE,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, GetFileInformationByHandle, GetFinalPathNameByHandleW, BY_HANDLE_FILE_INFORMATION,
    FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT, FILE_FLAG_OPEN_REPARSE_POINT,
    FILE_READ_ATTRIBUTES, FILE_READ_DATA, FILE_SHARE_READ, OPEN_EXISTING, READ_CONTROL,
    SYNCHRONIZE,
};
use windows_sys::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, WaitForSingleObject, PROCESS_QUERY_LIMITED_INFORMATION,
};

use crate::{
    IdentityVerification, IdentityVerifier, StrictPackageManifest, VerifiedApplicationAppIds,
    VerifiedPolicyAppIds,
};

const MAX_WFP_APP_ID_BYTES: u32 = 64 * 1024;
const MAX_CATALOG_HASH_BYTES: u32 = 128;
const MAX_MATCHING_CATALOGS: usize = 32;
const MAX_DRIVER_FILE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_AGENT_FILE_BYTES: u64 = 256 * 1024 * 1024;
const MAX_CORE_FILE_BYTES: u64 = 256 * 1024 * 1024;
const MAX_PROCESS_IMAGE_PATH_UNITS: usize = 32_768;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowsVerifiedIdentity {
    pub canonical_path: String,
    pub wfp_app_id_sha256: String,
    pub publisher_certificate_sha256: String,
}

#[derive(Default)]
pub struct WindowsIdentityVerifier;

pub struct WindowsIdentityLease {
    handles: Vec<OwnedHandle>,
}

pub struct WindowsDriverTrustLease {
    canonical_path: String,
    file_sha256: String,
    publisher_certificate_sha256: String,
    _file: File,
}

struct WindowsPackagedImageTrustLease {
    canonical_path: String,
    file_sha256: String,
    publisher_certificate_sha256: String,
    file: Arc<File>,
}

pub struct WindowsAgentImageTrustLease {
    inner: WindowsPackagedImageTrustLease,
}

pub struct WindowsCoreImageTrustLease {
    inner: WindowsPackagedImageTrustLease,
}

struct WindowsPackagedProcessTrustLease {
    process_id: u32,
    canonical_path: String,
    _process: OwnedHandle,
    _file: Arc<File>,
}

pub struct WindowsAgentProcessTrustLease {
    inner: WindowsPackagedProcessTrustLease,
}

pub struct WindowsCoreProcessTrustLease {
    inner: WindowsPackagedProcessTrustLease,
}

impl WindowsDriverTrustLease {
    pub fn canonical_path(&self) -> &str {
        &self.canonical_path
    }

    pub fn publisher_certificate_sha256(&self) -> &str {
        &self.publisher_certificate_sha256
    }

    pub fn file_sha256(&self) -> &str {
        &self.file_sha256
    }
}

impl WindowsAgentProcessTrustLease {
    pub fn process_id(&self) -> u32 {
        self.inner.process_id
    }

    pub fn canonical_path(&self) -> &str {
        &self.inner.canonical_path
    }

    pub fn is_running(&self) -> Result<bool> {
        self.inner.is_running("Agent")
    }
}

impl WindowsCoreProcessTrustLease {
    pub fn process_id(&self) -> u32 {
        self.inner.process_id
    }

    pub fn canonical_path(&self) -> &str {
        &self.inner.canonical_path
    }

    pub fn is_running(&self) -> Result<bool> {
        self.inner.is_running("Core")
    }
}

impl WindowsPackagedProcessTrustLease {
    fn is_running(&self, label: &str) -> Result<bool> {
        // SAFETY: the process handle is live and has SYNCHRONIZE access.
        match unsafe { WaitForSingleObject(self._process.as_raw_handle(), 0) } {
            WAIT_TIMEOUT => Ok(true),
            WAIT_OBJECT_0 => Ok(false),
            WAIT_FAILED => Err(io::Error::last_os_error())
                .with_context(|| format!("query trusted {label} process")),
            status => bail!("query trusted {label} process returned status 0x{status:08x}"),
        }
    }
}

impl WindowsAgentImageTrustLease {
    pub fn canonical_path(&self) -> &str {
        &self.inner.canonical_path
    }

    pub fn publisher_certificate_sha256(&self) -> &str {
        &self.inner.publisher_certificate_sha256
    }

    pub fn file_sha256(&self) -> &str {
        &self.inner.file_sha256
    }
}

impl WindowsCoreImageTrustLease {
    pub fn canonical_path(&self) -> &str {
        &self.inner.canonical_path
    }

    pub fn publisher_certificate_sha256(&self) -> &str {
        &self.inner.publisher_certificate_sha256
    }

    pub fn file_sha256(&self) -> &str {
        &self.inner.file_sha256
    }
}

impl WindowsIdentityLease {
    pub fn executable_count(&self) -> usize {
        self.handles.len()
    }
}

impl IdentityVerifier for WindowsIdentityVerifier {
    type VerificationLease = WindowsIdentityLease;

    fn verify(
        &mut self,
        policy: &StrictPolicyBundle,
    ) -> Result<IdentityVerification<Self::VerificationLease>> {
        policy.validate()?;
        let expected_count = policy.entries.iter().try_fold(0_usize, |count, entry| {
            count
                .checked_add(1 + entry.identity.verified_children.len())
                .ok_or_else(|| anyhow::anyhow!("strict identity count overflow"))
        })?;
        let mut handles = Vec::with_capacity(expected_count);
        let mut verified_applications = Vec::with_capacity(policy.entries.len());
        for entry in &policy.entries {
            let (handle, primary_app_id) = verify_and_lock_primary(&entry.identity)?;
            handles.push(handle);
            let mut family_app_ids = Vec::with_capacity(1 + entry.identity.verified_children.len());
            family_app_ids.push(primary_app_id);
            for child in &entry.identity.verified_children {
                let (actual, app_id, handle) = inspect_and_lock(Path::new(&child.canonical_path))?;
                verify_pinned_values(
                    &child.canonical_path,
                    &child.wfp_app_id_sha256,
                    &child.publisher_certificate_sha256,
                    &actual,
                )?;
                family_app_ids.push(app_id);
                handles.push(handle);
            }
            verified_applications.push(VerifiedApplicationAppIds::new(
                &entry.identity.identity_id,
                family_app_ids,
            )?);
        }
        let app_ids = VerifiedPolicyAppIds::new(policy, verified_applications)?;
        Ok(IdentityVerification::new(
            app_ids,
            WindowsIdentityLease { handles },
        ))
    }
}

pub fn inspect_windows_executable(path: impl AsRef<Path>) -> Result<WindowsVerifiedIdentity> {
    inspect_and_lock(path.as_ref()).map(|(identity, _app_id, _handle)| identity)
}

pub fn inspect_windows_driver(path: impl AsRef<Path>) -> Result<WindowsDriverTrustLease> {
    let (canonical_path, handle) = open_and_lock_plain_file(path.as_ref(), "strict driver")?;
    if canonical_path.len() > 1024
        || !canonical_path.to_ascii_lowercase().ends_with(".sys")
        || canonical_path.contains(['\0', '\r', '\n', '/'])
    {
        bail!("strict driver canonical path is invalid");
    }
    let mut file = File::from(handle);
    let file_sha256 = hash_locked_file(&mut file, "strict driver", MAX_DRIVER_FILE_BYTES)?;
    let publisher_certificate_sha256 =
        authenticode_publisher_digest(file.as_raw_handle(), &canonical_path)
            .context("verify strict driver Authenticode signer")?;
    Ok(WindowsDriverTrustLease {
        canonical_path,
        file_sha256,
        publisher_certificate_sha256,
        _file: file,
    })
}

pub fn verify_windows_driver(
    path: impl AsRef<Path>,
    expected_publisher_certificate_sha256: &str,
) -> Result<WindowsDriverTrustLease> {
    if expected_publisher_certificate_sha256.len() != 64
        || !expected_publisher_certificate_sha256
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit())
    {
        bail!("strict driver publisher certificate digest is invalid");
    }
    let lease = inspect_windows_driver(path)?;
    if !lease
        .publisher_certificate_sha256
        .eq_ignore_ascii_case(expected_publisher_certificate_sha256)
    {
        bail!("strict driver publisher certificate changed");
    }
    Ok(lease)
}

pub fn verify_windows_packaged_driver(
    path: impl AsRef<Path>,
    expected_file_sha256: &str,
    expected_publisher_certificate_sha256: &str,
) -> Result<WindowsDriverTrustLease> {
    validate_sha256(expected_file_sha256, "strict driver file digest")?;
    let lease = verify_windows_driver(path, expected_publisher_certificate_sha256)?;
    if !lease.file_sha256.eq_ignore_ascii_case(expected_file_sha256) {
        bail!("strict driver file digest changed");
    }
    Ok(lease)
}

pub fn verify_windows_packaged_agent_process(
    process_id: u32,
    expected_agent_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsAgentProcessTrustLease> {
    let image = verify_windows_packaged_agent_image(expected_agent_path, package)?;
    verify_windows_packaged_agent_process_with_image(process_id, &image)
}

pub fn verify_windows_packaged_agent_image(
    expected_agent_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsAgentImageTrustLease> {
    Ok(WindowsAgentImageTrustLease {
        inner: verify_windows_packaged_image(
            expected_agent_path.as_ref(),
            package.agent_file_sha256(),
            package.agent_publisher_certificate_sha256(),
            "Agent",
            MAX_AGENT_FILE_BYTES,
        )?,
    })
}

pub fn verify_windows_packaged_core_process(
    process_id: u32,
    expected_core_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsCoreProcessTrustLease> {
    let image = verify_windows_packaged_core_image(expected_core_path, package)?;
    verify_windows_packaged_core_process_with_image(process_id, &image)
}

pub fn verify_windows_packaged_core_image(
    expected_core_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsCoreImageTrustLease> {
    Ok(WindowsCoreImageTrustLease {
        inner: verify_windows_packaged_image(
            expected_core_path.as_ref(),
            package.core_file_sha256(),
            package.core_publisher_certificate_sha256(),
            "Core",
            MAX_CORE_FILE_BYTES,
        )?,
    })
}

fn verify_windows_packaged_image(
    expected_path: &Path,
    expected_file_sha256: &str,
    expected_publisher_certificate_sha256: &str,
    label: &str,
    maximum_bytes: u64,
) -> Result<WindowsPackagedImageTrustLease> {
    let package_label = format!("strict packaged {label}");
    let (canonical_path, handle) = open_and_lock_plain_file(expected_path, &package_label)?;
    if canonical_path.len() > 1024
        || !canonical_path.to_ascii_lowercase().ends_with(".exe")
        || canonical_path.contains(['\0', '\r', '\n', '/'])
    {
        bail!("strict {label} package path is invalid");
    }
    let mut file = File::from(handle);
    let strict_label = format!("strict {label}");
    let file_sha256 = hash_locked_file(&mut file, &strict_label, maximum_bytes)?;
    validate_sha256(expected_file_sha256, &format!("strict {label} file digest"))?;
    if !file_sha256.eq_ignore_ascii_case(expected_file_sha256) {
        bail!("strict {label} file digest does not match the package");
    }
    validate_sha256(
        expected_publisher_certificate_sha256,
        &format!("strict {label} publisher certificate digest"),
    )?;
    let publisher_certificate_sha256 =
        authenticode_publisher_digest(file.as_raw_handle(), &canonical_path)
            .with_context(|| format!("verify strict {label} Authenticode signer"))?;
    if !publisher_certificate_sha256.eq_ignore_ascii_case(expected_publisher_certificate_sha256) {
        bail!("strict {label} publisher does not match the package");
    }
    Ok(WindowsPackagedImageTrustLease {
        canonical_path,
        file_sha256,
        publisher_certificate_sha256,
        file: Arc::new(file),
    })
}

pub fn verify_windows_packaged_agent_process_with_image(
    process_id: u32,
    image: &WindowsAgentImageTrustLease,
) -> Result<WindowsAgentProcessTrustLease> {
    Ok(WindowsAgentProcessTrustLease {
        inner: verify_windows_packaged_process(process_id, &image.inner, "Agent")?,
    })
}

pub fn verify_windows_packaged_core_process_with_image(
    process_id: u32,
    image: &WindowsCoreImageTrustLease,
) -> Result<WindowsCoreProcessTrustLease> {
    Ok(WindowsCoreProcessTrustLease {
        inner: verify_windows_packaged_process(process_id, &image.inner, "Core")?,
    })
}

fn verify_windows_packaged_process(
    process_id: u32,
    image: &WindowsPackagedImageTrustLease,
    label: &str,
) -> Result<WindowsPackagedProcessTrustLease> {
    if process_id == 0 {
        bail!("strict {label} process ID is invalid");
    }
    // SAFETY: the PID is supplied by a Windows kernel identity API, not by a request frame.
    let process = unsafe {
        OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
            0,
            process_id,
        )
    };
    if process.is_null() {
        return Err(io::Error::last_os_error())
            .with_context(|| format!("open strict {label} process"));
    }
    // SAFETY: OpenProcess returned a unique owned process handle.
    let process = unsafe { OwnedHandle::from_raw_handle(process) };
    let process_path = process_image_path(process.as_raw_handle(), label)?;
    if !image.canonical_path.eq_ignore_ascii_case(&process_path) {
        bail!("strict {label} process image does not match the protected package path");
    }
    let lease = WindowsPackagedProcessTrustLease {
        process_id,
        canonical_path: image.canonical_path.clone(),
        _process: process,
        _file: Arc::clone(&image.file),
    };
    if !lease.is_running(label)? {
        bail!("strict {label} process exited during verification");
    }
    Ok(lease)
}

fn process_image_path(process: *mut c_void, label: &str) -> Result<String> {
    let mut buffer = vec![0_u16; MAX_PROCESS_IMAGE_PATH_UNITS];
    let mut length = u32::try_from(buffer.len()).expect("bounded process image path size");
    // SAFETY: the process handle is live and buffer/length are valid outputs.
    if unsafe { QueryFullProcessImageNameW(process, 0, buffer.as_mut_ptr(), &mut length) } == 0 {
        return Err(io::Error::last_os_error())
            .with_context(|| format!("query strict {label} process image path"));
    }
    let length = usize::try_from(length)
        .with_context(|| format!("strict {label} process path length overflow"))?;
    if length == 0 || length >= buffer.len() {
        bail!("strict {label} process image path length is invalid");
    }
    let path = String::from_utf16(&buffer[..length])
        .with_context(|| format!("strict {label} process image path is not UTF-16"))?;
    if !Path::new(&path).is_absolute() || path.contains(['\0', '\r', '\n', '/']) {
        bail!("strict {label} process image path is invalid");
    }
    Ok(path)
}

fn hash_locked_file(file: &mut File, label: &str, maximum_bytes: u64) -> Result<String> {
    let length = file
        .metadata()
        .with_context(|| format!("inspect {label} file size"))?
        .len();
    if length == 0 || length > maximum_bytes {
        bail!("{label} file size is invalid");
    }
    file.seek(SeekFrom::Start(0))
        .with_context(|| format!("rewind {label} file before hashing"))?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    let mut total = 0_u64;
    loop {
        let read = file
            .read(&mut buffer)
            .with_context(|| format!("hash {label} file"))?;
        if read == 0 {
            break;
        }
        total = total
            .checked_add(read as u64)
            .ok_or_else(|| anyhow::anyhow!("{label} file size overflow"))?;
        digest.update(&buffer[..read]);
    }
    if total != length {
        bail!("{label} file changed while hashing");
    }
    file.seek(SeekFrom::Start(0))
        .with_context(|| format!("rewind {label} file after hashing"))?;
    Ok(format!("{:x}", digest.finalize()))
}

fn validate_sha256(value: &str, label: &str) -> Result<()> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("{label} is invalid");
    }
    Ok(())
}

fn verify_and_lock_primary(identity: &StrictIdentity) -> Result<(OwnedHandle, Vec<u8>)> {
    let (actual, app_id, handle) = inspect_and_lock(Path::new(&identity.canonical_path))?;
    verify_pinned_values(
        &identity.canonical_path,
        &identity.wfp_app_id_sha256,
        &identity.publisher_certificate_sha256,
        &actual,
    )?;
    Ok((handle, app_id))
}

fn verify_pinned_values(
    expected_path: &str,
    expected_app_id: &str,
    expected_publisher: &str,
    actual: &WindowsVerifiedIdentity,
) -> Result<()> {
    if actual.canonical_path != expected_path {
        bail!("strict executable canonical path changed");
    }
    if !actual
        .wfp_app_id_sha256
        .eq_ignore_ascii_case(expected_app_id)
    {
        bail!("strict executable WFP application identity changed");
    }
    if !actual
        .publisher_certificate_sha256
        .eq_ignore_ascii_case(expected_publisher)
    {
        bail!("strict executable publisher certificate changed");
    }
    Ok(())
}

fn inspect_and_lock(path: &Path) -> Result<(WindowsVerifiedIdentity, Vec<u8>, OwnedHandle)> {
    let (canonical_path, handle) = open_and_lock_plain_file(path, "strict executable identity")?;
    if canonical_path.len() > 1024
        || !canonical_path.to_ascii_lowercase().ends_with(".exe")
        || canonical_path.contains(['\0', '\r', '\n', '/'])
    {
        bail!("strict executable canonical path is invalid");
    }
    let (wfp_app_id_sha256, wfp_app_id) = wfp_app_id(&canonical_path)?;
    let publisher_certificate_sha256 =
        authenticode_publisher_digest(handle.as_raw_handle(), &canonical_path)?;
    Ok((
        WindowsVerifiedIdentity {
            canonical_path,
            wfp_app_id_sha256,
            publisher_certificate_sha256,
        },
        wfp_app_id,
        handle,
    ))
}

fn open_and_lock_plain_file(path: &Path, label: &str) -> Result<(String, OwnedHandle)> {
    if !path.is_absolute() {
        bail!("{label} path must be absolute");
    }
    let path = wide_null(path);
    // The missing write/delete sharing is intentional: the lease prevents path replacement.
    // SAFETY: path is NUL-terminated and optional pointers are null.
    let handle = unsafe {
        CreateFileW(
            path.as_ptr(),
            FILE_READ_DATA | FILE_READ_ATTRIBUTES | READ_CONTROL,
            FILE_SHARE_READ,
            null(),
            OPEN_EXISTING,
            FILE_FLAG_OPEN_REPARSE_POINT,
            null_mut(),
        )
    };
    if handle == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error()).with_context(|| format!("open {label}"));
    }
    // SAFETY: CreateFileW returned a unique, owned handle.
    let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
    let raw_handle = handle.as_raw_handle();
    let mut information = BY_HANDLE_FILE_INFORMATION::default();
    // SAFETY: information is a valid output buffer and the handle is live.
    if unsafe { GetFileInformationByHandle(raw_handle, &mut information) } == 0 {
        return Err(io::Error::last_os_error()).with_context(|| format!("inspect {label} handle"));
    }
    if information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) != 0
    {
        bail!("{label} must be a plain file, not a directory or reparse point");
    }

    let canonical_path = final_dos_path(raw_handle)?;
    Ok((canonical_path, handle))
}

fn final_dos_path(handle: *mut c_void) -> Result<String> {
    // A zero flag requests FILE_NAME_NORMALIZED with VOLUME_NAME_DOS.
    // SAFETY: the first call intentionally has no output buffer to obtain the size.
    let required = unsafe { GetFinalPathNameByHandleW(handle, null_mut(), 0, 0) };
    if required == 0 || required > 32_768 {
        return Err(io::Error::last_os_error()).context("size strict executable final path");
    }
    let mut buffer = vec![0_u16; required as usize + 1];
    // SAFETY: buffer has room for the reported path plus a terminator.
    let written =
        unsafe { GetFinalPathNameByHandleW(handle, buffer.as_mut_ptr(), buffer.len() as u32, 0) };
    if written == 0 || written as usize >= buffer.len() {
        return Err(io::Error::last_os_error()).context("read strict executable final path");
    }
    let mut path = String::from_utf16(&buffer[..written as usize])
        .context("strict executable final path is not UTF-16")?;
    if let Some(unc) = path.strip_prefix(r"\\?\UNC\") {
        path = format!(r"\\{unc}");
    } else if let Some(dos) = path.strip_prefix(r"\\?\") {
        path = dos.to_owned();
    }
    if path.as_bytes().get(1) == Some(&b':') {
        path.replace_range(0..1, &path[..1].to_ascii_uppercase());
    }
    Ok(path)
}

fn wfp_app_id(path: &str) -> Result<(String, Vec<u8>)> {
    let path = wide_null(path);
    let mut blob = null_mut();
    // SAFETY: path is NUL-terminated and blob is a valid output pointer.
    let status = unsafe { FwpmGetAppIdFromFileName0(path.as_ptr(), &mut blob) };
    if status != 0 {
        bail!("retrieve WFP application identity failed with status 0x{status:08x}");
    }
    let blob = OwnedWfpBlob(blob);
    if blob.0.is_null() {
        bail!("WFP returned an empty application identity pointer");
    }
    // SAFETY: FwpmGetAppIdFromFileName0 returned a valid FWP_BYTE_BLOB allocation.
    let value = unsafe { &*blob.0 };
    if value.size == 0 || value.size > MAX_WFP_APP_ID_BYTES || value.data.is_null() {
        bail!("WFP returned an invalid application identity");
    }
    // SAFETY: the WFP allocation contains value.size readable bytes.
    let bytes = unsafe { std::slice::from_raw_parts(value.data, value.size as usize) };
    Ok((format!("{:x}", Sha256::digest(bytes)), bytes.to_vec()))
}

fn authenticode_publisher_digest(handle: *mut c_void, path: &str) -> Result<String> {
    let wide_path = wide_null(path);
    let mut file_info = WINTRUST_FILE_INFO {
        cbStruct: size_of::<WINTRUST_FILE_INFO>() as u32,
        pcwszFilePath: wide_path.as_ptr(),
        hFile: handle,
        pgKnownSubject: null_mut(),
    };
    let mut trust_data = new_trust_data(WTD_CHOICE_FILE);
    trust_data.Anonymous.pFile = &mut file_info;
    match verify_trust_data(&mut trust_data)? {
        Ok(digest) => Ok(digest),
        Err(status) if status == TRUST_E_NOSIGNATURE as u32 => {
            catalog_publisher_digest(handle, &wide_path)
        }
        Err(status) => bail!("Authenticode trust verification failed with status 0x{status:08x}"),
    }
}

fn new_trust_data(union_choice: u32) -> WINTRUST_DATA {
    WINTRUST_DATA {
        cbStruct: size_of::<WINTRUST_DATA>() as u32,
        dwUIChoice: WTD_UI_NONE,
        fdwRevocationChecks: WTD_REVOKE_WHOLECHAIN,
        dwUnionChoice: union_choice,
        dwStateAction: WTD_STATEACTION_VERIFY,
        dwProvFlags: WTD_CACHE_ONLY_URL_RETRIEVAL | WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT,
        dwUIContext: WTD_UICONTEXT_EXECUTE,
        ..WINTRUST_DATA::default()
    }
}

fn verify_trust_data(trust_data: &mut WINTRUST_DATA) -> Result<std::result::Result<String, u32>> {
    let mut action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    // SAFETY: the caller keeps the selected WinTrust union structure and its pointers live.
    let verify_status = unsafe {
        WinVerifyTrust(
            INVALID_HANDLE_VALUE,
            &mut action,
            (trust_data as *mut WINTRUST_DATA).cast(),
        )
    };
    let digest_result = if verify_status == 0 {
        Some(extract_publisher_digest(trust_data.hWVTStateData))
    } else {
        None
    };

    trust_data.dwStateAction = WTD_STATEACTION_CLOSE;
    // SAFETY: this closes the state created by the matching VERIFY call.
    let close_status = unsafe {
        WinVerifyTrust(
            INVALID_HANDLE_VALUE,
            &mut action,
            (trust_data as *mut WINTRUST_DATA).cast(),
        )
    };
    if close_status != 0 {
        bail!(
            "Authenticode trust state cleanup failed with status 0x{:08x}",
            close_status as u32
        );
    }
    if verify_status == 0 {
        Ok(Ok(digest_result.expect(
            "successful trust verification has a digest result",
        )?))
    } else {
        Ok(Err(verify_status as u32))
    }
}

fn catalog_publisher_digest(handle: *mut c_void, member_path: &[u16]) -> Result<String> {
    let admin = OwnedCatalogAdmin::acquire_sha256()?;
    let mut hash_len = 0_u32;
    // SAFETY: admin and file handles are live; a null buffer requests the required size.
    if unsafe {
        CryptCATAdminCalcHashFromFileHandle2(admin.0, handle, &mut hash_len, null_mut(), 0)
    } == 0
    {
        return Err(io::Error::last_os_error()).context("size executable catalog hash");
    }
    if hash_len == 0 || hash_len > MAX_CATALOG_HASH_BYTES {
        bail!("Windows returned an invalid executable catalog hash size");
    }
    let mut hash = vec![0_u8; hash_len as usize];
    // SAFETY: hash has the exact size requested by the catalog API.
    if unsafe {
        CryptCATAdminCalcHashFromFileHandle2(admin.0, handle, &mut hash_len, hash.as_mut_ptr(), 0)
    } == 0
    {
        return Err(io::Error::last_os_error()).context("calculate executable catalog hash");
    }
    hash.truncate(hash_len as usize);
    let mut member_tag = String::with_capacity(hash.len() * 2);
    for byte in &hash {
        write!(member_tag, "{byte:02X}").expect("writing to a String cannot fail");
    }
    let member_tag = wide_null(member_tag);
    let mut catalog = OwnedCatalogContext::first(admin.0, &hash);
    let mut last_status = None;

    for _ in 0..MAX_MATCHING_CATALOGS {
        if catalog.context == 0 {
            break;
        }
        let mut catalog_info = CATALOG_INFO {
            cbStruct: size_of::<CATALOG_INFO>() as u32,
            ..CATALOG_INFO::default()
        };
        // SAFETY: catalog is a live HCATINFO and catalog_info is a valid output buffer.
        if unsafe { CryptCATCatalogInfoFromContext(catalog.context, &mut catalog_info, 0) } == 0 {
            return Err(io::Error::last_os_error()).context("read executable catalog path");
        }
        if catalog_info.wszCatalogFile[0] == 0 || !catalog_info.wszCatalogFile.contains(&0) {
            bail!("Windows returned an invalid executable catalog path");
        }
        let mut trust_info = WINTRUST_CATALOG_INFO {
            cbStruct: size_of::<WINTRUST_CATALOG_INFO>() as u32,
            pcwszCatalogFilePath: catalog_info.wszCatalogFile.as_ptr(),
            pcwszMemberTag: member_tag.as_ptr(),
            pcwszMemberFilePath: member_path.as_ptr(),
            hMemberFile: handle,
            pbCalculatedFileHash: hash.as_mut_ptr(),
            cbCalculatedFileHash: hash_len,
            hCatAdmin: admin.0,
            ..WINTRUST_CATALOG_INFO::default()
        };
        let mut trust_data = new_trust_data(WTD_CHOICE_CATALOG);
        trust_data.Anonymous.pCatalog = &mut trust_info;
        match verify_trust_data(&mut trust_data)? {
            Ok(digest) => return Ok(digest),
            Err(status) => last_status = Some(status),
        }
        catalog.advance(&hash);
    }

    if catalog.context != 0 {
        bail!("executable appears in too many Windows security catalogs");
    }
    if let Some(status) = last_status {
        bail!("catalog trust verification failed with status 0x{status:08x}");
    }
    bail!("executable has neither a trusted embedded signature nor a SHA-256 catalog signature")
}

fn extract_publisher_digest(state: *mut c_void) -> Result<String> {
    if state.is_null() {
        bail!("Authenticode verification returned no provider state");
    }
    // SAFETY: state is a live handle from WTD_STATEACTION_VERIFY.
    let provider = unsafe { WTHelperProvDataFromStateData(state) };
    if provider.is_null() {
        bail!("Authenticode provider data is unavailable");
    }
    // SAFETY: provider is live and index zero requests the primary signer.
    let signer = unsafe { WTHelperGetProvSignerFromChain(provider, 0, 0, 0) };
    if signer.is_null() {
        bail!("Authenticode primary signer is unavailable");
    }
    // SAFETY: signer is owned by the live WinTrust state.
    let signer = unsafe { &*signer };
    if signer.dwError != 0 || signer.csCertChain == 0 || signer.pasCertChain.is_null() {
        bail!("Authenticode signer chain is invalid");
    }
    // SAFETY: a non-empty pasCertChain starts with the publisher leaf certificate.
    let publisher = unsafe { &*signer.pasCertChain };
    if publisher.dwError != 0 || publisher.fTestCert != 0 || publisher.pCert.is_null() {
        bail!("Authenticode publisher certificate is invalid or a test certificate");
    }
    // SAFETY: the certificate context is valid while the WinTrust state remains open.
    let certificate = unsafe { &*publisher.pCert };
    if certificate.cbCertEncoded == 0 || certificate.pbCertEncoded.is_null() {
        bail!("Authenticode publisher certificate encoding is empty");
    }
    // SAFETY: the certificate context contains cbCertEncoded readable DER bytes.
    let bytes = unsafe {
        std::slice::from_raw_parts(
            certificate.pbCertEncoded,
            certificate.cbCertEncoded as usize,
        )
    };
    Ok(format!("{:x}", Sha256::digest(bytes)))
}

struct OwnedWfpBlob(*mut FWP_BYTE_BLOB);

impl Drop for OwnedWfpBlob {
    fn drop(&mut self) {
        let mut pointer = self.0.cast();
        // SAFETY: pointer was allocated by WFP and is freed exactly once here.
        unsafe {
            FwpmFreeMemory0(&mut pointer);
        }
    }
}

struct OwnedCatalogAdmin(isize);

impl OwnedCatalogAdmin {
    fn acquire_sha256() -> Result<Self> {
        let mut handle = 0_isize;
        // SAFETY: handle is a valid output pointer; optional policy pointers are null.
        if unsafe {
            CryptCATAdminAcquireContext2(&mut handle, null(), BCRYPT_SHA256_ALGORITHM, null(), 0)
        } == 0
        {
            return Err(io::Error::last_os_error()).context("acquire SHA-256 catalog context");
        }
        if handle == 0 {
            bail!("Windows returned an empty catalog administrator context");
        }
        Ok(Self(handle))
    }
}

impl Drop for OwnedCatalogAdmin {
    fn drop(&mut self) {
        if self.0 != 0 {
            // SAFETY: the context is owned and released exactly once.
            unsafe {
                CryptCATAdminReleaseContext(self.0, 0);
            }
        }
    }
}

struct OwnedCatalogContext {
    admin: isize,
    context: isize,
}

impl OwnedCatalogContext {
    fn first(admin: isize, hash: &[u8]) -> Self {
        // SAFETY: admin is live and hash remains readable for the duration of the call.
        let context = unsafe {
            CryptCATAdminEnumCatalogFromHash(admin, hash.as_ptr(), hash.len() as u32, 0, null_mut())
        };
        Self { admin, context }
    }

    fn advance(&mut self, hash: &[u8]) {
        let mut previous = std::mem::take(&mut self.context);
        // CryptCATAdminEnumCatalogFromHash consumes the previous enumeration context.
        // SAFETY: admin and previous are live and hash is readable for the call.
        self.context = unsafe {
            CryptCATAdminEnumCatalogFromHash(
                self.admin,
                hash.as_ptr(),
                hash.len() as u32,
                0,
                &mut previous,
            )
        };
    }
}

impl Drop for OwnedCatalogContext {
    fn drop(&mut self) {
        if self.context != 0 {
            // SAFETY: the context is owned and its administrator remains live.
            unsafe {
                CryptCATAdminReleaseCatalogContext(self.admin, self.context, 0);
            }
        }
    }
}

fn wide_null(value: impl AsRef<Path>) -> Vec<u16> {
    value
        .as_ref()
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect()
}
