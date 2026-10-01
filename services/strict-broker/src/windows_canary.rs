//! Activation canaries run in a private child of the signed Broker. The child
//! receives no ingress password. Only the parent evaluates kernel/relay proof.
use std::io::{Read, Write};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, Shutdown, SocketAddr, TcpStream, UdpSocket};
use std::process::{Child, Command, Stdio};
use std::os::windows::process::CommandExt;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};
use anyhow::{bail, Context, Result};
use flclash_strict_contract::StrictProxyIngressSet;
use crate::{StrictPackageManifest, WindowsSharedIoctlDriverChannel};
use crate::windows_core_udp_health::{probe_core_dns_mapping, confirm_core_dns_restoration};
use crate::windows_wfp_engine::WindowsCanaryFilters;

const TIMEOUT: Duration = Duration::from_secs(2);
const CHILD_TIMEOUT: Duration = Duration::from_secs(25);

#[derive(Debug)]
pub(crate) enum CanaryFailure { DnsMapping, DnsRestoration, Network, Timeout }
impl std::fmt::Display for CanaryFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::DnsMapping => "strict DNS mapping could not be obtained",
            Self::DnsRestoration => "Core did not prove DNS domain restoration",
            Self::Network => "scoped WFP TCP, DNS or QUIC forwarding canary failed",
            Self::Timeout => "strict forwarding canary exceeded its time budget",
        })
    }
}
impl std::error::Error for CanaryFailure {}

struct ChildLease(Child);
impl Drop for ChildLease {
    fn drop(&mut self) { let _ = self.0.kill(); let _ = self.0.wait(); }
}

