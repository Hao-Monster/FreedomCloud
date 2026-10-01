//! Per-user strict ingress recovery credentials. Only the OS Keychain receives
//! secret data; callers must not log the returned string or put it in argv/files.
//! The account is an endpoint/UID-derived identifier selected by the runtime.
//! Operations must run outside the async executor's reactor thread.
#![cfg(target_os = "macos")]

use std::ffi::{c_char, c_void};
use std::ptr::{null, null_mut};
use std::sync::Mutex;

use anyhow::{anyhow, bail, Result};

const SERVICE: &[u8] = b"com.freedomcloud.agent.strict-ingress";
const MAX_BYTES: usize = 4 * 1024 * 1024;
const ITEM_NOT_FOUND: i32 = -25300;
// Interaction permission is process-wide, so all accesses in this module share
// this lock and restore the previous setting before releasing it.
static KEYCHAIN_LOCK: Mutex<()> = Mutex::new(());

#[link(name = "Security", kind = "framework")]
extern "C" {
    fn SecKeychainCopyDefault(keychain: *mut *mut c_void) -> i32;
    fn SecKeychainGetUserInteractionAllowed(allowed: *mut u8) -> i32;
    fn SecKeychainSetUserInteractionAllowed(allowed: u8) -> i32;
    fn SecKeychainFindGenericPassword(
        keychain: *const c_void,
        service_len: u32,
        service: *const c_char,
        account_len: u32,
        account: *const c_char,
        password_len: *mut u32,
        password: *mut *mut c_void,
        item: *mut *mut c_void,
    ) -> i32;
    fn SecKeychainAddGenericPassword(
        keychain: *mut c_void,
        service_len: u32,
        service: *const c_char,
        account_len: u32,
        account: *const c_char,
        password_len: u32,
        password: *const c_void,
        item: *mut *mut c_void,
    ) -> i32;
    fn SecKeychainItemModifyAttributesAndData(
        item: *mut c_void,
        attributes: *const c_void,
        length: u32,
        data: *const c_void,
    ) -> i32;
    fn SecKeychainItemDelete(item: *mut c_void) -> i32;
    fn SecKeychainItemFreeContent(attributes: *mut c_void, data: *mut c_void) -> i32;
}

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFRelease(value: *const c_void);
}

struct Object(*mut c_void);
impl Drop for Object {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: only owned Copy/Find references enter this wrapper.
            unsafe { CFRelease(self.0) };
        }
    }
}

struct PasswordBuffer {
    pointer: *mut c_void,
    length: u32,
}
impl Drop for PasswordBuffer {
    fn drop(&mut self) {
        if !self.pointer.is_null() {
            // SAFETY: Security.framework owns this returned allocation. Clear
            // its secret bytes before releasing it using the matching API.
            unsafe {
                for index in 0..self.length as usize {
                    self.pointer.cast::<u8>().add(index).write_volatile(0);
                }
                SecKeychainItemFreeContent(null_mut(), self.pointer);
            }
        }
    }
}

struct InteractionGuard {
    previous: u8,
    restored: bool,
}
impl InteractionGuard {
    fn disable() -> Result<Self> {
        let mut previous = 0;
        // SAFETY: valid one-byte Boolean out-pointer, no borrowed FFI storage.
        check(unsafe { SecKeychainGetUserInteractionAllowed(&mut previous) }, "read interaction policy")?;
        check(unsafe { SecKeychainSetUserInteractionAllowed(0) }, "disable interaction")?;
        Ok(Self { previous, restored: false })
    }

    fn restore(&mut self) -> Result<()> {
        check(unsafe { SecKeychainSetUserInteractionAllowed(self.previous) }, "restore interaction policy")?;
        self.restored = true;
        Ok(())
    }
}
impl Drop for InteractionGuard {
    fn drop(&mut self) {
        if !self.restored {
            // Normal exits explicitly restore and report errors. This fallback
            // covers unwinding; destructors cannot propagate a second error.
            unsafe { SecKeychainSetUserInteractionAllowed(self.previous) };
        }
    }
}

fn check(status: i32, operation: &'static str) -> Result<()> {
    if status != 0 {
        bail!("macOS strict Keychain {operation} failed (OSStatus {status})");
    }
    Ok(())
}

