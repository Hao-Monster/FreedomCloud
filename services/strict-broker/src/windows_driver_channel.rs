use std::collections::BTreeSet;
use std::ffi::c_void;
use std::io;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::Path;
use std::ptr::{null, null_mut};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::{StrictAction, StrictCapability, MAX_STRICT_APPLICATIONS};
use sha2::{Digest, Sha256};
use windows_sys::Win32::Foundation::{
    ERROR_IO_PENDING, ERROR_NOT_FOUND, ERROR_OPERATION_ABORTED, GENERIC_READ, GENERIC_WRITE,
    INVALID_HANDLE_VALUE, WAIT_FAILED, WAIT_OBJECT_0, WAIT_TIMEOUT,
};
use windows_sys::Win32::Storage::FileSystem::{CreateFileW, FILE_FLAG_OVERLAPPED, OPEN_EXISTING};
use windows_sys::Win32::System::Threading::{CreateEventW, WaitForSingleObject};
use windows_sys::Win32::System::IO::{
    CancelIoEx, DeviceIoControl, GetOverlappedResult, OVERLAPPED,
};

use crate::{
    verify_windows_driver, WfpPolicyPlan, WindowsDriverPolicyChannel, WindowsDriverPolicySnapshot,
    WindowsDriverTrustLease,
};

const DEVICE_PATH: &str = r"\\.\FlClashStrict";
const WIRE_MAGIC: u32 = u32::from_le_bytes(*b"FCXS");
const WIRE_PROTOCOL: u16 = 1;
const POLICY_HEADER_BYTES: usize = 112;
const POLICY_RULE_BYTES: usize = 16;
const SNAPSHOT_BYTES: usize = 80;
const MAX_DRIVER_POLICY_WIRE_BYTES: usize = 3 * 1024 * 1024;
const MAX_DRIVER_RULES: usize = MAX_STRICT_APPLICATIONS * 33;
const MAX_IOCTL_DEADLINE: Duration = Duration::from_secs(300);

const FILE_DEVICE_NETWORK: u32 = 0x12;
const METHOD_BUFFERED: u32 = 0;
const FILE_READ_WRITE_ACCESS: u32 = 3;
const IOCTL_UPLOAD_POLICY: u32 = ctl_code(0x900);
const IOCTL_UNLOAD_POLICY: u32 = ctl_code(0x901);
const IOCTL_QUERY_POLICY: u32 = ctl_code(0x902);

const SNAPSHOT_FLAG_LOADED: u32 = 1;
const CAP_TCP4_REDIRECT: u64 = 1 << 0;
const CAP_TCP6_REDIRECT: u64 = 1 << 1;
const CAP_UDP4_REDIRECT: u64 = 1 << 2;
const CAP_UDP6_REDIRECT: u64 = 1 << 3;
const CAP_DNS_CAPTURED: u64 = 1 << 4;
const CAP_QUIC_CAPTURED: u64 = 1 << 5;
const CAP_REDIRECT_LOOP_PROTECTED: u64 = 1 << 6;
const CAP_PERSISTENT_FAIL_CLOSED: u64 = 1 << 7;
const KNOWN_CAPABILITIES: u64 = CAP_TCP4_REDIRECT
    | CAP_TCP6_REDIRECT
    | CAP_UDP4_REDIRECT
    | CAP_UDP6_REDIRECT
    | CAP_DNS_CAPTURED
    | CAP_QUIC_CAPTURED
    | CAP_REDIRECT_LOOP_PROTECTED
    | CAP_PERSISTENT_FAIL_CLOSED;

