use std::collections::{BTreeMap, BTreeSet};
use std::ffi::c_void;
use std::mem::size_of;
use std::net::{Ipv4Addr, SocketAddrV4};
use std::path::Path;
use std::slice;

use anyhow::{bail, Result};
use windows_sys::Win32::Foundation::{ERROR_INSUFFICIENT_BUFFER, NO_ERROR};
use windows_sys::Win32::NetworkManagement::IpHelper::{
    GetExtendedTcpTable, GetExtendedUdpTable, MIB_TCPROW_OWNER_PID, MIB_UDPROW_OWNER_PID,
    TCP_TABLE_OWNER_PID_LISTENER, UDP_TABLE_OWNER_PID,
};
use windows_sys::Win32::Networking::WinSock::AF_INET;

use crate::{
    verify_windows_packaged_core_image, verify_windows_packaged_core_process_with_image,
    StrictPackageManifest, WindowsCoreImageTrustLease, WindowsCoreProcessTrustLease,
};

const MAX_TCP_OWNER_TABLE_BYTES: u32 = 16 * 1024 * 1024;
const MAX_UDP_OWNER_TABLE_BYTES: u32 = 16 * 1024 * 1024;
const MAX_TCP_OWNER_QUERY_ATTEMPTS: usize = 4;
const MAX_UDP_OWNER_QUERY_ATTEMPTS: usize = 4;
const MAX_STRICT_CORE_LISTENERS: usize = 128;

pub struct WindowsCoreListenerTrustLease {
    process: WindowsCoreProcessTrustLease,
    tcp_endpoints: Vec<SocketAddrV4>,
    udp_endpoints: Vec<SocketAddrV4>,
}

impl WindowsCoreListenerTrustLease {
    pub fn process_id(&self) -> u32 {
        self.process.process_id()
    }

    pub fn endpoints(&self) -> &[SocketAddrV4] {
        &self.tcp_endpoints
    }

    pub fn udp_endpoints(&self) -> &[SocketAddrV4] {
        &self.udp_endpoints
    }

    pub fn is_running(&self) -> Result<bool> {
        self.process.is_running()
    }

    pub fn verify_listener_ownership(&self) -> Result<()> {
        if !self.is_running()?
            || windows_tcp_listener_owner_pid_for_all(&self.tcp_endpoints)? != self.process_id()
        {
            bail!("strict Core listener ownership lease is no longer valid");
        }
        if !self.udp_endpoints.is_empty()
            && windows_udp_listener_owner_pid_for_all(&self.udp_endpoints)? != self.process_id()
        {
            bail!("strict Core UDP listener ownership lease is no longer valid");
        }
        Ok(())
    }
}

pub fn windows_tcp_listener_owner_pid(endpoint: SocketAddrV4) -> Result<u32> {
    windows_tcp_listener_owner_pid_for_all(std::slice::from_ref(&endpoint))
}

pub fn windows_tcp_listener_owner_pid_for_all(endpoints: &[SocketAddrV4]) -> Result<u32> {
    if endpoints.is_empty() || endpoints.len() > MAX_STRICT_CORE_LISTENERS {
        bail!("strict Core listener owner query count is invalid");
    }
    if endpoints
        .iter()
        .any(|endpoint| endpoint.ip() != &Ipv4Addr::LOCALHOST || endpoint.port() == 0)
    {
        bail!("strict Core listener owner query requires exact IPv4 loopback");
    }
    let targets: BTreeSet<_> = endpoints.iter().copied().collect();
    if targets.len() != endpoints.len() {
        bail!("strict Core listener owner query contains duplicate endpoints");
    }

    let mut owners = BTreeMap::new();
    for row in query_tcp_listener_rows()? {
        let address = Ipv4Addr::from(row.dwLocalAddr.to_ne_bytes());
        let port = u16::from_be(row.dwLocalPort as u16);
        let endpoint = SocketAddrV4::new(address, port);
        if !targets.contains(&endpoint) {
            continue;
        }
        if row.dwOwningPid == 0 {
            bail!("strict Core listener has no kernel-reported owner PID");
        }
        if owners
            .insert(endpoint, row.dwOwningPid)
            .is_some_and(|existing| existing != row.dwOwningPid)
        {
            bail!("strict Core listener ownership is ambiguous");
        }
    }
    if owners.len() != targets.len() {
        bail!("strict Core listener owner is unavailable");
    }
    let process_ids: BTreeSet<_> = owners.values().copied().collect();
    if process_ids.len() != 1 {
        bail!("strict Core listeners are not owned by one process");
    }
    Ok(*process_ids
        .first()
        .expect("a complete non-empty listener set has an owner"))
}

