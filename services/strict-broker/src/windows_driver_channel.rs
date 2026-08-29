use std::collections::BTreeSet;
use std::ffi::c_void;
use std::io;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddrV4, SocketAddrV6};
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::Path;
use std::ptr::{null, null_mut};
use std::sync::{Arc, Mutex, MutexGuard};
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

use crate::windows_driver_service::{verify_windows_driver_service, WindowsDriverServiceLease};
use crate::{
    verify_windows_packaged_driver, StrictPackageManifest, WfpPolicyPlan,
    WindowsDriverEndpointLeaseSnapshot, WindowsDriverPolicyChannel, WindowsDriverPolicySnapshot,
    WindowsDriverTrustLease,
};

const DEVICE_PATH: &str = r"\\.\FlClashStrict";
const DRIVER_SERVICE_NAME: &str = "FlClashStrictCallout";
const WIRE_MAGIC: u32 = u32::from_le_bytes(*b"FCXS");
const WIRE_PROTOCOL: u16 = 2;
const POLICY_HEADER_BYTES: usize = 112;
const POLICY_RULE_BYTES: usize = 16;
const ENDPOINT_LEASE_BYTES: usize = 160;
const ENDPOINT_BYTES: usize = 20;
const SNAPSHOT_BYTES: usize = 128;
const MAX_DRIVER_POLICY_WIRE_BYTES: usize = 3 * 1024 * 1024;
const MAX_DRIVER_RULES: usize = MAX_STRICT_APPLICATIONS * 33;
const MAX_IOCTL_DEADLINE: Duration = Duration::from_secs(300);

const FILE_DEVICE_NETWORK: u32 = 0x12;
const METHOD_BUFFERED: u32 = 0;
const FILE_READ_WRITE_ACCESS: u32 = 3;
const IOCTL_UPLOAD_POLICY: u32 = ctl_code(0x900);
const IOCTL_UNLOAD_POLICY: u32 = ctl_code(0x901);
const IOCTL_QUERY_POLICY: u32 = ctl_code(0x902);
const IOCTL_ACTIVATE_LEASE: u32 = ctl_code(0x903);
const IOCTL_REVOKE_LEASE: u32 = ctl_code(0x904);

const SNAPSHOT_FLAG_LOADED: u32 = 1;
const SNAPSHOT_FLAG_LEASE_ACTIVE: u32 = 1 << 1;
const MIN_LEASE_MILLIS: u32 = 1_000;
const MAX_LEASE_MILLIS: u32 = 30_000;
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowsEndpointLease {
    revision: u64,
    policy_digest: [u8; 32],
    nonce: [u8; 16],
    ttl_millis: u32,
    tcp_v4: SocketAddrV4,
    tcp_v6: SocketAddrV6,
    udp_v4: SocketAddrV4,
    udp_v6: SocketAddrV6,
}

impl WindowsEndpointLease {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        revision: u64,
        policy_digest: &str,
        nonce: [u8; 16],
        ttl: Duration,
        tcp_v4: SocketAddrV4,
        tcp_v6: SocketAddrV6,
        udp_v4: SocketAddrV4,
        udp_v6: SocketAddrV6,
    ) -> Result<Self> {
        let ttl_millis = u32::try_from(ttl.as_millis())
            .context("strict endpoint lease TTL exceeds its wire format")?;
        let policy_digest = decode_sha256(policy_digest)?;
        if revision == 0
            || policy_digest.iter().all(|byte| *byte == 0)
            || nonce.iter().all(|byte| *byte == 0)
            || !(MIN_LEASE_MILLIS..=MAX_LEASE_MILLIS).contains(&ttl_millis)
            || Duration::from_millis(u64::from(ttl_millis)) != ttl
            || tcp_v4.ip() != &Ipv4Addr::LOCALHOST
            || udp_v4.ip() != &Ipv4Addr::LOCALHOST
            || tcp_v6.ip() != &Ipv6Addr::LOCALHOST
            || udp_v6.ip() != &Ipv6Addr::LOCALHOST
            || [tcp_v4.port(), tcp_v6.port(), udp_v4.port(), udp_v6.port()].contains(&0)
        {
            bail!("strict endpoint lease is invalid");
        }
        Ok(Self {
            revision,
            policy_digest,
            nonce,
            ttl_millis,
            tcp_v4,
            tcp_v6,
            udp_v4,
            udp_v6,
        })
    }

    fn encode(&self) -> Vec<u8> {
        let mut output = vec![0_u8; ENDPOINT_LEASE_BYTES];
        write_u32(&mut output, 0, WIRE_MAGIC);
        write_u16(&mut output, 4, WIRE_PROTOCOL);
        write_u16(&mut output, 6, ENDPOINT_LEASE_BYTES as u16);
        write_u32(&mut output, 8, self.ttl_millis);
        write_u64(&mut output, 16, self.revision);
        output[24..56].copy_from_slice(&self.policy_digest);
        output[56..72].copy_from_slice(&self.nonce);
        encode_v4_endpoint(&mut output[72..72 + ENDPOINT_BYTES], self.tcp_v4);
        encode_v6_endpoint(&mut output[92..92 + ENDPOINT_BYTES], self.tcp_v6);
        encode_v4_endpoint(&mut output[112..112 + ENDPOINT_BYTES], self.udp_v4);
        encode_v6_endpoint(&mut output[132..132 + ENDPOINT_BYTES], self.udp_v6);
        output
    }
}