fn with_keychain<T>(account: &str, action: impl FnOnce(&Object) -> Result<T>) -> Result<T> {
    if account.is_empty() || account.len() > 512 || account.as_bytes().contains(&0) {
        bail!("invalid macOS strict Keychain account identifier");
    }
    let _lock = KEYCHAIN_LOCK.lock().map_err(|_| anyhow!("macOS strict Keychain lock poisoned"))?;
    let mut interaction = InteractionGuard::disable()?;
    let result = (|| {
        let mut keychain = Object(null_mut());
        check(unsafe { SecKeychainCopyDefault(&mut keychain.0) }, "open default keychain")?;
        if keychain.0.is_null() {
            bail!("macOS strict default Keychain reference is missing");
        }
        action(&keychain)
    })();
    // Never report success if non-interactive policy restoration failed. Keep
    // the primary operation error otherwise; both errors contain no secrets.
    let restore = interaction.restore();
    match (result, restore) {
        (Ok(value), Ok(())) => Ok(value),
        (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(error),
        (Err(error), Err(restore_error)) => Err(error.context(restore_error.to_string())),
    }
}

/// Return None only when the exact service/account item is absent. A locked
/// Keychain, denied ACL, invalid UTF-8 or oversized saved value is an error.
pub fn load(account: &str) -> Result<Option<String>> {
    with_keychain(account, |keychain| {
        let mut password = PasswordBuffer { pointer: null_mut(), length: 0 };
        let status = unsafe {
            SecKeychainFindGenericPassword(
                keychain.0, SERVICE.len() as u32, SERVICE.as_ptr().cast(),
                account.len() as u32, account.as_ptr().cast(),
                &mut password.length, &mut password.pointer, null_mut(),
            )
        };
        if status == ITEM_NOT_FOUND { return Ok(None); }
        check(status, "read credentials")?;
        if password.length as usize > MAX_BYTES {
            bail!("macOS strict Keychain value exceeds 4 MiB");
        }
        if password.length == 0 { return Ok(Some(String::new())); }
        if password.pointer.is_null() {
            bail!("macOS strict Keychain returned missing credential data");
        }
        // SAFETY: a successful Keychain lookup owns length readable bytes until
        // PasswordBuffer drops. Copy only after enforcing the payload bound.
        let bytes = unsafe { std::slice::from_raw_parts(password.pointer.cast::<u8>(), password.length as usize) };
        let text = std::str::from_utf8(bytes).map_err(|_| anyhow!("macOS strict Keychain value is not UTF-8"))?;
        Ok(Some(text.to_owned()))
    })
}

/// Replace credentials without recreating the item's existing ACL. None deletes
/// the exact item; deleting an absent item succeeds. No shell or files are used.
pub fn save(account: &str, value: Option<&str>) -> Result<()> {
    if value.is_some_and(|text| text.len() > MAX_BYTES) {
        bail!("macOS strict Keychain value exceeds 4 MiB");
    }
    with_keychain(account, |keychain| {
        let mut item = Object(null_mut());
        let status = unsafe {
            SecKeychainFindGenericPassword(
                keychain.0, SERVICE.len() as u32, SERVICE.as_ptr().cast(),
                account.len() as u32, account.as_ptr().cast(),
                null_mut(), null_mut(), &mut item.0,
            )
        };
        if status == ITEM_NOT_FOUND {
            if let Some(text) = value {
                check(unsafe {
                    SecKeychainAddGenericPassword(
                        keychain.0, SERVICE.len() as u32, SERVICE.as_ptr().cast(),
                        account.len() as u32, account.as_ptr().cast(),
                        text.len() as u32, text.as_ptr().cast(), null_mut(),
                    )
                }, "create credentials")?;
            }
            return Ok(());
        }
        check(status, "find credential item")?;
        if item.0.is_null() { bail!("macOS strict Keychain item reference is missing"); }
        match value {
            Some(text) => check(unsafe {
                SecKeychainItemModifyAttributesAndData(item.0, null(), text.len() as u32, text.as_ptr().cast())
            }, "replace credentials"),
            None => {
                let result = unsafe { SecKeychainItemDelete(item.0) };
                if result == ITEM_NOT_FOUND { Ok(()) } else { check(result, "delete credentials") }
            }
        }
    })
}
