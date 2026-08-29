use std::ffi::c_void;
use std::io;
use std::mem::size_of;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::Path;
use std::ptr::{addr_of, null, null_mut};

use anyhow::{bail, Context, Result};
use windows_sys::Win32::Foundation::{LocalFree, INVALID_HANDLE_VALUE};
use windows_sys::Win32::Security::Authorization::{GetSecurityInfo, SE_FILE_OBJECT};
use windows_sys::Win32::Security::{
    CreateWellKnownSid, EqualSid, GetAce, GetLengthSid, GetSecurityDescriptorControl,
    GetSecurityDescriptorDacl, GetSecurityDescriptorOwner, IsValidSid, WinBuiltinAdministratorsSid,
    WinLocalSystemSid, ACCESS_ALLOWED_ACE, ACL, CONTAINER_INHERIT_ACE, DACL_SECURITY_INFORMATION,
    INHERITED_ACE, OBJECT_INHERIT_ACE, OWNER_SECURITY_INFORMATION, PSECURITY_DESCRIPTOR, PSID,
    SE_DACL_PROTECTED,
};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION, FILE_ALL_ACCESS,
    FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_REPARSE_POINT, FILE_FLAG_BACKUP_SEMANTICS,
    FILE_FLAG_OPEN_REPARSE_POINT, FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE,
    OPEN_EXISTING, READ_CONTROL,
};
use windows_sys::Win32::System::SystemServices::ACCESS_ALLOWED_ACE_TYPE;

pub struct WindowsRecoveryAclVerifier;

impl WindowsRecoveryAclVerifier {
    pub fn verify_directory(path: impl AsRef<Path>) -> Result<()> {
        let path = path.as_ref();
        if !path.is_absolute() {
            bail!("strict recovery directory must be absolute");
        }
        let wide_path: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        // SAFETY: path is NUL-terminated and optional pointers are null.
        let handle = unsafe {
            CreateFileW(
                wide_path.as_ptr(),
                READ_CONTROL,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                null(),
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                null_mut(),
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error()).context("open strict recovery directory ACL");
        }
        // SAFETY: CreateFileW returned a unique owned handle.
        let handle = unsafe { OwnedHandle::from_raw_handle(handle) };
        let mut information = BY_HANDLE_FILE_INFORMATION::default();
        // SAFETY: the handle is live and information is a valid output buffer.
        if unsafe { GetFileInformationByHandle(handle.as_raw_handle(), &mut information) } == 0 {
            return Err(io::Error::last_os_error())
                .context("inspect strict recovery directory handle");
        }
        if information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY == 0
            || information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT != 0
        {
            bail!("strict recovery path is not a plain directory");
        }

        let mut descriptor = null_mut();
        // SAFETY: the handle is live and descriptor is a valid output pointer.
        let status = unsafe {
            GetSecurityInfo(
                handle.as_raw_handle(),
                SE_FILE_OBJECT,
                OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
                null_mut(),
                null_mut(),
                null_mut(),
                null_mut(),
                &mut descriptor,
            )
        };
        if status != 0 {
            bail!("read strict recovery directory ACL failed with status 0x{status:08x}");
        }
        let descriptor = OwnedSecurityDescriptor(descriptor);
        validate_descriptor(descriptor.0)
    }
}