const fn ctl_code(function: u32) -> u32 {
    (FILE_DEVICE_NETWORK << 16) | (FILE_READ_WRITE_ACCESS << 14) | (function << 2) | METHOD_BUFFERED
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowsDriverIoctlDeadline(Duration);

impl WindowsDriverIoctlDeadline {
    pub fn new(value: Duration) -> Result<Self> {
        if value.is_zero() || value > MAX_IOCTL_DEADLINE {
            bail!("strict driver IOCTL deadline is invalid");
        }
        Ok(Self(value))
    }
}

impl Default for WindowsDriverIoctlDeadline {
    fn default() -> Self {
        Self(Duration::from_secs(5))
    }
}

pub struct WindowsIoctlDriverChannel {
    device: OwnedHandle,
    _driver_trust: WindowsDriverTrustLease,
    deadline: WindowsDriverIoctlDeadline,
}

impl WindowsIoctlDriverChannel {
    pub fn open(
        driver_path: impl AsRef<Path>,
        expected_publisher_certificate_sha256: &str,
    ) -> Result<Self> {
        Self::open_with_deadline(
            driver_path,
            expected_publisher_certificate_sha256,
            WindowsDriverIoctlDeadline::default(),
        )
    }

    pub fn open_with_deadline(
        driver_path: impl AsRef<Path>,
        expected_publisher_certificate_sha256: &str,
        deadline: WindowsDriverIoctlDeadline,
    ) -> Result<Self> {
        WindowsDriverIoctlDeadline::new(deadline.0)?;
        let driver_trust =
            verify_windows_driver(driver_path, expected_publisher_certificate_sha256)?;
        let path = wide(DEVICE_PATH);
        // SAFETY: path is NUL-terminated and no optional pointers are supplied.
        let device = unsafe {
            CreateFileW(
                path.as_ptr(),
                GENERIC_READ | GENERIC_WRITE,
                0,
                null(),
                OPEN_EXISTING,
                FILE_FLAG_OVERLAPPED,
                null_mut(),
            )
        };
        if device == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error()).context("open strict callout device");
        }
        // SAFETY: CreateFileW returned a unique owned handle.
        let device = unsafe { OwnedHandle::from_raw_handle(device) };
        Ok(Self {
            device,
            _driver_trust: driver_trust,
            deadline,
        })
    }

    fn issue(&self, code: u32, input: &[u8]) -> Result<WindowsDriverPolicySnapshot> {
        if input.len() > MAX_DRIVER_POLICY_WIRE_BYTES {
            bail!("strict driver IOCTL input exceeds its size limit");
        }
        let mut output = [0_u8; SNAPSHOT_BYTES];
        let transferred = run_overlapped_ioctl(
            self.device.as_raw_handle(),
            code,
            input,
            &mut output,
            self.deadline.0,
        )?;
        if transferred as usize != output.len() {
            bail!("strict driver returned a truncated policy snapshot");
        }
        let mut snapshot = decode_snapshot(&output)?;
        if snapshot.loaded {
            snapshot.capabilities.insert(StrictCapability::DriverSigned);
        }
        Ok(snapshot)
    }
}

impl WindowsDriverPolicyChannel for WindowsIoctlDriverChannel {
    fn upload(&mut self, plan: &WfpPolicyPlan) -> Result<()> {
        let wire = encode_policy(plan)?;
        let snapshot = self.issue(IOCTL_UPLOAD_POLICY, &wire)?;
        validate_upload_response(plan, &snapshot)
    }

    fn unload(&mut self) -> Result<()> {
        let snapshot = self.issue(IOCTL_UNLOAD_POLICY, &[])?;
        if snapshot.loaded || snapshot.revision.is_some() || snapshot.policy_digest.is_some() {
            bail!("strict driver retained policy state after unload");
        }
        Ok(())
    }

    fn snapshot(&mut self) -> Result<WindowsDriverPolicySnapshot> {
        self.issue(IOCTL_QUERY_POLICY, &[])
    }
}

