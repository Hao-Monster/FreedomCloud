//! Authenticated control-plane primitives for strict per-application proxying.
//!
#![allow(dead_code)]

//! The WFP callout must not send raw application sockets directly to a
//! Mihomo mixed port: a SOCKS/HTTP handshake and an explicit flow lifetime are
//! required.  This module defines that bounded control plane independently of
//! the driver and keeps all state transitions fail-closed.  It intentionally
//! does not bind a listener or change host networking; the Windows service can
//! embed it when the signed data-plane broker is available.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::timeout;

pub const BROKER_PROTOCOL_VERSION: u32 = 1;
pub const MAX_FRAME_BYTES: usize = 64 * 1024;
pub const MAX_DESTINATION_BYTES: usize = 255;
pub const MAX_PAYLOAD_BYTES: usize = 32 * 1024;
pub const MAX_FLOWS: usize = 4096;
pub const FLOW_IDLE_TIMEOUT: Duration = Duration::from_secs(120);
pub const MIHOMO_CONNECT_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum FlowProtocol {
    Tcp,
    Udp,
    Dns,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum FlowState {
    Opening,
    Established,
    Closing,
    Closed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "type")]
pub enum BrokerFrame {
    Hello {
        protocol: u32,
        token: String,
    },
    Open {
        flow_id: u64,
        process_id: u32,
        protocol: FlowProtocol,
        destination: String,
        mihomo: SocketAddr,
    },
    Opened {
        flow_id: u64,
    },
    Data {
        flow_id: u64,
        payload: Vec<u8>,
    },
    Close {
        flow_id: u64,
    },
    Error {
        flow_id: Option<u64>,
        code: BrokerErrorCode,
    },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BrokerErrorCode {
    Unauthorized,
    ProtocolMismatch,
    InvalidRequest,
    Capacity,
    FlowNotFound,
    ProxyUnavailable,
    Timeout,
    Closed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlowSnapshot {
    pub flow_id: u64,
    pub process_id: u32,
    pub protocol: FlowProtocol,
    pub destination: String,
    pub mihomo: SocketAddr,
    pub state: FlowState,
}

#[derive(Debug)]
struct FlowRecord {
    snapshot: FlowSnapshot,
    last_activity: Instant,
}

#[derive(Debug, Default)]
pub struct FlowRegistry {
    flows: HashMap<u64, FlowRecord>,
}

impl FlowRegistry {
    pub fn len(&self) -> usize {
        self.flows.len()
    }

    pub fn open(
        &mut self,
        flow_id: u64,
        process_id: u32,
        protocol: FlowProtocol,
        destination: &str,
        mihomo: SocketAddr,
        now: Instant,
    ) -> Result<FlowSnapshot, BrokerErrorCode> {
        validate_open(flow_id, process_id, destination, mihomo)?;
        if self.flows.len() >= MAX_FLOWS && !self.flows.contains_key(&flow_id) {
            return Err(BrokerErrorCode::Capacity);
        }
        if self.flows.contains_key(&flow_id) {
            return Err(BrokerErrorCode::InvalidRequest);
        }
        let snapshot = FlowSnapshot {
            flow_id,
            process_id,
            protocol,
            destination: destination.to_owned(),
            mihomo,
            state: FlowState::Opening,
        };
        self.flows.insert(
            flow_id,
            FlowRecord {
                snapshot: snapshot.clone(),
                last_activity: now,
            },
        );
        Ok(snapshot)
    }

    pub fn establish(
        &mut self,
        flow_id: u64,
        now: Instant,
    ) -> Result<FlowSnapshot, BrokerErrorCode> {
        let record = self
            .flows
            .get_mut(&flow_id)
            .ok_or(BrokerErrorCode::FlowNotFound)?;
        if record.snapshot.state != FlowState::Opening {
            return Err(BrokerErrorCode::InvalidRequest);
        }
        record.snapshot.state = FlowState::Established;
        record.last_activity = now;
        Ok(record.snapshot.clone())
    }

    pub fn touch(&mut self, flow_id: u64, now: Instant) -> Result<(), BrokerErrorCode> {
        let record = self
            .flows
            .get_mut(&flow_id)
            .ok_or(BrokerErrorCode::FlowNotFound)?;
        if record.snapshot.state != FlowState::Established {
            return Err(BrokerErrorCode::Closed);
        }
        record.last_activity = now;
        Ok(())
    }

    pub fn close(&mut self, flow_id: u64) -> Result<FlowSnapshot, BrokerErrorCode> {
        let mut record = self
            .flows
            .remove(&flow_id)
            .ok_or(BrokerErrorCode::FlowNotFound)?;
        record.snapshot.state = FlowState::Closed;
        Ok(record.snapshot)
    }

    pub fn reap_idle(&mut self, now: Instant, timeout: Duration) -> Vec<FlowSnapshot> {
        let expired = self
            .flows
            .iter()
            .filter_map(|(id, record)| {
                (now.saturating_duration_since(record.last_activity) >= timeout).then_some(*id)
            })
            .collect::<Vec<_>>();
        expired
            .into_iter()
            .filter_map(|id| self.close(id).ok())
            .collect()
    }

    pub fn snapshot(&self, flow_id: u64) -> Option<FlowSnapshot> {
        self.flows
            .get(&flow_id)
            .map(|record| record.snapshot.clone())
    }
}

#[derive(Debug, Default)]
pub struct MihomoBroker {
    registry: FlowRegistry,
    authenticated: bool,
}

impl MihomoBroker {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn authenticate(
        &mut self,
        frame: &BrokerFrame,
        expected_token: &str,
    ) -> Result<(), BrokerErrorCode> {
        let BrokerFrame::Hello { protocol, token } = frame else {
            return Err(BrokerErrorCode::Unauthorized);
        };
        if *protocol != BROKER_PROTOCOL_VERSION {
            return Err(BrokerErrorCode::ProtocolMismatch);
        }
        if !constant_time_eq(token, expected_token) {
            return Err(BrokerErrorCode::Unauthorized);
        }
        self.authenticated = true;
        Ok(())
    }

    pub fn open(
        &mut self,
        frame: &BrokerFrame,
        now: Instant,
    ) -> Result<BrokerFrame, BrokerErrorCode> {
        if !self.authenticated {
            return Err(BrokerErrorCode::Unauthorized);
        }
        let BrokerFrame::Open {
            flow_id,
            process_id,
            protocol,
            destination,
            mihomo,
        } = frame
        else {
            return Err(BrokerErrorCode::InvalidRequest);
        };
        self.registry
            .open(*flow_id, *process_id, *protocol, destination, *mihomo, now)?;
        Ok(BrokerFrame::Opened { flow_id: *flow_id })
    }

    pub fn establish(
        &mut self,
        flow_id: u64,
        now: Instant,
    ) -> Result<BrokerFrame, BrokerErrorCode> {
        if !self.authenticated {
            return Err(BrokerErrorCode::Unauthorized);
        }
        self.registry.establish(flow_id, now)?;
        Ok(BrokerFrame::Opened { flow_id })
    }

    pub fn data(&mut self, frame: &BrokerFrame, now: Instant) -> Result<(), BrokerErrorCode> {
        if !self.authenticated {
            return Err(BrokerErrorCode::Unauthorized);
        }
        let BrokerFrame::Data { flow_id, payload } = frame else {
            return Err(BrokerErrorCode::InvalidRequest);
        };
        if payload.len() > MAX_PAYLOAD_BYTES {
            return Err(BrokerErrorCode::InvalidRequest);
        }
        self.registry.touch(*flow_id, now)
    }

    pub fn close(&mut self, flow_id: u64) -> Result<BrokerFrame, BrokerErrorCode> {
        if !self.authenticated {
            return Err(BrokerErrorCode::Unauthorized);
        }
        self.registry.close(flow_id)?;
        Ok(BrokerFrame::Close { flow_id })
    }

    #[allow(dead_code)]
    pub fn reap_idle(&mut self, now: Instant) -> Vec<FlowSnapshot> {
        self.registry.reap_idle(now, FLOW_IDLE_TIMEOUT)
    }

    pub fn flow(&self, flow_id: u64) -> Option<FlowSnapshot> {
        self.registry.snapshot(flow_id)
    }
}

pub fn encode_frame(frame: &BrokerFrame) -> Result<Vec<u8>, BrokerErrorCode> {
    let mut encoded = serde_json::to_vec(frame).map_err(|_| BrokerErrorCode::InvalidRequest)?;
    if encoded.len() > MAX_FRAME_BYTES {
        return Err(BrokerErrorCode::InvalidRequest);
    }
    encoded.push(b'\n');
    Ok(encoded)
}

pub fn decode_frame(line: &[u8]) -> Result<BrokerFrame, BrokerErrorCode> {
    if line.is_empty() || line.len() > MAX_FRAME_BYTES || line.last() != Some(&b'\n') {
        return Err(BrokerErrorCode::InvalidRequest);
    }
    serde_json::from_slice(&line[..line.len() - 1]).map_err(|_| BrokerErrorCode::InvalidRequest)
}

/// Establishes one TCP flow through Mihomo's local SOCKS5 listener.  The
/// caller remains responsible for registering the returned stream in the
/// flow registry before forwarding bytes.  Only loopback Mihomo endpoints are
/// accepted, and every handshake stage has a bounded timeout.
pub async fn connect_tcp_via_mihomo(
    mihomo: SocketAddr,
    destination: &str,
) -> Result<TcpStream, BrokerErrorCode> {
    validate_open(1, 1, destination, mihomo)?;
    let (host, port) = parse_destination(destination).ok_or(BrokerErrorCode::InvalidRequest)?;
    let mut stream = timeout(MIHOMO_CONNECT_TIMEOUT, TcpStream::connect(mihomo))
        .await
        .map_err(|_| BrokerErrorCode::Timeout)?
        .map_err(|_| BrokerErrorCode::ProxyUnavailable)?;
    timeout(MIHOMO_CONNECT_TIMEOUT, async {
        stream.write_all(&[0x05, 0x01, 0x00]).await?;
        let mut greeting = [0u8; 2];
        stream.read_exact(&mut greeting).await?;
        if greeting != [0x05, 0x00] {
            return Err(std::io::Error::other(
                "Mihomo SOCKS5 authentication rejected",
            ));
        }
        let mut request = vec![0x05, 0x01, 0x00];
        if let Ok(address) = host.parse::<std::net::IpAddr>() {
            match address {
                std::net::IpAddr::V4(value) => {
                    request.push(0x01);
                    request.extend_from_slice(&value.octets());
                }
                std::net::IpAddr::V6(value) => {
                    request.push(0x04);
                    request.extend_from_slice(&value.octets());
                }
            }
        } else {
            let bytes = host.as_bytes();
            if bytes.is_empty() || bytes.len() > 255 {
                return Err(std::io::Error::other("Mihomo destination is too long"));
            }
            request.push(0x03);
            request.push(bytes.len() as u8);
            request.extend_from_slice(bytes);
        }
        request.extend_from_slice(&port.to_be_bytes());
        stream.write_all(&request).await?;
        let mut response = [0u8; 4];
        stream.read_exact(&mut response).await?;
        if response[0] != 0x05 || response[1] != 0x00 {
            return Err(std::io::Error::other("Mihomo SOCKS5 CONNECT failed"));
        }
        let address_len = match response[3] {
            0x01 => 4,
            0x04 => 16,
            0x03 => {
                let mut length = [0u8; 1];
                stream.read_exact(&mut length).await?;
                usize::from(length[0])
            }
            _ => {
                return Err(std::io::Error::other(
                    "Mihomo returned invalid address type",
                ))
            }
        };
        let mut bound_address = vec![0u8; address_len + 2];
        stream.read_exact(&mut bound_address).await?;
        Ok::<(), std::io::Error>(())
    })
    .await
    .map_err(|_| BrokerErrorCode::Timeout)?
    .map_err(|_| BrokerErrorCode::ProxyUnavailable)?;
    Ok(stream)
}

fn parse_destination(destination: &str) -> Option<(String, u16)> {
    if let Some(rest) = destination.strip_prefix('[') {
        let (host, port) = rest.split_once("]:")?;
        let port = port.parse().ok()?;
        return (port != 0).then_some((host.to_owned(), port));
    }
    let (host, port) = destination.rsplit_once(':')?;
    if host.is_empty() || host.contains(':') {
        return None;
    }
    let port = port.parse().ok()?;
    (port != 0).then_some((host.to_owned(), port))
}

fn validate_open(
    flow_id: u64,
    process_id: u32,
    destination: &str,
    mihomo: SocketAddr,
) -> Result<(), BrokerErrorCode> {
    if flow_id == 0 || process_id == 0 || destination.is_empty() {
        return Err(BrokerErrorCode::InvalidRequest);
    }
    if destination.len() > MAX_DESTINATION_BYTES
        || destination
            .bytes()
            .any(|byte| byte == b'\r' || byte == b'\n')
    {
        return Err(BrokerErrorCode::InvalidRequest);
    }
    // Mihomo must be a local broker endpoint.  This prevents a privileged
    // Helper flow-control endpoint from becoming an arbitrary TCP pivot.
    if !mihomo.ip().is_loopback() || mihomo.port() == 0 {
        return Err(BrokerErrorCode::ProxyUnavailable);
    }
    Ok(())
}

fn constant_time_eq(left: &str, right: &str) -> bool {
    let left = left.as_bytes();
    let right = right.as_bytes();
    let mut difference = left.len() ^ right.len();
    for index in 0..left.len().max(right.len()) {
        difference |= usize::from(
            left.get(index).copied().unwrap_or_default()
                ^ right.get(index).copied().unwrap_or_default(),
        );
    }
    difference == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr, SocketAddr};

    fn proxy() -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 7890)
    }

    #[test]
    fn authenticated_tcp_flow_has_explicit_lifecycle() {
        let now = Instant::now();
        let mut broker = MihomoBroker::new();
        assert_eq!(
            broker.authenticate(
                &BrokerFrame::Hello {
                    protocol: BROKER_PROTOCOL_VERSION,
                    token: "secret".to_owned(),
                },
                "secret",
            ),
            Ok(())
        );
        let open = BrokerFrame::Open {
            flow_id: 7,
            process_id: 42,
            protocol: FlowProtocol::Tcp,
            destination: "example.com:443".to_owned(),
            mihomo: proxy(),
        };
        assert_eq!(
            broker.open(&open, now),
            Ok(BrokerFrame::Opened { flow_id: 7 })
        );
        assert_eq!(
            broker.flow(7).map(|flow| flow.state),
            Some(FlowState::Opening)
        );
        broker.establish(7, now).expect("establish");
        broker
            .data(
                &BrokerFrame::Data {
                    flow_id: 7,
                    payload: b"hello".to_vec(),
                },
                now,
            )
            .expect("data");
        broker.close(7).expect("close");
        assert!(broker.flow(7).is_none());
    }

    #[test]
    fn frame_round_trip_and_bounds_are_deterministic() {
        let frame = BrokerFrame::Data {
            flow_id: 9,
            payload: vec![1, 2, 3],
        };
        let encoded = encode_frame(&frame).expect("encode");
        assert_eq!(decode_frame(&encoded).expect("decode"), frame);
        assert_eq!(decode_frame(b"{}"), Err(BrokerErrorCode::InvalidRequest));
        assert_eq!(
            encode_frame(&BrokerFrame::Data {
                flow_id: 9,
                payload: vec![0; MAX_PAYLOAD_BYTES + 1],
            }),
            Err(BrokerErrorCode::InvalidRequest)
        );
    }

    #[test]
    fn rejects_non_loopback_proxy_and_invalid_destination() {
        let mut registry = FlowRegistry::default();
        let remote = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(192, 0, 2, 1)), 7890);
        assert_eq!(
            registry.open(
                1,
                2,
                FlowProtocol::Udp,
                "example.com:443",
                remote,
                Instant::now()
            ),
            Err(BrokerErrorCode::ProxyUnavailable)
        );
        assert_eq!(
            registry.open(
                1,
                2,
                FlowProtocol::Dns,
                "bad\ndestination",
                proxy(),
                Instant::now()
            ),
            Err(BrokerErrorCode::InvalidRequest)
        );
    }

    #[test]
    fn idle_flows_are_reaped_and_closed() {
        let now = Instant::now();
        let mut registry = FlowRegistry::default();
        registry
            .open(3, 4, FlowProtocol::Udp, "dns.google:53", proxy(), now)
            .expect("open");
        let expired = registry.reap_idle(now + Duration::from_secs(121), FLOW_IDLE_TIMEOUT);
        assert_eq!(expired.len(), 1);
        assert_eq!(expired[0].state, FlowState::Closed);
        assert_eq!(registry.len(), 0);
    }

    #[test]
    fn destination_parser_handles_domains_and_bracketed_ipv6() {
        assert_eq!(
            parse_destination("example.com:443"),
            Some(("example.com".to_owned(), 443))
        );
        assert_eq!(
            parse_destination("[2001:db8::1]:443"),
            Some(("2001:db8::1".to_owned(), 443))
        );
        assert!(parse_destination("2001:db8::1:443").is_none());
        assert!(parse_destination("example.com:0").is_none());
    }
}