fn validate_descriptor(descriptor: PSECURITY_DESCRIPTOR) -> Result<()> {
    if descriptor.is_null() {
        bail!("strict recovery security descriptor is missing");
    }
    let system_sid = well_known_sid(WinLocalSystemSid)?;
    let administrators_sid = well_known_sid(WinBuiltinAdministratorsSid)?;

    let mut control = 0_u16;
    let mut revision = 0_u32;
    // SAFETY: descriptor is live and both output pointers are valid.
    if unsafe { GetSecurityDescriptorControl(descriptor, &mut control, &mut revision) } == 0 {
        return Err(io::Error::last_os_error())
            .context("read strict recovery security descriptor control");
    }
    if control & SE_DACL_PROTECTED == 0 {
        bail!("strict recovery DACL must be protected from inheritance");
    }

    let mut owner = null_mut();
    let mut owner_defaulted = 0;
    // SAFETY: descriptor and outputs are valid.
    if unsafe { GetSecurityDescriptorOwner(descriptor, &mut owner, &mut owner_defaulted) } == 0 {
        return Err(io::Error::last_os_error()).context("read strict recovery owner");
    }
    if owner.is_null()
        || owner_defaulted != 0
        || (!sid_equal(owner, system_sid.as_psid())
            && !sid_equal(owner, administrators_sid.as_psid()))
    {
        bail!("strict recovery owner must be LocalSystem or Administrators");
    }

    let mut dacl_present = 0;
    let mut dacl: *mut ACL = null_mut();
    let mut dacl_defaulted = 0;
    // SAFETY: descriptor and outputs are valid.
    if unsafe {
        GetSecurityDescriptorDacl(
            descriptor,
            &mut dacl_present,
            &mut dacl,
            &mut dacl_defaulted,
        )
    } == 0
    {
        return Err(io::Error::last_os_error()).context("read strict recovery DACL");
    }
    if dacl_present == 0 || dacl.is_null() || dacl_defaulted != 0 {
        bail!("strict recovery DACL must be explicit and non-null");
    }
    // SAFETY: dacl was returned from a valid security descriptor.
    let ace_count = unsafe { (*dacl).AceCount } as u32;
    if ace_count != 2 {
        bail!("strict recovery DACL must contain exactly two access entries");
    }

    let mut saw_system = false;
    let mut saw_administrators = false;
    for index in 0..ace_count {
        let mut ace_pointer = null_mut();
        // SAFETY: index is below AceCount and ace_pointer is a valid output.
        if unsafe { GetAce(dacl, index, &mut ace_pointer) } == 0 {
            return Err(io::Error::last_os_error()).context("read strict recovery DACL entry");
        }
        let ace = ace_pointer.cast::<ACCESS_ALLOWED_ACE>();
        // SAFETY: GetAce returned an ACE whose header can be inspected.
        let header = unsafe { (*ace).Header };
        if header.AceType != ACCESS_ALLOWED_ACE_TYPE as u8
            || (header.AceSize as usize) < size_of::<ACCESS_ALLOWED_ACE>()
            || header.AceFlags as u32 != OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE
            || header.AceFlags as u32 & INHERITED_ACE != 0
        {
            bail!("strict recovery DACL contains a non-canonical access entry");
        }
        // SAFETY: the minimum ACE size includes SidStart, which is the first SID byte.
        let sid = unsafe { addr_of!((*ace).SidStart).cast_mut().cast::<c_void>() };
        if unsafe { IsValidSid(sid) } == 0 {
            bail!("strict recovery DACL contains an invalid SID");
        }
        // SAFETY: sid is valid and contained by the ACE allocation.
        let sid_length = unsafe { GetLengthSid(sid) } as usize;
        let sid_offset = size_of::<ACCESS_ALLOWED_ACE>() - size_of::<u32>();
        if sid_offset + sid_length > header.AceSize as usize {
            bail!("strict recovery DACL SID exceeds its access entry");
        }
        // SAFETY: GetAce returned a complete ACCESS_ALLOWED_ACE.
        if unsafe { (*ace).Mask } != FILE_ALL_ACCESS {
            bail!("strict recovery DACL entries must grant exact file full control");
        }
        if sid_equal(sid, system_sid.as_psid()) {
            if saw_system {
                bail!("strict recovery DACL duplicates the LocalSystem entry");
            }
            saw_system = true;
        } else if sid_equal(sid, administrators_sid.as_psid()) {
            if saw_administrators {
                bail!("strict recovery DACL duplicates the Administrators entry");
            }
            saw_administrators = true;
        } else {
            bail!("strict recovery DACL grants access to an unauthorized SID");
        }
    }
    if !saw_system || !saw_administrators {
        bail!("strict recovery DACL is missing a required principal");
    }
    Ok(())
}

struct OwnedSecurityDescriptor(PSECURITY_DESCRIPTOR);

impl Drop for OwnedSecurityDescriptor {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: GetSecurityInfo allocated this descriptor with LocalAlloc.
            unsafe {
                LocalFree(self.0);
            }
        }
    }
}

struct SidStorage([usize; 9]);

impl SidStorage {
    fn as_psid(&self) -> PSID {
        self.0.as_ptr().cast_mut().cast()
    }
}

fn well_known_sid(sid_type: i32) -> Result<SidStorage> {
    let mut storage = SidStorage([0; 9]);
    let mut size = (storage.0.len() * size_of::<usize>()) as u32;
    // SAFETY: storage is aligned and large enough for SECURITY_MAX_SID_SIZE.
    if unsafe {
        CreateWellKnownSid(
            sid_type,
            null_mut(),
            storage.0.as_mut_ptr().cast(),
            &mut size,
        )
    } == 0
    {
        return Err(io::Error::last_os_error()).context("create recovery ACL principal SID");
    }
    Ok(storage)
}

fn sid_equal(left: PSID, right: PSID) -> bool {
    // SAFETY: both SIDs were validated or created by Windows.
    unsafe { EqualSid(left, right) != 0 }
}

#[cfg(test)]
mod tests {
    use super::*;
    use windows_sys::Win32::Security::Authorization::{
        ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
    };

    fn descriptor(sddl: &str) -> OwnedSecurityDescriptor {
        let sddl: Vec<u16> = sddl.encode_utf16().chain(Some(0)).collect();
        let mut descriptor = null_mut();
        // SAFETY: SDDL is NUL-terminated and descriptor is a valid output.
        assert_ne!(
            unsafe {
                ConvertStringSecurityDescriptorToSecurityDescriptorW(
                    sddl.as_ptr(),
                    SDDL_REVISION_1,
                    &mut descriptor,
                    null_mut(),
                )
            },
            0
        );
        OwnedSecurityDescriptor(descriptor)
    }

    #[test]
    fn only_protected_system_and_administrator_full_control_is_accepted() {
        let valid = descriptor("O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)");
        assert!(validate_descriptor(valid.0).is_ok());

        let inherited = descriptor("O:SYG:SYD:(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)");
        assert!(validate_descriptor(inherited.0).is_err());

        let user_writable =
            descriptor("O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FW;;;BU)");
        assert!(validate_descriptor(user_writable.0).is_err());
    }
}