fn encode_policy(plan: &WfpPolicyPlan) -> Result<Vec<u8>> {
    if plan.rules().is_empty() || plan.rules().len() > MAX_DRIVER_RULES {
        bail!("strict driver policy rule count is invalid");
    }
    let target_group_count = u32::try_from(plan.target_groups().len())
        .context("strict driver target-group count exceeds the wire format")?;
    let rule_count = u32::try_from(plan.rules().len())
        .context("strict driver rule count exceeds the wire format")?;
    let mut rules = Vec::with_capacity(plan.rules().len() * POLICY_RULE_BYTES);
    let mut app_ids = Vec::new();
    for rule in plan.rules() {
        let app_offset = u32::try_from(app_ids.len())
            .context("strict driver App-ID offset exceeds the wire format")?;
        let app_length = u32::try_from(rule.app_id().len())
            .context("strict driver App-ID length exceeds the wire format")?;
        if app_length == 0 {
            bail!("strict driver policy contains an empty App-ID");
        }
        app_ids.extend_from_slice(rule.app_id());
        put_u16(&mut rules, rule.family_index());
        rules.push(rule.member_index());
        rules.push(match rule.action() {
            StrictAction::Proxy => 1,
            StrictAction::Block => 2,
        });
        put_u16(&mut rules, rule.target_group_index().unwrap_or(u16::MAX));
        put_u16(&mut rules, 0);
        put_u32(&mut rules, app_offset);
        put_u32(&mut rules, app_length);
    }
    let rules_offset = POLICY_HEADER_BYTES;
    let app_ids_offset = rules_offset
        .checked_add(rules.len())
        .ok_or_else(|| anyhow::anyhow!("strict driver policy size overflow"))?;
    let total_bytes = app_ids_offset
        .checked_add(app_ids.len())
        .ok_or_else(|| anyhow::anyhow!("strict driver policy size overflow"))?;
    if total_bytes > MAX_DRIVER_POLICY_WIRE_BYTES {
        bail!("strict driver policy exceeds its wire size limit");
    }
    let policy_digest = decode_sha256(plan.policy_digest())?;
    let payload_digest = Sha256::new()
        .chain_update(&rules)
        .chain_update(&app_ids)
        .finalize();

    let mut output = vec![0_u8; POLICY_HEADER_BYTES];
    write_u32(&mut output, 0, WIRE_MAGIC);
    write_u16(&mut output, 4, WIRE_PROTOCOL);
    write_u16(&mut output, 6, POLICY_HEADER_BYTES as u16);
    write_u32(&mut output, 8, total_bytes as u32);
    write_u32(&mut output, 12, rule_count);
    write_u32(&mut output, 16, target_group_count);
    write_u64(&mut output, 24, plan.revision());
    output[32..64].copy_from_slice(&policy_digest);
    output[64..96].copy_from_slice(&payload_digest);
    write_u32(&mut output, 96, rules_offset as u32);
    write_u32(&mut output, 100, app_ids_offset as u32);
    write_u32(&mut output, 104, app_ids.len() as u32);
    output.extend_from_slice(&rules);
    output.extend_from_slice(&app_ids);
    debug_assert_eq!(output.len(), total_bytes);
    Ok(output)
}

fn decode_snapshot(bytes: &[u8]) -> Result<WindowsDriverPolicySnapshot> {
    if bytes.len() != SNAPSHOT_BYTES
        || read_u32(bytes, 0)? != WIRE_MAGIC
        || read_u16(bytes, 4)? != WIRE_PROTOCOL
        || read_u16(bytes, 6)? as usize != SNAPSHOT_BYTES
    {
        bail!("strict driver snapshot header is invalid");
    }
    let flags = read_u32(bytes, 8)?;
    if flags & !SNAPSHOT_FLAG_LOADED != 0 {
        bail!("strict driver snapshot contains unknown flags");
    }
    let rule_count = read_u32(bytes, 12)?;
    let generation = read_u64(bytes, 16)?;
    let revision = read_u64(bytes, 24)?;
    let digest = &bytes[32..64];
    let capability_mask = read_u64(bytes, 64)?;
    if capability_mask & !KNOWN_CAPABILITIES != 0 || bytes[72..].iter().any(|value| *value != 0) {
        bail!("strict driver snapshot contains unknown capability or reserved bits");
    }

    let loaded = flags & SNAPSHOT_FLAG_LOADED != 0;
    if loaded {
        if revision == 0
            || generation == 0
            || rule_count == 0
            || rule_count as usize > MAX_DRIVER_RULES
        {
            bail!("loaded strict driver snapshot metadata is invalid");
        }
    } else if revision != 0
        || rule_count != 0
        || digest.iter().any(|value| *value != 0)
        || capability_mask != 0
    {
        bail!("unloaded strict driver snapshot retained active metadata");
    }

    Ok(WindowsDriverPolicySnapshot {
        revision: loaded.then_some(revision),
        policy_digest: loaded.then(|| hex(digest)),
        rule_count: rule_count as usize,
        generation,
        loaded,
        capabilities: decode_capabilities(capability_mask),
    })
}

