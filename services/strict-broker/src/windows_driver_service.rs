use std::io;
use std::mem::size_of;
use std::ptr::{null, null_mut};

use anyhow::{bail, Context, Result};
use windows_sys::Win32::Foundation::ERROR_INSUFFICIENT_BUFFER;
use windows_sys::Win32::System::Services::{
    CloseServiceHandle, OpenSCManagerW, OpenServiceW, QueryServiceConfigW, QUERY_SERVICE_CONFIGW,
    SC_HANDLE, SC_MANAGER_CONNECT, SERVICE_KERNEL_DRIVER, SERVICE_QUERY_CONFIG,
};

const MAX_SERVICE_CONFIG_BYTES: usize = 64 * 1024;

pub(crate) struct WindowsDriverServiceLease {
    _manager: OwnedScHandle,
    _service: OwnedScHandle,
}

pub(crate) fn verify_windows_driver_service(
    service_name: &str,
    expected_canonical_path: &str,
) -> Result<WindowsDriverServiceLease> {
    let service_name = validate_service_name(service_name)?;
    // SAFETY: null machine/database names select the local active SCM database.
    let manager = unsafe { OpenSCManagerW(null(), null(), SC_MANAGER_CONNECT) };
    let manager = OwnedScHandle::new(manager).context("open local service control manager")?;
    // SAFETY: the manager handle is live and the service name is NUL-terminated.
    let service =
        unsafe { OpenServiceW(manager.raw(), service_name.as_ptr(), SERVICE_QUERY_CONFIG) };
    let service = OwnedScHandle::new(service).context("open strict callout driver service")?;
    let config = query_service_config(service.raw())?;
    validate_driver_service_binding(
        config.service_type,
        &config.binary_path,
        expected_canonical_path,
    )?;
    Ok(WindowsDriverServiceLease {
        _manager: manager,
        _service: service,
    })
}

struct DriverServiceConfig {
    service_type: u32,
    binary_path: String,
}

fn query_service_config(service: SC_HANDLE) -> Result<DriverServiceConfig> {
    let mut needed = 0_u32;
    // SAFETY: this sizing call intentionally supplies no output buffer.
    if unsafe { QueryServiceConfigW(service, null_mut(), 0, &mut needed) } != 0 {
        bail!("strict driver service configuration sizing unexpectedly succeeded");
    }
    let error = io::Error::last_os_error();
    if error.raw_os_error() != Some(ERROR_INSUFFICIENT_BUFFER as i32) {
        return Err(error).context("size strict driver service configuration");
    }
    let needed =
        usize::try_from(needed).context("strict driver service configuration is too large")?;
    if needed < size_of::<QUERY_SERVICE_CONFIGW>() || needed > MAX_SERVICE_CONFIG_BYTES {
        bail!("strict driver service configuration size is invalid");
    }

    // QUERY_SERVICE_CONFIGW contains pointers, so use pointer-aligned backing storage.
    let word_bytes = size_of::<usize>();
    let word_count = needed
        .checked_add(word_bytes - 1)
        .ok_or_else(|| anyhow::anyhow!("strict driver service configuration size overflow"))?
        / word_bytes;
    let mut storage = vec![0_usize; word_count];
    let storage_bytes = storage
        .len()
        .checked_mul(word_bytes)
        .ok_or_else(|| anyhow::anyhow!("strict driver service configuration size overflow"))?;
    let config = storage.as_mut_ptr().cast::<QUERY_SERVICE_CONFIGW>();
    let mut returned = 0_u32;
    // SAFETY: storage is aligned and large enough for the byte count supplied.
    if unsafe {
        QueryServiceConfigW(
            service,
            config,
            u32::try_from(storage_bytes).expect("bounded service configuration size"),
            &mut returned,
        )
    } == 0
    {
        return Err(io::Error::last_os_error())
            .context("query strict driver service configuration");
    }
    // SAFETY: QueryServiceConfigW initialized the leading structure in storage.
    let config = unsafe { &*config };
    let binary_path = read_bounded_wide_string(
        config.lpBinaryPathName,
        storage.as_ptr() as usize,
        storage_bytes,
    )?;
    Ok(DriverServiceConfig {
        service_type: config.dwServiceType,
        binary_path,
    })
}

fn read_bounded_wide_string(pointer: *const u16, base: usize, bytes: usize) -> Result<String> {
    let end = base
        .checked_add(bytes)
        .ok_or_else(|| anyhow::anyhow!("strict driver service configuration range overflow"))?;
    let address = pointer as usize;
    if pointer.is_null()
        || address < base
        || address >= end
        || (address - base) % size_of::<u16>() != 0
    {
        bail!("strict driver service image path pointer is invalid");
    }
    let capacity = (end - address) / size_of::<u16>();
    // SAFETY: the pointer was proven to be aligned and contained by the live storage buffer.
    let values = unsafe { std::slice::from_raw_parts(pointer, capacity) };
    let length = values
        .iter()
        .position(|value| *value == 0)
        .ok_or_else(|| anyhow::anyhow!("strict driver service image path is not terminated"))?;
    String::from_utf16(&values[..length])
        .context("strict driver service image path is not valid UTF-16")
}