pub struct WindowsIoctlDriverChannel {
    device: OwnedHandle,
    _driver_trust: WindowsDriverTrustLease,
    _driver_service: WindowsDriverServiceLease,
    deadline: WindowsDriverIoctlDeadline,
    expected_driver_build_id: String,
}

#[derive(Clone)]
pub struct WindowsSharedIoctlDriverChannel {
    inner: Arc<Mutex<WindowsIoctlDriverChannel>>,
}

impl WindowsSharedIoctlDriverChannel {
    pub fn open(driver_path: impl AsRef<Path>, package: &StrictPackageManifest) -> Result<Self> {
        Ok(Self {
            inner: Arc::new(Mutex::new(WindowsIoctlDriverChannel::open(
                driver_path,
                package,
            )?)),
        })
    }

    fn lock(&self) -> Result<MutexGuard<'_, WindowsIoctlDriverChannel>> {
        self.inner
            .lock()
            .map_err(|_| anyhow::anyhow!("strict driver channel lock is poisoned"))
    }

    pub fn activate_endpoint_lease(
        &self,
        lease: &WindowsEndpointLease,
    ) -> Result<WindowsDriverPolicySnapshot> {
        self.lock()?.activate_endpoint_lease(lease)
    }

    pub fn revoke_endpoint_lease(&self) -> Result<WindowsDriverPolicySnapshot> {
        self.lock()?.revoke_endpoint_lease()
    }
}

impl WindowsIoctlDriverChannel {
    pub fn open(driver_path: impl AsRef<Path>, package: &StrictPackageManifest) -> Result<Self> {
        Self::open_with_deadline(driver_path, package, WindowsDriverIoctlDeadline::default())
    }

    pub fn open_with_deadline(
        driver_path: impl AsRef<Path>,
        package: &StrictPackageManifest,
        deadline: WindowsDriverIoctlDeadline,
    ) -> Result<Self> {
        WindowsDriverIoctlDeadline::new(deadline.0)?;
        let driver_trust = verify_windows_packaged_driver(
            driver_path,
            package.driver_file_sha256(),
            package.driver_publisher_certificate_sha256(),
        )?;
        let driver_service =
            verify_windows_driver_service(DRIVER_SERVICE_NAME, driver_trust.canonical_path())?;
        let expected_driver_build_id = canonical_build_id(package.driver_build_id())?;
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
        let channel = Self {
            device,
            _driver_trust: driver_trust,
            _driver_service: driver_service,
            deadline,
            expected_driver_build_id,
        };
        channel
            .issue(IOCTL_QUERY_POLICY, &[])
            .context("attest strict callout device at open")?;
        Ok(channel)
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
        if snapshot.driver_build_id.as_deref() != Some(self.expected_driver_build_id.as_str()) {
            bail!("strict driver device build identity does not match the signed package");
        }
        if snapshot.loaded {
            snapshot.capabilities.insert(StrictCapability::DriverSigned);
        }
        Ok(snapshot)
    }

