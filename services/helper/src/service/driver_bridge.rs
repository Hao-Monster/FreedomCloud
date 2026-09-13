//! User-mode bridge for the strict WFP callout device.
//!
//! This is a narrow, versioned IOCTL boundary. It does not install a driver,
//! alter BCD settings, or provide a direct-network fallback. A missing device
//! is surfaced to the authenticated Helper caller so strict mode can remain
//! fail-closed.

#[cfg(target_os = "windows")]
#[allow(dead_code)]
mod windows_bridge {
    use std::ffi::OsStr;
    use std::mem::size_of;
    use std::os::windows::ffi::OsStrExt;
    use std::ptr::null_mut;

    use windows_sys::Win32::Foundation::{CloseHandle, GetLastError, HANDLE, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::Storage::FileSystem::{
        CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
    };
    use windows_sys::Win32::System::IO::DeviceIoControl;

    const DEVICE_PATH: &str = r"\\.\FlClashXStrictCapture";
    const FILE_DEVICE_NETWORK: u32 = 0x12;
    const METHOD_BUFFERED: u32 = 0;
    const FILE_ANY_ACCESS: u32 = 0;
    const IOCTL_SC_UPDATE_POLICY: u32 =
        (FILE_DEVICE_NETWORK << 16) | (FILE_ANY_ACCESS << 14) | (0x8337 << 2) | METHOD_BUFFERED;
    const IOCTL_SC_CLEAR_POLICY: u32 =
        (FILE_DEVICE_NETWORK << 16) | (FILE_ANY_ACCESS << 14) | (0x8338 << 2) | METHOD_BUFFERED;
    const IOCTL_SC_QUERY_STATUS: u32 =
        (FILE_DEVICE_NETWORK << 16) | (FILE_ANY_ACCESS << 14) | (0x8339 << 2) | METHOD_BUFFERED;
    pub const PROTOCOL_VERSION: u32 = 2;

    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default)]
    pub struct PolicyUpdate {
        pub version: u32,
        pub flags: u32,
        pub process_id: u32,
        pub broker_process_id: u32,
        pub proxy_ipv4: u32,
        pub proxy_port: u16,
        pub reserved: u16,
        pub proxy_ipv6: [u8; 16],
    }

    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default)]
    pub struct PolicyClear {
        pub version: u32,
        pub process_id: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy, Debug, Default)]
    pub struct DriverStatus {
        pub version: u32,
        pub policy_count: u32,
        pub registered_callouts: u32,
        pub generation: u32,
    }

    pub struct DriverClient {
        handle: HANDLE,
    }

    impl Drop for DriverClient {
        fn drop(&mut self) {
            if self.handle != INVALID_HANDLE_VALUE {
                // SAFETY: handle was returned by CreateFileW and is owned here.
                unsafe { CloseHandle(self.handle) };
            }
        }
    }

    impl DriverClient {
        pub fn connect() -> Result<Self, String> {
            let path: Vec<u16> = OsStr::new(DEVICE_PATH)
                .encode_wide()
                .chain(Some(0))
                .collect();
            // SAFETY: path is a valid NUL-terminated UTF-16 string.
            let handle = unsafe {
                CreateFileW(
                    path.as_ptr(),
                    0xC0000000,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    null_mut(),
                    OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL,
                    0,
                )
            };
            if handle == INVALID_HANDLE_VALUE {
                return Err(format!(
                    "strict capture device unavailable: Win32 error {}",
                    unsafe { GetLastError() }
                ));
            }
            Ok(Self { handle })
        }

        pub fn update_policy(
            &self,
            process_id: u32,
            broker_process_id: u32,
            proxy_ipv4: u32,
            proxy_port: u16,
            redirect_ready: bool,
        ) -> Result<(), String> {
            if process_id == 0 || broker_process_id == 0 || proxy_port == 0 {
                return Err(
                    "process id, broker process id and proxy port must be non-zero".to_owned(),
                );
            }
            let request = PolicyUpdate {
                version: PROTOCOL_VERSION,
                flags: if redirect_ready { 1 } else { 0 },
                process_id,
                broker_process_id,
                proxy_ipv4,
                proxy_port,
                reserved: 0,
                proxy_ipv6: [0; 16],
            };
            self.call(IOCTL_SC_UPDATE_POLICY, &request, None::<&mut DriverStatus>)
        }

        pub fn clear_policy(&self, process_id: u32) -> Result<(), String> {
            if process_id == 0 {
                return Err("process id must be non-zero".to_owned());
            }
            let request = PolicyClear {
                version: PROTOCOL_VERSION,
                process_id,
            };
            self.call(IOCTL_SC_CLEAR_POLICY, &request, None::<&mut DriverStatus>)
        }

        pub fn status(&self) -> Result<DriverStatus, String> {
            let mut response = DriverStatus::default();
            self.call(IOCTL_SC_QUERY_STATUS, &(), Some(&mut response))?;
            if response.version != PROTOCOL_VERSION {
                return Err(format!(
                    "strict capture protocol mismatch: {}",
                    response.version
                ));
            }
            Ok(response)
        }

        fn call<T: Copy, R>(
            &self,
            code: u32,
            request: &T,
            response: Option<&mut R>,
        ) -> Result<(), String> {
            let mut returned = 0u32;
            let (out_ptr, out_len) = match response {
                Some(value) => (value as *mut R as *mut _, size_of::<R>() as u32),
                None => (null_mut(), 0),
            };
            // SAFETY: buffers remain valid for this synchronous call.
            let ok = unsafe {
                DeviceIoControl(
                    self.handle,
                    code,
                    request as *const T as *mut _,
                    size_of::<T>() as u32,
                    out_ptr,
                    out_len,
                    &mut returned,
                    null_mut(),
                )
            };
            if ok == 0 {
                return Err(format!(
                    "strict capture IOCTL 0x{code:08x} failed: Win32 error {}",
                    unsafe { GetLastError() }
                ));
            }
            Ok(())
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        #[test]
        fn protocol_layout_is_stable() {
            assert_eq!(size_of::<PolicyUpdate>(), 40);
            assert_eq!(size_of::<PolicyClear>(), 8);
            assert_eq!(size_of::<DriverStatus>(), 16);
        }
    }
}

#[cfg(target_os = "windows")]
#[allow(unused_imports)]
pub use windows_bridge::{DriverClient, DriverStatus, PolicyClear, PolicyUpdate, PROTOCOL_VERSION};