fn validate_driver_service_binding(
    service_type: u32,
    configured_path: &str,
    expected_canonical_path: &str,
) -> Result<()> {
    if service_type != SERVICE_KERNEL_DRIVER {
        bail!("strict callout service is not an exclusive kernel-driver service");
    }
    let configured = normalize_driver_image_path(configured_path, false)?;
    let expected = normalize_driver_image_path(expected_canonical_path, true)?;
    if !configured.eq_ignore_ascii_case(&expected) {
        bail!("strict callout service image path does not match the signed driver file");
    }
    Ok(())
}

fn normalize_driver_image_path(value: &str, canonical: bool) -> Result<String> {
    if value.is_empty()
        || value.len() > 1024
        || !value.is_ascii()
        || value.trim() != value
        || value.contains(['\0', '\r', '\n', '/', '"', '%'])
    {
        bail!("strict driver service image path is invalid");
    }
    let path = if canonical {
        value
    } else if let Some(path) = value.strip_prefix(r"\\?\") {
        path
    } else {
        value.strip_prefix(r"\??\").unwrap_or(value)
    };
    let bytes = path.as_bytes();
    if bytes.len() < 7
        || !bytes[0].is_ascii_alphabetic()
        || bytes[1] != b':'
        || bytes[2] != b'\\'
        || !path.to_ascii_lowercase().ends_with(".sys")
        || path[3..].split('\\').any(|part| {
            part.is_empty()
                || part == "."
                || part == ".."
                || part.contains(['*', '?', ':', '|', '<', '>'])
        })
    {
        bail!("strict driver service image path must be an absolute plain .sys path");
    }
    Ok(path.to_owned())
}

fn validate_service_name(value: &str) -> Result<Vec<u16>> {
    if value.is_empty()
        || value.len() > 128
        || !value.is_ascii()
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        bail!("strict driver service name is invalid");
    }
    Ok(value.encode_utf16().chain(Some(0)).collect())
}

struct OwnedScHandle(SC_HANDLE);

// SCM handles are process-scoped kernel handles with no thread affinity. This
// wrapper has unique ownership and is only moved so its eventual close can run
// on the Broker's bounded lease-renewal worker.
unsafe impl Send for OwnedScHandle {}

impl OwnedScHandle {
    fn new(handle: SC_HANDLE) -> Result<Self> {
        if handle.is_null() {
            return Err(io::Error::last_os_error()).context("acquire service control handle");
        }
        Ok(Self(handle))
    }

    fn raw(&self) -> SC_HANDLE {
        self.0
    }
}

impl Drop for OwnedScHandle {
    fn drop(&mut self) {
        // SAFETY: this wrapper uniquely owns a nonzero SCM handle.
        unsafe { CloseServiceHandle(self.0) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CANONICAL: &str = r"C:\Program Files\FlClashX\driver\FlClashStrictCallout.sys";

    #[test]
    fn accepts_only_an_exact_kernel_driver_binding() {
        validate_driver_service_binding(
            SERVICE_KERNEL_DRIVER,
            r"C:\Program Files\FlClashX\driver\FlClashStrictCallout.sys",
            CANONICAL,
        )
        .unwrap();
        validate_driver_service_binding(
            SERVICE_KERNEL_DRIVER,
            r"\??\c:\program files\flclashx\driver\flclashstrictcallout.sys",
            CANONICAL,
        )
        .unwrap();

        assert!(validate_driver_service_binding(
            SERVICE_KERNEL_DRIVER | 0x100,
            r"C:\Program Files\FlClashX\driver\FlClashStrictCallout.sys",
            CANONICAL,
        )
        .is_err());
        assert!(validate_driver_service_binding(
            SERVICE_KERNEL_DRIVER,
            r"C:\Program Files\FlClashX\driver\other.sys",
            CANONICAL,
        )
        .is_err());
    }

    #[test]
    fn rejects_ambiguous_or_expandable_service_paths() {
        for path in [
            r#""C:\Program Files\FlClashX\driver\FlClashStrictCallout.sys""#,
            r"%ProgramFiles%\FlClashX\driver\FlClashStrictCallout.sys",
            r"C:\Program Files\FlClashX\driver\FlClashStrictCallout.sys --argument",
            r"C:\Program Files\FlClashX\driver\..\FlClashStrictCallout.sys",
            r"\\server\share\FlClashStrictCallout.sys",
            r"driver\FlClashStrictCallout.sys",
        ] {
            assert!(
                validate_driver_service_binding(SERVICE_KERNEL_DRIVER, path, CANONICAL).is_err()
            );
        }
    }

    #[test]
    fn service_names_are_narrow_and_terminated() {
        let valid = validate_service_name("FlClashStrictCallout").unwrap();
        assert_eq!(valid.last(), Some(&0));
        assert!(validate_service_name("").is_err());
        assert!(validate_service_name("FlClash Strict Callout").is_err());
        assert!(validate_service_name(&"x".repeat(129)).is_err());
    }
}