    pub fn activate_endpoint_lease(
        &self,
        lease: &WindowsEndpointLease,
    ) -> Result<WindowsDriverPolicySnapshot> {
        let snapshot = self.issue(IOCTL_ACTIVATE_LEASE, &lease.encode())?;
        let expected_digest = hex(&lease.policy_digest);
        if !snapshot.loaded
            || snapshot.revision != Some(lease.revision)
            || snapshot.policy_digest.as_deref() != Some(expected_digest.as_str())
            || snapshot.endpoint_lease.as_ref().is_none_or(|active| {
                active.nonce != lease.nonce
                    || active.generation == 0
                    || active.remaining_millis == 0
                    || active.remaining_millis > lease.ttl_millis
            })
        {
            bail!("strict driver did not attest the endpoint lease");
        }
        Ok(snapshot)
    }

    pub fn revoke_endpoint_lease(&self) -> Result<WindowsDriverPolicySnapshot> {
        let snapshot = self.issue(IOCTL_REVOKE_LEASE, &[])?;
        if snapshot.endpoint_lease.is_some() {
            bail!("strict driver retained endpoint lease state after revocation");
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

impl WindowsDriverPolicyChannel for WindowsSharedIoctlDriverChannel {
    fn upload(&mut self, plan: &WfpPolicyPlan) -> Result<()> {
        self.lock()?.upload(plan)
    }

    fn unload(&mut self) -> Result<()> {
        self.lock()?.unload()
    }

    fn snapshot(&mut self) -> Result<WindowsDriverPolicySnapshot> {
        self.lock()?.snapshot()
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
    if flags & !(SNAPSHOT_FLAG_LOADED | SNAPSHOT_FLAG_LEASE_ACTIVE) != 0 {
        bail!("strict driver snapshot contains unknown flags");
    }
    let rule_count = read_u32(bytes, 12)?;
    let generation = read_u64(bytes, 16)?;
    let revision = read_u64(bytes, 24)?;
    let digest = &bytes[32..64];
    let capability_mask = read_u64(bytes, 64)?;
    let driver_build_id = &bytes[72..88];
    let lease_generation = read_u64(bytes, 88)?;
    let lease_remaining_millis = read_u32(bytes, 96)?;
    let lease_nonce: [u8; 16] = bytes[104..120].try_into().expect("lease nonce slice");
    if capability_mask & !KNOWN_CAPABILITIES != 0
        || driver_build_id.iter().all(|value| *value == 0)
        || bytes[100..104].iter().any(|value| *value != 0)
        || bytes[120..].iter().any(|value| *value != 0)
    {
        bail!("strict driver snapshot contains unknown capability or reserved bits");
    }

    let loaded = flags & SNAPSHOT_FLAG_LOADED != 0;
    let lease_active = flags & SNAPSHOT_FLAG_LEASE_ACTIVE != 0;
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
    let endpoint_lease = if lease_active {
        if !loaded
            || lease_generation == 0
            || lease_remaining_millis == 0
            || lease_remaining_millis > MAX_LEASE_MILLIS
            || lease_nonce.iter().all(|value| *value == 0)
        {
            bail!("active strict endpoint lease metadata is invalid");
        }
        Some(WindowsDriverEndpointLeaseSnapshot {
            generation: lease_generation,
            remaining_millis: lease_remaining_millis,
            nonce: lease_nonce,
        })
    } else {
        if lease_generation != 0
            || lease_remaining_millis != 0
            || lease_nonce.iter().any(|value| *value != 0)
        {
            bail!("inactive strict endpoint lease retained metadata");
        }
        None
    };

    Ok(WindowsDriverPolicySnapshot {
        driver_build_id: Some(hex(driver_build_id)),
        revision: loaded.then_some(revision),
        policy_digest: loaded.then(|| hex(digest)),
        rule_count: rule_count as usize,
        generation,
        loaded,
        capabilities: decode_capabilities(capability_mask),
        endpoint_lease,
    })
}

fn encode_v4_endpoint(output: &mut [u8], endpoint: SocketAddrV4) {
    debug_assert_eq!(output.len(), ENDPOINT_BYTES);
    output[..4].copy_from_slice(&endpoint.ip().octets());
    write_u16(output, 16, endpoint.port());
}

fn encode_v6_endpoint(output: &mut [u8], endpoint: SocketAddrV6) {
    debug_assert_eq!(output.len(), ENDPOINT_BYTES);
    output[..16].copy_from_slice(&endpoint.ip().octets());
    write_u16(output, 16, endpoint.port());
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

fn canonical_build_id(value: &str) -> Result<String> {
    if value.len() != 32 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("strict driver build identity is invalid");
    }
    Ok(value.to_ascii_lowercase())
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

    fn assert_send_sync<T: Send + Sync>() {}

    #[test]
    fn shared_driver_channel_is_safe_to_serialize_across_runtime_threads() {
        assert_send_sync::<WindowsSharedIoctlDriverChannel>();
    }
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
        snapshot[72..88].copy_from_slice(&[0xcd; 16]);
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
        snapshot[72..88].copy_from_slice(&[0xcd; 16]);
        write_u64(
            &mut snapshot,
            64,
            CAP_TCP4_REDIRECT | CAP_PERSISTENT_FAIL_CLOSED,
        );

        let decoded = decode_snapshot(&snapshot).unwrap();
        let expected_build_id = "cd".repeat(16);
        assert_eq!(
            decoded.driver_build_id.as_deref(),
            Some(expected_build_id.as_str())
        );
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
        assert!(decoded.endpoint_lease.is_none());
    }

    #[test]
    fn endpoint_lease_wire_is_loopback_only_and_snapshot_bound() {
        let digest = "ab".repeat(32);
        let lease = WindowsEndpointLease::new(
            91,
            &digest,
            [0x5a; 16],
            Duration::from_secs(5),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41001),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 41002, 0, 0),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41003),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 41004, 0, 0),
        )
        .unwrap();
        let wire = lease.encode();
        assert_eq!(wire.len(), ENDPOINT_LEASE_BYTES);
        assert_eq!(read_u16(&wire, 4).unwrap(), WIRE_PROTOCOL);
        assert_eq!(read_u16(&wire, 6).unwrap() as usize, ENDPOINT_LEASE_BYTES);
        assert_eq!(read_u32(&wire, 8).unwrap(), 5_000);
        assert_eq!(read_u64(&wire, 16).unwrap(), 91);
        assert_eq!(&wire[24..56], &[0xab; 32]);
        assert_eq!(&wire[56..72], &[0x5a; 16]);
        assert_eq!(&wire[72..76], &Ipv4Addr::LOCALHOST.octets());
        assert!(wire[76..88].iter().all(|value| *value == 0));
        assert_eq!(read_u16(&wire, 88).unwrap(), 41001);
        assert_eq!(&wire[92..108], &Ipv6Addr::LOCALHOST.octets());
        assert_eq!(read_u16(&wire, 108).unwrap(), 41002);
        assert!(wire[152..].iter().all(|value| *value == 0));