fn decode_capabilities(mask: u64) -> BTreeSet<StrictCapability> {
    [
        (CAP_TCP4_REDIRECT, StrictCapability::Tcp4Redirect),
        (CAP_TCP6_REDIRECT, StrictCapability::Tcp6Redirect),
        (CAP_UDP4_REDIRECT, StrictCapability::Udp4Redirect),
        (CAP_UDP6_REDIRECT, StrictCapability::Udp6Redirect),
        (CAP_DNS_CAPTURED, StrictCapability::DnsCaptured),
        (CAP_QUIC_CAPTURED, StrictCapability::QuicCaptured),
        (
            CAP_REDIRECT_LOOP_PROTECTED,
            StrictCapability::RedirectLoopProtected,
        ),
        (
            CAP_PERSISTENT_FAIL_CLOSED,
            StrictCapability::PersistentFailClosed,
        ),
    ]
    .into_iter()
    .filter_map(|(bit, capability)| (mask & bit != 0).then_some(capability))
    .collect()
}

fn validate_upload_response(
    plan: &WfpPolicyPlan,
    snapshot: &WindowsDriverPolicySnapshot,
) -> Result<()> {
    if !snapshot.loaded
        || snapshot.revision != Some(plan.revision())
        || snapshot.rule_count != plan.rules().len()
        || snapshot
            .policy_digest
            .as_deref()
            .is_none_or(|digest| !digest.eq_ignore_ascii_case(plan.policy_digest()))
    {
        bail!("strict driver did not attest the uploaded policy wire image");
    }
    Ok(())
}

fn run_overlapped_ioctl(
    handle: *mut c_void,
    code: u32,
    input: &[u8],
    output: &mut [u8],
    timeout: Duration,
) -> Result<u32> {
    WindowsDriverIoctlDeadline::new(timeout)?;
    // SAFETY: no custom security descriptor or name is supplied.
    let event = unsafe { CreateEventW(null(), 1, 0, null()) };
    if event.is_null() {
        return Err(io::Error::last_os_error()).context("create strict driver IOCTL event");
    }
    // SAFETY: CreateEventW returned a unique owned handle.
    let event = unsafe { OwnedHandle::from_raw_handle(event) };
    let mut overlapped = OVERLAPPED {
        hEvent: event.as_raw_handle(),
        ..OVERLAPPED::default()
    };
    let mut immediate_bytes = 0;
    let input_pointer = if input.is_empty() {
        null()
    } else {
        input.as_ptr().cast()
    };
    // SAFETY: input/output and OVERLAPPED remain live until immediate completion
    // or until the pending operation is cancelled and drained below.
    let result = unsafe {
        DeviceIoControl(
            handle,
            code,
            input_pointer,
            input.len() as u32,
            output.as_mut_ptr().cast(),
            output.len() as u32,
            &mut immediate_bytes,
            &mut overlapped,
        )
    };
    if result != 0 {
        return Ok(immediate_bytes);
    }
    let error = io::Error::last_os_error();
    if error.raw_os_error() != Some(ERROR_IO_PENDING as i32) {
        return Err(error).context("start strict driver IOCTL");
    }

    let wait_millis = timeout_to_millis(timeout)?;
    // SAFETY: the event and operation remain live while waiting.
    let wait = unsafe { WaitForSingleObject(event.as_raw_handle(), wait_millis) };
    if wait == WAIT_TIMEOUT {
        cancel_and_drain(handle, &overlapped)?;
        bail!("strict driver IOCTL deadline exceeded");
    }
    if wait != WAIT_OBJECT_0 {
        let wait_error = if wait == WAIT_FAILED {
            io::Error::last_os_error()
        } else {
            io::Error::other(format!("unexpected wait result 0x{wait:08x}"))
        };
        cancel_and_drain(handle, &overlapped)?;
        return Err(wait_error).context("wait for strict driver IOCTL");
    }
    let mut transferred = 0;
    // SAFETY: the event is signalled and OVERLAPPED remains live.
    if unsafe { GetOverlappedResult(handle, &overlapped, &mut transferred, 0) } == 0 {
        return Err(io::Error::last_os_error()).context("complete strict driver IOCTL");
    }
    Ok(transferred)
}