pub fn windows_udp_listener_owner_pid(endpoint: SocketAddrV4) -> Result<u32> {
    windows_udp_listener_owner_pid_for_all(std::slice::from_ref(&endpoint))
}

pub fn windows_udp_listener_owner_pid_for_all(endpoints: &[SocketAddrV4]) -> Result<u32> {
    validate_owner_query_endpoints(endpoints, "UDP")?;
    let targets: BTreeSet<_> = endpoints.iter().copied().collect();
    let mut owners = BTreeMap::new();
    for row in query_udp_listener_rows()? {
        let address = Ipv4Addr::from(row.dwLocalAddr.to_ne_bytes());
        let port = u16::from_be(row.dwLocalPort as u16);
        let endpoint = SocketAddrV4::new(address, port);
        if !targets.contains(&endpoint) {
            continue;
        }
        if row.dwOwningPid == 0 {
            bail!("strict Core UDP listener has no kernel-reported owner PID");
        }
        if owners
            .insert(endpoint, row.dwOwningPid)
            .is_some_and(|existing| existing != row.dwOwningPid)
        {
            bail!("strict Core UDP listener ownership is ambiguous");
        }
    }
    consistent_owner(&targets, &owners, "UDP")
}

pub fn verify_windows_packaged_core_listener_owner(
    endpoints: &[SocketAddrV4],
    expected_core_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsCoreProcessTrustLease> {
    let image = verify_windows_packaged_core_image(expected_core_path, package)?;
    verify_windows_packaged_core_listener_owner_with_image(endpoints, &image)
}

pub fn verify_windows_packaged_core_listener_owner_with_image(
    endpoints: &[SocketAddrV4],
    image: &WindowsCoreImageTrustLease,
) -> Result<WindowsCoreProcessTrustLease> {
    let process_id = windows_tcp_listener_owner_pid_for_all(endpoints)?;
    let lease = verify_windows_packaged_core_process_with_image(process_id, image)?;
    // Re-read after the process handle is retained. This closes the gap where
    // the original listener could disappear between the table query and
    // OpenProcess; the retained handle then prevents PID reuse.
    if windows_tcp_listener_owner_pid_for_all(endpoints)? != lease.process_id()
        || !lease.is_running()?
    {
        bail!("strict Core listener ownership changed during verification");
    }
    Ok(lease)
}

pub fn verify_windows_packaged_core_listener_set(
    endpoints: &[SocketAddrV4],
    expected_core_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsCoreListenerTrustLease> {
    let image = verify_windows_packaged_core_image(expected_core_path, package)?;
    verify_windows_packaged_core_listener_set_with_image(endpoints, &image)
}

pub fn verify_windows_packaged_core_listener_set_with_image(
    endpoints: &[SocketAddrV4],
    image: &WindowsCoreImageTrustLease,
) -> Result<WindowsCoreListenerTrustLease> {
    let process = verify_windows_packaged_core_listener_owner_with_image(endpoints, image)?;
    Ok(WindowsCoreListenerTrustLease {
        process,
        tcp_endpoints: endpoints.to_vec(),
        udp_endpoints: Vec::new(),
    })
}

pub fn verify_windows_packaged_core_ingress_set(
    tcp_endpoints: &[SocketAddrV4],
    udp_endpoints: &[SocketAddrV4],
    expected_core_path: impl AsRef<Path>,
    package: &StrictPackageManifest,
) -> Result<WindowsCoreListenerTrustLease> {
    let image = verify_windows_packaged_core_image(expected_core_path, package)?;
    verify_windows_packaged_core_ingress_set_with_image(tcp_endpoints, udp_endpoints, &image)
}

pub fn verify_windows_packaged_core_ingress_set_with_image(
    tcp_endpoints: &[SocketAddrV4],
    udp_endpoints: &[SocketAddrV4],
    image: &WindowsCoreImageTrustLease,
) -> Result<WindowsCoreListenerTrustLease> {
    let tcp_process_id = windows_tcp_listener_owner_pid_for_all(tcp_endpoints)?;
    let udp_process_id = windows_udp_listener_owner_pid_for_all(udp_endpoints)?;
    if tcp_process_id != udp_process_id {
        bail!("strict Core TCP and UDP listeners are not owned by one process");
    }
    let process = verify_windows_packaged_core_process_with_image(tcp_process_id, image)?;
    if !process.is_running()?
        || windows_tcp_listener_owner_pid_for_all(tcp_endpoints)? != process.process_id()
        || windows_udp_listener_owner_pid_for_all(udp_endpoints)? != process.process_id()
    {
        bail!("strict Core ingress ownership changed during verification");
    }
    Ok(WindowsCoreListenerTrustLease {
        process,
        tcp_endpoints: tcp_endpoints.to_vec(),
        udp_endpoints: udp_endpoints.to_vec(),
    })
}

fn validate_owner_query_endpoints(endpoints: &[SocketAddrV4], label: &str) -> Result<()> {
    if endpoints.is_empty() || endpoints.len() > MAX_STRICT_CORE_LISTENERS {
        bail!("strict Core {label} listener owner query count is invalid");
    }
    if endpoints
        .iter()
        .any(|endpoint| endpoint.ip() != &Ipv4Addr::LOCALHOST || endpoint.port() == 0)
    {
        bail!("strict Core {label} listener owner query requires exact IPv4 loopback");
    }
    if endpoints.iter().copied().collect::<BTreeSet<_>>().len() != endpoints.len() {
        bail!("strict Core {label} listener owner query contains duplicate endpoints");
    }
    Ok(())
}

fn consistent_owner(
    targets: &BTreeSet<SocketAddrV4>,
    owners: &BTreeMap<SocketAddrV4, u32>,
    label: &str,
) -> Result<u32> {
    if owners.len() != targets.len() {
        bail!("strict Core {label} listener owner is unavailable");
    }
    let process_ids: BTreeSet<_> = owners.values().copied().collect();
    if process_ids.len() != 1 {
        bail!("strict Core {label} listeners are not owned by one process");
    }
    Ok(*process_ids
        .first()
        .expect("a complete non-empty listener set has an owner"))
}

fn query_tcp_listener_rows() -> Result<Vec<MIB_TCPROW_OWNER_PID>> {
    let mut required_bytes = 0_u32;
    // SAFETY: the first call intentionally supplies a null buffer so Windows
    // returns the required byte count in `required_bytes`.
    let first = unsafe {
        GetExtendedTcpTable(
            std::ptr::null_mut(),
            &mut required_bytes,
            0,
            u32::from(AF_INET),
            TCP_TABLE_OWNER_PID_LISTENER,
            0,
        )
    };
    if first != ERROR_INSUFFICIENT_BUFFER && first != NO_ERROR {
        bail!("query strict Core TCP owner table size failed with code {first}");
    }

    for _ in 0..MAX_TCP_OWNER_QUERY_ATTEMPTS {
        if required_bytes < size_of::<u32>() as u32 || required_bytes > MAX_TCP_OWNER_TABLE_BYTES {
            bail!("strict Core TCP owner table size is invalid");
        }
        let words = (required_bytes as usize).div_ceil(size_of::<u32>());
        // A u32 allocation gives the header and every row their required
        // four-byte alignment; a Vec<u8> would not provide that guarantee.
        let mut storage = vec![0_u32; words];
        let mut returned_bytes = required_bytes;
        // SAFETY: `storage` is writable for at least `required_bytes`, aligned
        // for the documented table/row layout, and remains alive for the call.
        let result = unsafe {
            GetExtendedTcpTable(
                storage.as_mut_ptr().cast::<c_void>(),
                &mut returned_bytes,
                0,
                u32::from(AF_INET),
                TCP_TABLE_OWNER_PID_LISTENER,
                0,
            )
        };
        if result == ERROR_INSUFFICIENT_BUFFER {
            required_bytes = returned_bytes;
            continue;
        }
        if result != NO_ERROR {
            bail!("query strict Core TCP owner table failed with code {result}");
        }
        if returned_bytes < size_of::<u32>() as u32
            || returned_bytes as usize > storage.len() * size_of::<u32>()
        {
            bail!("strict Core TCP owner table returned an invalid size");
        }

        let count = storage[0] as usize;
        let available_rows =
            (returned_bytes as usize - size_of::<u32>()) / size_of::<MIB_TCPROW_OWNER_PID>();
        if count > available_rows {
            bail!("strict Core TCP owner table row count is invalid");
        }
        // SAFETY: the checked returned size contains `count` complete rows;
        // storage and the four-byte header preserve MIB row alignment.
        let rows = unsafe {
            let first_row = storage
                .as_ptr()
                .cast::<u8>()
                .add(size_of::<u32>())
                .cast::<MIB_TCPROW_OWNER_PID>();
            slice::from_raw_parts(first_row, count).to_vec()
        };
        return Ok(rows);
    }
    bail!("strict Core TCP owner table changed too frequently")
}

fn query_udp_listener_rows() -> Result<Vec<MIB_UDPROW_OWNER_PID>> {
    let mut required_bytes = 0_u32;
    // SAFETY: the null buffer requests the current table size from Windows.
    let first = unsafe {
        GetExtendedUdpTable(
            std::ptr::null_mut(),
            &mut required_bytes,
            0,
            u32::from(AF_INET),
            UDP_TABLE_OWNER_PID,
            0,
        )
    };
    if first != ERROR_INSUFFICIENT_BUFFER && first != NO_ERROR {
        bail!("query strict Core UDP owner table size failed with code {first}");
    }

    for _ in 0..MAX_UDP_OWNER_QUERY_ATTEMPTS {
        if required_bytes < size_of::<u32>() as u32 || required_bytes > MAX_UDP_OWNER_TABLE_BYTES {
            bail!("strict Core UDP owner table size is invalid");
        }
        let words = (required_bytes as usize).div_ceil(size_of::<u32>());
        let mut storage = vec![0_u32; words];
        let mut returned_bytes = required_bytes;
        // SAFETY: the allocation is aligned and writable for the requested table size.
        let result = unsafe {
            GetExtendedUdpTable(
                storage.as_mut_ptr().cast::<c_void>(),
                &mut returned_bytes,
                0,
                u32::from(AF_INET),
                UDP_TABLE_OWNER_PID,
                0,
            )
        };
        if result == ERROR_INSUFFICIENT_BUFFER {
            required_bytes = returned_bytes;
            continue;
        }
        if result != NO_ERROR {
            bail!("query strict Core UDP owner table failed with code {result}");
        }
        if returned_bytes < size_of::<u32>() as u32
            || returned_bytes as usize > storage.len() * size_of::<u32>()
        {
            bail!("strict Core UDP owner table returned an invalid size");
        }
        let count = storage[0] as usize;
        let available_rows =
            (returned_bytes as usize - size_of::<u32>()) / size_of::<MIB_UDPROW_OWNER_PID>();
        if count > available_rows {
            bail!("strict Core UDP owner table row count is invalid");
        }
        // SAFETY: the checked table size contains every complete UDP owner row.
        let rows = unsafe {
            let first_row = storage
                .as_ptr()
                .cast::<u8>()
                .add(size_of::<u32>())
                .cast::<MIB_UDPROW_OWNER_PID>();
            slice::from_raw_parts(first_row, count).to_vec()
        };
        return Ok(rows);
    }
    bail!("strict Core UDP owner table changed too frequently")
}

#[cfg(test)]
mod tests {
    use std::net::{Ipv4Addr, SocketAddrV4, TcpListener, UdpSocket};

    use super::*;

    #[test]
    fn exact_loopback_listener_is_bound_to_its_kernel_owner_pid() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let endpoint = match listener.local_addr().unwrap() {
            std::net::SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };

        assert_eq!(
            windows_tcp_listener_owner_pid(endpoint).unwrap(),
            std::process::id()
        );
        assert!(windows_tcp_listener_owner_pid(SocketAddrV4::new(
            Ipv4Addr::UNSPECIFIED,
            endpoint.port(),
        ))
        .is_err());
    }

    #[test]
    fn listener_set_is_resolved_by_one_consistent_kernel_owner() {
        let first = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let second = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let endpoints = [
            match first.local_addr().unwrap() {
                std::net::SocketAddr::V4(endpoint) => endpoint,
                _ => unreachable!(),
            },
            match second.local_addr().unwrap() {
                std::net::SocketAddr::V4(endpoint) => endpoint,
                _ => unreachable!(),
            },
        ];

        assert_eq!(
            windows_tcp_listener_owner_pid_for_all(&endpoints).unwrap(),
            std::process::id()
        );
        assert!(windows_tcp_listener_owner_pid_for_all(&[endpoints[0], endpoints[0]]).is_err());
    }

    #[test]
    fn exact_loopback_udp_listener_is_bound_to_its_kernel_owner_pid() {
        let listener = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let endpoint = match listener.local_addr().unwrap() {
            std::net::SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };

        assert_eq!(
            windows_udp_listener_owner_pid(endpoint).unwrap(),
            std::process::id()
        );
        assert!(windows_udp_listener_owner_pid(SocketAddrV4::new(
            Ipv4Addr::UNSPECIFIED,
            endpoint.port(),
        ))
        .is_err());
    }
}