        let mut snapshot = [0_u8; SNAPSHOT_BYTES];
        write_u32(&mut snapshot, 0, WIRE_MAGIC);
        write_u16(&mut snapshot, 4, WIRE_PROTOCOL);
        write_u16(&mut snapshot, 6, SNAPSHOT_BYTES as u16);
        write_u32(
            &mut snapshot,
            8,
            SNAPSHOT_FLAG_LOADED | SNAPSHOT_FLAG_LEASE_ACTIVE,
        );
        write_u32(&mut snapshot, 12, 1);
        write_u64(&mut snapshot, 16, 7);
        write_u64(&mut snapshot, 24, 91);
        snapshot[32..64].copy_from_slice(&[0xab; 32]);
        snapshot[72..88].copy_from_slice(&[0xcd; 16]);
        write_u64(&mut snapshot, 88, 3);
        write_u32(&mut snapshot, 96, 4_999);
        snapshot[104..120].copy_from_slice(&[0x5a; 16]);
        let decoded = decode_snapshot(&snapshot).unwrap();
        assert_eq!(
            decoded.endpoint_lease,
            Some(WindowsDriverEndpointLeaseSnapshot {
                generation: 3,
                remaining_millis: 4_999,
                nonce: [0x5a; 16],
            })
        );

        assert!(WindowsEndpointLease::new(
            91,
            &"00".repeat(32),
            [1; 16],
            Duration::from_secs(5),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 1),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 2, 0, 0),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 3),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 4, 0, 0),
        )
        .is_err());
        assert!(WindowsEndpointLease::new(
            91,
            &digest,
            [0; 16],
            Duration::from_secs(5),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 1),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 2, 0, 0),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 3),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 4, 0, 0),
        )
        .is_err());
        assert!(WindowsEndpointLease::new(
            91,
            &digest,
            [1; 16],
            Duration::from_secs(5),
            SocketAddrV4::new(Ipv4Addr::new(127, 0, 0, 2), 1),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 2, 0, 0),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 3),
            SocketAddrV6::new(Ipv6Addr::LOCALHOST, 4, 0, 0),
        )
        .is_err());
    }

    #[test]
    fn ioctl_deadlines_are_strictly_bounded() {
        assert!(WindowsDriverIoctlDeadline::new(Duration::ZERO).is_err());
        assert!(WindowsDriverIoctlDeadline::new(Duration::from_secs(301)).is_err());
        assert!(WindowsDriverIoctlDeadline::new(Duration::from_millis(1)).is_ok());
    }

    #[test]
    fn package_build_identity_is_exact_and_case_normalized() {
        assert_eq!(
            canonical_build_id("ABCDEF0123456789ABCDEF0123456789").unwrap(),
            "abcdef0123456789abcdef0123456789"
        );
        assert!(canonical_build_id("00").is_err());
        assert!(canonical_build_id("g0000000000000000000000000000000").is_err());
    }

    #[test]
    fn kernel_header_tracks_the_rust_wire_contract() {
        let header = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/include/flclash_strict_wire.h"
        ));
        for declaration in [
            "0x53584346u",
            "FCX_STRICT_WIRE_PROTOCOL ((UINT16)2u)",
            "FCX_STRICT_POLICY_HEADER_BYTES ((UINT16)112u)",
            "FCX_STRICT_POLICY_RULE_BYTES ((UINT16)16u)",
            "FCX_STRICT_ENDPOINT_LEASE_BYTES ((UINT16)160u)",
            "FCX_STRICT_ENDPOINT_BYTES ((UINT16)20u)",
            "FCX_STRICT_SNAPSHOT_BYTES ((UINT16)128u)",
            "UINT8 DriverBuildId[16]",
            "UINT64 LeaseGeneration",
            "IOCTL_FCX_STRICT_UPLOAD_POLICY",
            "IOCTL_FCX_STRICT_UNLOAD_POLICY",
            "IOCTL_FCX_STRICT_QUERY_POLICY",
            "IOCTL_FCX_STRICT_ACTIVATE_LEASE",
            "IOCTL_FCX_STRICT_REVOKE_LEASE",
        ] {
            assert!(
                header.contains(declaration),
                "missing ABI declaration: {declaration}"
            );
        }
    }

    #[test]
    fn kernel_sources_preserve_the_fail_closed_capability_boundary() {
        let driver = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/src/driver.c"
        ));
        let policy = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/src/policy.c"
        ));
        let project = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/FlClashStrictCallout.vcxproj"
        ));

        for declaration in [
            "D:P(A;;GA;;;SY)",
            "WdfIoQueueDispatchSequential",
            "WdfExecutionLevelPassive",
            "ExAcquireRundownProtectionCacheAware",
            "FcxStrictPolicyFind",
            "ClassifyOut->actionType = FWP_ACTION_BLOCK",
            "Output->Capabilities = FCX_STRICT_CAP_PERSISTENT_FAIL_CLOSED;",
            "WdfRequestGetRequestorProcessId",
            "PsLookupProcessByProcessId",
            "PsSetCreateProcessNotifyRoutineEx",
            "lease->BrokerProcess == Process",
        ] {
            assert!(
                driver.contains(declaration),
                "missing kernel safety invariant: {declaration}"
            );
        }
        for unavailable_capability in [
            "FCX_STRICT_CAP_TCP4_REDIRECT",
            "FCX_STRICT_CAP_TCP6_REDIRECT",
            "FCX_STRICT_CAP_UDP4_REDIRECT",
            "FCX_STRICT_CAP_UDP6_REDIRECT",
            "FCX_STRICT_CAP_DNS_CAPTURED",
            "FCX_STRICT_CAP_QUIC_CAPTURED",
            "FCX_STRICT_CAP_REDIRECT_LOOP_PROTECTED",
        ] {
            assert!(
                !driver.contains(unavailable_capability),
                "driver advertised an unavailable capability: {unavailable_capability}"
            );
        }
        for deprecated_allocator in ["ExAllocatePool(", "ExAllocatePoolWithTag("] {
            assert!(
                !driver.contains(deprecated_allocator) && !policy.contains(deprecated_allocator),
                "deprecated kernel allocator used: {deprecated_allocator}"
            );
        }
        assert!(!driver.contains("WdfObjectDelete("));
        assert!(project.contains("/INTEGRITYCHECK"));
        assert!(project.contains("<KMDF_VERSION_MINOR>21</KMDF_VERSION_MINOR>"));
        assert!(policy.contains("ExAllocatePool2("));
        assert!(policy.contains("POOL_FLAG_NON_PAGED"));
    }

    #[test]
    fn kernel_callouts_expose_redirect_context_and_own_the_redirect_handle() {
        let driver = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/src/driver.c"
        ));

        for declaration in [
            "static const GUID FcxProviderKey",
            "static HANDLE FcxRedirectHandle",
            "_In_opt_ const VOID *ClassifyContext",
            "_In_ const FWPS_FILTER1 *Filter",
            "FWPS_CALLOUT1 callout",
            "FWPS_CALLOUT_CLASSIFY_FN1 classifyFunctions[4]",
            "FwpsCalloutRegister1(",
            "FwpsRedirectHandleCreate0(&FcxProviderKey",
            "FwpsRedirectHandleDestroy0(FcxRedirectHandle)",
        ] {
            assert!(
                driver.contains(declaration),
                "missing redirect lifecycle invariant: {declaration}"
            );
        }
        for obsolete_api in [
            "FWPS_CALLOUT0 callout",
            "FWPS_CALLOUT_CLASSIFY_FN0",
            "FwpsCalloutRegister0(",
        ] {
            assert!(
                !driver.contains(obsolete_api),
                "obsolete callout API still present: {obsolete_api}"
            );
        }
    }

    #[test]
    fn kernel_tcp_redirect_is_lease_bound_loop_safe_and_inline() {
        let driver = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/src/driver.c"
        ));

        for invariant in [
            "FcxClassifyTcpRedirect(",
            "FcxClassifyRedirectedTcpGuard(",
            "FWP_CONDITION_FLAG_IS_CONNECTION_REDIRECTED",
            "FWPS_METADATA_FIELD_LOCAL_REDIRECT_TARGET_PID",
            "FWPS_METADATA_FIELD_ORIGINAL_DESTINATION",
            "FwpsQueryConnectionRedirectState0(",
            "FWPS_CONNECTION_REDIRECTED_BY_SELF",
            "FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF",
            "FwpsAcquireClassifyHandle0(",
            "FwpsAcquireWritableLayerDataPointer0(",
            "FwpsApplyModifiedLayerData0(classifyHandle, writableRequest, 0)",
            "FwpsReleaseClassifyHandle0(classifyHandle)",
            "ExAllocatePool2(POOL_FLAG_NON_PAGED",
            "connectRequest->localRedirectTargetPID",
            "connectRequest->localRedirectHandle = FcxRedirectHandle",
            "connectRequest->localRedirectContext = redirectContext",
            "rule->Action == FCX_STRICT_ACTION_PROXY",
            "Lease->ExpiresAtInterruptTime > KeQueryInterruptTime()",
            "Context->TargetGroupIndex = Rule->TargetGroupIndex",
            "Context->IpProtocol = IPPROTO_TCP",
        ] {
            assert!(
                driver.contains(invariant),
                "missing TCP redirect invariant: {invariant}"
            );
        }
    }
}