fn cancel_and_drain(handle: *mut c_void, overlapped: &OVERLAPPED) -> Result<()> {
    // SAFETY: OVERLAPPED belongs to a pending operation on this handle.
    let cancel_error = if unsafe { CancelIoEx(handle, overlapped) } == 0 {
        let error = io::Error::last_os_error();
        (error.raw_os_error() != Some(ERROR_NOT_FOUND as i32)).then_some(error)
    } else {
        None
    };
    let mut transferred = 0;
    // SAFETY: waiting here drains completion before caller-owned buffers are dropped.
    let drain_error =
        if unsafe { GetOverlappedResult(handle, overlapped, &mut transferred, 1) } == 0 {
            let error = io::Error::last_os_error();
            (error.raw_os_error() != Some(ERROR_OPERATION_ABORTED as i32)).then_some(error)
        } else {
            None
        };
    if let Some(error) = cancel_error {
        return Err(error).context("cancel strict driver IOCTL");
    }
    if let Some(error) = drain_error {
        return Err(error).context("drain cancelled strict driver IOCTL");
    }
    Ok(())
}

fn timeout_to_millis(timeout: Duration) -> Result<u32> {
    WindowsDriverIoctlDeadline::new(timeout)?;
    let millis = timeout.as_millis();
    let rounded = millis + u128::from(timeout.subsec_nanos() % 1_000_000 != 0);
    u32::try_from(rounded).context("strict driver IOCTL deadline exceeds Windows wait range")
}

fn decode_sha256(value: &str) -> Result<[u8; 32]> {
    if value.len() != 64 {
        bail!("strict driver policy digest is invalid");
    }
    let mut output = [0_u8; 32];
    for (index, pair) in value.as_bytes().chunks_exact(2).enumerate() {
        output[index] = (hex_nibble(pair[0])? << 4) | hex_nibble(pair[1])?;
    }
    Ok(output)
}

fn hex_nibble(value: u8) -> Result<u8> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        b'A'..=b'F' => Ok(value - b'A' + 10),
        _ => bail!("strict driver policy digest is not hexadecimal"),
    }
}