pub(crate) fn run_canaries(driver: &WindowsSharedIoctlDriverChannel, package: &StrictPackageManifest,
    revision: u64, digest: &str, nonce: [u8;16], ingress: &StrictProxyIngressSet,
    relayed: &AtomicUsize, canary_pid: &AtomicUsize) -> Result<()> {
    let executable = std::env::current_exe()?;
    // Retain a handle denying write/delete until all children have exited.
    let (identity, app_id, _image_lock) = crate::windows_identity::inspect_and_lock(&executable)?;
    if !identity.publisher_certificate_sha256.eq_ignore_ascii_case(package.core_publisher_certificate_sha256()) {
        bail!("strict canary executable publisher does not match package");
    }
    let _filters = WindowsCanaryFilters::install(&app_id, nonce)?;
    let endpoint = ingress.udp_endpoint.context("missing strict Core UDP endpoint")?;
    let overall_deadline = Instant::now() + Duration::from_secs(240);
    for (target, entry) in ingress.entries.iter().enumerate() {
        if Instant::now() >= overall_deadline { return Err(CanaryFailure::Timeout.into()); }
        let mut probe_nonce = nonce;
        probe_nonce[0] ^= target as u8;
        let mapped = probe_core_dns_mapping(endpoint, ingress.generation,
            &entry.username, &entry.password, probe_nonce, TIMEOUT).map_err(|_| CanaryFailure::DnsMapping)?;
        let before = driver.query_policy_snapshot()?;
        let baseline = relayed.load(Ordering::Acquire);
        let mut child = ChildLease(Command::new(&executable).arg("--strict-canary")
            .stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null())
            .creation_flags(0x08000000).spawn().context("start signed strict canary child")?);
        driver.bind_canary(revision, digest, nonce, child.0.id(), u16::try_from(target)?)?;
        canary_pid.store(child.0.id() as usize, Ordering::Release);
        driver.activate_datagram_path()?;
        let challenge = probe_nonce.iter().map(|b| format!("{b:02x}")).collect::<String>();
        let mut input = child.0.stdin.take().context("canary stdin unavailable")?;
        writeln!(input, "{mapped} {challenge}")?;
        drop(input);
        let deadline = (Instant::now() + CHILD_TIMEOUT).min(overall_deadline);
        loop {
            if let Some(status) = child.0.try_wait()? {
                if !status.success() { return Err(CanaryFailure::Network.into()); }
                break;
            }
            if Instant::now() >= deadline { return Err(CanaryFailure::Timeout.into()); }
            std::thread::sleep(Duration::from_millis(20));
        }
        confirm_core_dns_restoration(endpoint, ingress.generation,
            &entry.username, &entry.password, probe_nonce, TIMEOUT).map_err(|_| CanaryFailure::DnsRestoration)?;
        // A successful remote request is not proof: Broker exemptions or a
        // missing callout would let it escape. Require authenticated WFP
        // metadata accepted by the relay and successful kernel UDP injections.
        let deadline = Instant::now() + Duration::from_secs(1);
        loop {
            let after = driver.query_policy_snapshot()?;
            let lease_matches = after.revision == Some(revision)
                && after.policy_digest.as_deref() == Some(digest)
                && after.endpoint_lease.as_ref().map(|v| v.nonce) == Some(nonce);
            if !lease_matches || after.datagram_health.injection_failed != before.datagram_health.injection_failed
                || after.datagram_health.partial_batch_failures != before.datagram_health.partial_batch_failures {
                bail!("strict canary lease or UDP injection evidence failed");
            }
            if relayed.load(Ordering::Acquire).saturating_sub(baseline) >= 3
                && after.datagram_health.injection_succeeded.saturating_sub(before.datagram_health.injection_succeeded) >= 4
                && driver.canary_udp_mask()? == 15 {
                break;
            }
            if Instant::now() >= deadline { return Err(CanaryFailure::Network.into()); }
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    Ok(())
}

/// This mode never reports health itself. It exercises unproxied Winsock calls
/// after the parent has bound its PID to a short-lived kernel lease.
pub fn run_windows_strict_canary_child() -> Result<()> {
    let mut input = String::new();
    std::io::stdin().take(128).read_to_string(&mut input)?;
    let mut fields = input.split_whitespace();
    let mapped: Ipv4Addr = fields.next().context("missing DNS mapping")?.parse()?;
    let nonce = fields.next().context("missing challenge")?;
    if fields.next().is_some() || nonce.len() != 32 || !nonce.bytes().all(|b| b.is_ascii_hexdigit())
        || mapped.is_loopback() || mapped.is_unspecified() || mapped.is_multicast() {
        bail!("invalid canary challenge");
    }
    // These bounded endpoints intentionally do not depend on system DNS.
    let v4 = IpAddr::V4(std::env::var("FCX_STRICT_CANARY_IPV4").unwrap_or_else(|_| "1.1.1.1".into()).parse::<Ipv4Addr>()?);
    let v6 = IpAddr::V6(std::env::var("FCX_STRICT_CANARY_IPV6").unwrap_or_else(|_| "2606:4700:4700::1111".into()).parse::<Ipv6Addr>()?);
    if [v4,v6].iter().any(|ip| ip.is_loopback() || ip.is_unspecified() || ip.is_multicast()) {
        bail!("unsafe configured canary endpoint");
    }
    http_trace(v4, "one.one.one.one")?;
    http_trace(v6, "one.one.one.one")?;
    http_trace(IpAddr::V4(mapped), "www.cloudflare.com")?;
    for ip in [v4,v6] { dns(ip, nonce)?; quic(ip, nonce)?; }
    Ok(())
}

fn http_trace(ip: IpAddr, host: &str) -> Result<()> {
    let mut socket = TcpStream::connect_timeout(&SocketAddr::new(ip,80),TIMEOUT)?;
    socket.set_read_timeout(Some(TIMEOUT))?; socket.set_write_timeout(Some(TIMEOUT))?;
    write!(socket,"GET /cdn-cgi/trace HTTP/1.0\r\nHost: {host}\r\nConnection: close\r\n\r\n")?;
    socket.shutdown(Shutdown::Write)?;
    let mut response=String::new(); socket.take(16*1024).read_to_string(&mut response)?;
    if !response.starts_with("HTTP/1.1 200") && !response.starts_with("HTTP/1.0 200") { bail!("canary HTTP response rejected"); }
    if !response.lines().any(|line| line.strip_prefix("ip=").is_some_and(|ip| ip.parse::<IpAddr>().is_ok())) {
        bail!("canary HTTP trace missing address");
    }
    Ok(())
}

fn udp(ip: IpAddr, port: u16, packet: &[u8]) -> Result<Vec<u8>> {
    let bind = if ip.is_ipv4() { "0.0.0.0:0" } else { "[::]:0" };
    let socket = UdpSocket::bind(bind)?;
    socket.set_read_timeout(Some(TIMEOUT))?; socket.set_write_timeout(Some(TIMEOUT))?;
    socket.connect(SocketAddr::new(ip,port))?;
    if socket.send(packet)? != packet.len() { bail!("truncated canary UDP request"); }
    let mut response=vec![0u8;4096]; let count=socket.recv(&mut response)?; response.truncate(count); Ok(response)
}
fn dns(ip: IpAddr, nonce: &str) -> Result<()> {
    let mut query=vec![0x46,0x43,1,0,0,1,0,0,0,0,0,0];
    for label in [nonce,"example","com"] { query.push(label.len() as u8); query.extend_from_slice(label.as_bytes()); }
    query.extend_from_slice(&[0,0,1,0,1]);
    let response=udp(ip,53,&query)?;
    if response.len()<query.len() || response[..2]!=query[..2] || response[2]&0x80==0
        || response[4..6]!=[0,1] || response[12..query.len()]!=query[12..] {
        bail!("canary DNS reply correlation failed");
    }
    Ok(())
}
fn quic(ip: IpAddr, nonce: &str) -> Result<()> {
    // Reserved version forces RFC 9000 version negotiation without credentials.
    let dcid=&nonce.as_bytes()[..8]; let scid=&nonce.as_bytes()[8..16];
    let mut packet=vec![0xc0,0x0a,0x0a,0x0a,0x0a,8]; packet.extend_from_slice(dcid);
    packet.push(8); packet.extend_from_slice(scid); packet.resize(1200,0);
    let response=udp(ip,443,&packet)?;
    if response.len()<27 || response[0]&0x80==0 || response[1..5]!=[0,0,0,0]
        || response[5]!=8 || response[6..14]!=*scid || response[14]!=8 || response[15..23]!=*dcid
        || (response.len()-23)%4!=0 { bail!("canary QUIC version negotiation correlation failed"); }
    Ok(())
}