fn hex(value: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(value.len() * 2);
    for byte in value {
        output.push(DIGITS[(byte >> 4) as usize] as char);
        output.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    output
}

fn put_u16(output: &mut Vec<u8>, value: u16) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn put_u32(output: &mut Vec<u8>, value: u32) {
    output.extend_from_slice(&value.to_le_bytes());
}

fn write_u16(output: &mut [u8], offset: usize, value: u16) {
    output[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
}

fn write_u32(output: &mut [u8], offset: usize, value: u32) {
    output[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn write_u64(output: &mut [u8], offset: usize, value: u64) {
    output[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
}

fn read_u16(input: &[u8], offset: usize) -> Result<u16> {
    let value = input
        .get(offset..offset + 2)
        .ok_or_else(|| anyhow::anyhow!("strict driver wire integer is truncated"))?;
    Ok(u16::from_le_bytes(
        value.try_into().expect("two-byte slice"),
    ))
}

fn read_u32(input: &[u8], offset: usize) -> Result<u32> {
    let value = input
        .get(offset..offset + 4)
        .ok_or_else(|| anyhow::anyhow!("strict driver wire integer is truncated"))?;
    Ok(u32::from_le_bytes(
        value.try_into().expect("four-byte slice"),
    ))
}

fn read_u64(input: &[u8], offset: usize) -> Result<u64> {
    let value = input
        .get(offset..offset + 8)
        .ok_or_else(|| anyhow::anyhow!("strict driver wire integer is truncated"))?;
    Ok(u64::from_le_bytes(
        value.try_into().expect("eight-byte slice"),
    ))
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain([0]).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{VerifiedApplicationAppIds, VerifiedPolicyAppIds};
    use flclash_strict_contract::{StrictIdentity, StrictPolicyBundle, StrictPolicyEntry};

    fn plan() -> WfpPolicyPlan {
        let policy = StrictPolicyBundle::new(
            91,
            vec![StrictPolicyEntry::proxy(
                StrictIdentity {
                    identity_id: "10000000-0000-4000-8000-000000000001".into(),
                    canonical_path: r"C:\Apps\DriverWire\app.exe".into(),
                    wfp_app_id_sha256: "a".repeat(64),
                    publisher_certificate_sha256: "b".repeat(64),
                    verified_children: Vec::new(),
                },
                "Proxy-A".into(),
            )],
        )
        .unwrap();
        let verified = VerifiedPolicyAppIds::new(
            &policy,
            vec![VerifiedApplicationAppIds::new(
                "10000000-0000-4000-8000-000000000001",
                vec![vec![1, 2, 3, 4]],
            )
            .unwrap()],
        )
        .unwrap();
        WfpPolicyPlan::new(&policy, &verified).unwrap()
    }

    #[test]
    fn policy_wire_has_bounded_offsets_and_payload_digest() {
        let plan = plan();
        let wire = encode_policy(&plan).unwrap();

        assert_eq!(read_u32(&wire, 0).unwrap(), WIRE_MAGIC);
        assert_eq!(read_u16(&wire, 6).unwrap() as usize, POLICY_HEADER_BYTES);
        assert_eq!(read_u32(&wire, 8).unwrap() as usize, wire.len());
        assert_eq!(read_u32(&wire, 12).unwrap(), 1);
        assert_eq!(read_u64(&wire, 24).unwrap(), 91);
        let rules_offset = read_u32(&wire, 96).unwrap() as usize;
        let app_ids_offset = read_u32(&wire, 100).unwrap() as usize;
        assert_eq!(rules_offset, POLICY_HEADER_BYTES);
        assert_eq!(app_ids_offset, POLICY_HEADER_BYTES + POLICY_RULE_BYTES);
        assert_eq!(&wire[app_ids_offset..], &[1, 2, 3, 4]);
        let payload = Sha256::digest(&wire[rules_offset..]);
        assert_eq!(&wire[64..96], &payload[..]);
    }

    #[test]
    fn driver_snapshot_rejects_unknown_and_unloaded_metadata() {
        let mut snapshot = [0_u8; SNAPSHOT_BYTES];
        write_u32(&mut snapshot, 0, WIRE_MAGIC);
        write_u16(&mut snapshot, 4, WIRE_PROTOCOL);
        write_u16(&mut snapshot, 6, SNAPSHOT_BYTES as u16);
        write_u64(&mut snapshot, 16, 4);
        assert_eq!(decode_snapshot(&snapshot).unwrap().generation, 4);

        write_u64(&mut snapshot, 64, 1 << 63);
        assert!(decode_snapshot(&snapshot).is_err());
        write_u64(&mut snapshot, 64, 0);
        write_u64(&mut snapshot, 24, 9);
        assert!(decode_snapshot(&snapshot).is_err());
    }

    #[test]
    fn loaded_driver_snapshot_maps_only_kernel_owned_capabilities() {
        let mut snapshot = [0_u8; SNAPSHOT_BYTES];
        write_u32(&mut snapshot, 0, WIRE_MAGIC);
        write_u16(&mut snapshot, 4, WIRE_PROTOCOL);
        write_u16(&mut snapshot, 6, SNAPSHOT_BYTES as u16);
        write_u32(&mut snapshot, 8, SNAPSHOT_FLAG_LOADED);
        write_u32(&mut snapshot, 12, 1);
        write_u64(&mut snapshot, 16, 7);
        write_u64(&mut snapshot, 24, 91);
        snapshot[32..64].copy_from_slice(&[0xab; 32]);
        write_u64(
            &mut snapshot,
            64,
            CAP_TCP4_REDIRECT | CAP_PERSISTENT_FAIL_CLOSED,
        );

        let decoded = decode_snapshot(&snapshot).unwrap();
        assert_eq!(decoded.revision, Some(91));
        let expected_digest = "ab".repeat(32);
        assert_eq!(
            decoded.policy_digest.as_deref(),
            Some(expected_digest.as_str())
        );
        assert_eq!(
            decoded.capabilities,
            BTreeSet::from([
                StrictCapability::Tcp4Redirect,
                StrictCapability::PersistentFailClosed,
            ])
        );
        assert!(!decoded
            .capabilities
            .contains(&StrictCapability::IdentityVerified));
        assert!(!decoded
            .capabilities
            .contains(&StrictCapability::RecoveryVerified));
    }

    #[test]
    fn ioctl_deadlines_are_strictly_bounded() {
        assert!(WindowsDriverIoctlDeadline::new(Duration::ZERO).is_err());
        assert!(WindowsDriverIoctlDeadline::new(Duration::from_secs(301)).is_err());
        assert!(WindowsDriverIoctlDeadline::new(Duration::from_millis(1)).is_ok());
    }
}
