use std::collections::HashMap;
use std::io::ErrorKind;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use flclash_strict_contract::StrictProxyIngressSet;

use crate::{
    strict_udp_data_frame_key_id, strict_udp_frame::decode_strict_udp_credential,
    StrictUdpDataAuthenticator, StrictUdpDataDirection, StrictUdpReplayWindow,
    STRICT_UDP_DATA_MAX_FRAME_BYTES,
};

pub const STRICT_CORE_UDP_MAX_ASSOCIATIONS: usize = 1024;
const STRICT_CORE_UDP_ASSOCIATION_IDLE: Duration = Duration::from_secs(90);
const STRICT_CORE_UDP_SWEEP_INTERVAL: Duration = Duration::from_secs(1);
const STRICT_CORE_UDP_MAX_TIMEOUT: Duration = Duration::from_secs(30);

pub struct StrictCoreUdpTransport {
    socket: UdpSocket,
    local_endpoint: SocketAddrV4,
    credentials: Vec<StrictUdpDataAuthenticator>,
    credentials_by_target: HashMap<String, usize>,
    credentials_by_key: HashMap<[u8; 16], usize>,
    associations: HashMap<[u8; 16], StrictCoreUdpAssociation>,
    send_buffer: Box<[u8; STRICT_UDP_DATA_MAX_FRAME_BYTES]>,
    receive_buffer: Box<[u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1]>,
    last_sweep: Instant,
}

struct StrictCoreUdpAssociation {
    credential_index: usize,
    next_outbound: Option<u64>,
    inbound_replay: StrictUdpReplayWindow,
    last_seen: Instant,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StrictCoreUdpReply {
    association_id: [u8; 16],
    sequence: u64,
    endpoint: SocketAddr,
    payload_bytes: usize,
}

impl StrictCoreUdpReply {
    pub fn association_id(&self) -> [u8; 16] {
        self.association_id
    }

    pub fn sequence(&self) -> u64 {
        self.sequence
    }

    pub fn endpoint(&self) -> SocketAddr {
        self.endpoint
    }

    pub fn payload_bytes(&self) -> usize {
        self.payload_bytes
    }
}

impl StrictCoreUdpTransport {
    pub fn connect(ingress: &StrictProxyIngressSet, timeout: Duration) -> Result<Self> {
        ingress.validate()?;
        if ingress.entries.is_empty() || timeout.is_zero() || timeout > STRICT_CORE_UDP_MAX_TIMEOUT
        {
            bail!("strict Core UDP transport parameters are invalid");
        }
        let core_endpoint = ingress
            .udp_endpoint
            .context("strict Core UDP data endpoint is missing")?;
        let mut credentials = Vec::with_capacity(ingress.entries.len());
        let mut credentials_by_target = HashMap::with_capacity(ingress.entries.len());
        let mut credentials_by_key = HashMap::with_capacity(ingress.entries.len());
        for entry in &ingress.entries {
            let username = decode_strict_udp_credential(&entry.username, "username")?;
            let password = decode_strict_udp_credential(&entry.password, "password")?;
            let mut key_id = [0_u8; 16];
            key_id.copy_from_slice(&username[..16]);
            if credentials_by_target.contains_key(&entry.target_group)
                || credentials_by_key.contains_key(&key_id)
            {
                bail!("strict Core UDP credential identity is duplicated");
            }
            let credential = StrictUdpDataAuthenticator::new(ingress.generation, key_id, password)?;
            let credential_index = credentials.len();
            credentials_by_target.insert(entry.target_group.clone(), credential_index);
            credentials_by_key.insert(key_id, credential_index);
            credentials.push(credential);
        }

        let socket = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
            .context("bind strict Core UDP data transport")?;
        socket
            .set_read_timeout(Some(timeout))
            .context("set strict Core UDP data read timeout")?;
        socket
            .set_write_timeout(Some(timeout))
            .context("set strict Core UDP data write timeout")?;
        socket
            .connect(core_endpoint)
            .context("connect strict Core UDP data transport")?;
        let local_endpoint = match socket.local_addr()? {
            SocketAddr::V4(endpoint)
                if endpoint.ip() == &Ipv4Addr::LOCALHOST && endpoint.port() != 0 =>
            {
                endpoint
            }
            _ => bail!("strict Core UDP data transport bound an unsafe endpoint"),
        };
        Ok(Self {
            socket,
            local_endpoint,
            credentials,
            credentials_by_target,
            credentials_by_key,
            associations: HashMap::with_capacity(STRICT_CORE_UDP_MAX_ASSOCIATIONS),
            send_buffer: Box::new([0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES]),
            receive_buffer: Box::new([0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1]),
            last_sweep: Instant::now(),
        })
    }

    pub fn local_endpoint(&self) -> SocketAddrV4 {
        self.local_endpoint
    }

    pub fn association_count(&self) -> usize {
        self.associations.len()
    }

    pub fn remove_association(&mut self, association_id: [u8; 16]) -> bool {
        self.associations.remove(&association_id).is_some()
    }

    pub fn send(
        &mut self,
        association_id: [u8; 16],
        target_group: &str,
        destination: SocketAddr,
        payload: &[u8],
    ) -> Result<u64> {
        let now = Instant::now();
        self.sweep_if_due(now);
        let credential_index = *self
            .credentials_by_target
            .get(target_group)
            .context("strict Core UDP target group is unavailable")?;
        let (sequence, is_new) = match self.associations.get(&association_id) {
            Some(association) => {
                if association.credential_index != credential_index {
                    bail!("strict Core UDP association changed target group");
                }
                (
                    association
                        .next_outbound
                        .context("strict Core UDP outbound sequence is exhausted")?,
                    false,
                )
            }
            None => {
                if self.associations.len() >= STRICT_CORE_UDP_MAX_ASSOCIATIONS {
                    self.sweep(now);
                    if self.associations.len() >= STRICT_CORE_UDP_MAX_ASSOCIATIONS {
                        bail!("strict Core UDP association limit is reached");
                    }
                }
                (1, true)
            }
        };
        let frame_bytes = self.credentials[credential_index].encode(
            self.send_buffer.as_mut_slice(),
            StrictUdpDataDirection::Outbound,
            association_id,
            sequence,
            destination,
            payload,
        )?;
        let next_outbound = sequence.checked_add(1);
        if is_new {
            self.associations.insert(
                association_id,
                StrictCoreUdpAssociation {
                    credential_index,
                    next_outbound,
                    inbound_replay: StrictUdpReplayWindow::default(),
                    last_seen: now,
                },
            );
        } else if let Some(association) = self.associations.get_mut(&association_id) {
            association.next_outbound = next_outbound;
            association.last_seen = now;
        } else {
            bail!("strict Core UDP association disappeared");
        }
        let sent = self
            .socket
            .send(&self.send_buffer[..frame_bytes])
            .context("send strict Core UDP data frame")?;
        if sent != frame_bytes {
            bail!("strict Core UDP data frame was truncated");
        }
        Ok(sequence)
    }

    pub fn receive_into(&mut self, output: &mut [u8]) -> Result<StrictCoreUdpReply> {
        self.poll_receive_into(output)?
            .context("strict Core UDP data receive deadline exceeded")
    }

    pub fn poll_receive_into(&mut self, output: &mut [u8]) -> Result<Option<StrictCoreUdpReply>> {
        self.sweep_if_due(Instant::now());
        let count = match self.socket.recv(self.receive_buffer.as_mut_slice()) {
            Ok(count) => count,
            Err(error) if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                return Ok(None);
            }
            Err(error) => return Err(error).context("receive strict Core UDP data frame"),
        };
        if count > STRICT_UDP_DATA_MAX_FRAME_BYTES {
            bail!("strict Core UDP data frame is oversized");
        }
        let frame = &self.receive_buffer[..count];
        let key_id = strict_udp_data_frame_key_id(frame)?;
        let credential_index = *self
            .credentials_by_key
            .get(&key_id)
            .context("strict Core UDP reply credential is unknown")?;
        let decoded =
            self.credentials[credential_index].decode(frame, StrictUdpDataDirection::Inbound)?;
        if output.len() < decoded.payload().len() {
            bail!("strict Core UDP reply output buffer is too small");
        }
        let association_id = decoded.association_id();
        let sequence = decoded.sequence();
        let endpoint = decoded.endpoint();
        let payload_bytes = decoded.payload().len();
        let now = Instant::now();
        let association = self
            .associations
            .get_mut(&association_id)
            .context("strict Core UDP reply association is unknown or expired")?;
        if association.credential_index != credential_index {
            bail!("strict Core UDP reply changed credential identity");
        }
        if !association.inbound_replay.accept(sequence) {
            bail!("strict Core UDP reply sequence is replayed or stale");
        }
        association.last_seen = now;
        output[..payload_bytes].copy_from_slice(decoded.payload());
        Ok(Some(StrictCoreUdpReply {
            association_id,
            sequence,
            endpoint,
            payload_bytes,
        }))
    }

    fn sweep_if_due(&mut self, now: Instant) {
        if now.duration_since(self.last_sweep) >= STRICT_CORE_UDP_SWEEP_INTERVAL {
            self.sweep(now);
        }
    }

    fn sweep(&mut self, now: Instant) {
        self.associations.retain(|_, association| {
            now.duration_since(association.last_seen) < STRICT_CORE_UDP_ASSOCIATION_IDLE
        });
        self.last_sweep = now;
    }
}

#[cfg(test)]
mod tests {
    use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
    use std::thread;
    use std::time::Duration;

    use flclash_strict_contract::{StrictProxyIngressEntry, StrictProxyIngressSet};

    use super::*;
    use crate::{
        StrictUdpDataAuthenticator, StrictUdpDataDirection, STRICT_UDP_DATA_MAX_FRAME_BYTES,
    };

    #[test]
    fn persistent_transport_routes_and_authenticates_core_replies() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let core_endpoint = v4_endpoint(&core);
        let ingress = ingress(core_endpoint, 41, "GLOBAL", '1', '3');
        let worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(41, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (count, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..count], StrictUdpDataDirection::Outbound)
                .unwrap();
            assert_eq!(decoded.payload(), b"request");
            let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let count = authenticator
                .encode(
                    &mut response,
                    StrictUdpDataDirection::Inbound,
                    decoded.association_id(),
                    1,
                    decoded.endpoint(),
                    b"response",
                )
                .unwrap();
            core.send_to(&response[..count], source).unwrap();

            let (count, _) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..count], StrictUdpDataDirection::Outbound)
                .unwrap();
            assert_eq!(decoded.sequence(), 2);
            assert_eq!(decoded.payload(), b"request-2");
        });

        let mut transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_secs(1)).unwrap();
        let association = [0x44; 16];
        let destination = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 443));
        assert_eq!(
            transport
                .send(association, "GLOBAL", destination, b"request",)
                .unwrap(),
            1
        );
        let mut payload = [0_u8; 64];
        let reply = transport.receive_into(&mut payload).unwrap();
        assert_eq!(reply.association_id(), association);
        assert_eq!(reply.sequence(), 1);
        assert_eq!(reply.endpoint(), destination);
        assert_eq!(reply.payload_bytes(), 8);
        assert_eq!(&payload[..reply.payload_bytes()], b"response");
        assert_eq!(
            transport
                .send(association, "GLOBAL", destination, b"request-2")
                .unwrap(),
            2
        );
        assert_eq!(transport.association_count(), 1);
        assert!(transport.local_endpoint().ip().is_loopback());
        worker.join().unwrap();
        assert!(transport.remove_association(association));
        assert_eq!(transport.association_count(), 0);
    }

    #[test]
    fn transport_rejects_replayed_replies_and_cross_group_association_reuse() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let core_endpoint = v4_endpoint(&core);
        let ingress = StrictProxyIngressSet::new(
            43,
            core_endpoint,
            vec![
                ingress_entry("GROUP-A", '1', '3'),
                ingress_entry("GROUP-B", '2', '4'),
            ],
        )
        .unwrap();
        let worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(43, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (count, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..count], StrictUdpDataDirection::Outbound)
                .unwrap();
            let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let count = authenticator
                .encode(
                    &mut response,
                    StrictUdpDataDirection::Inbound,
                    decoded.association_id(),
                    1,
                    decoded.endpoint(),
                    b"reply",
                )
                .unwrap();
            core.send_to(&response[..count], source).unwrap();
            core.send_to(&response[..count], source).unwrap();
        });

        let mut transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_secs(1)).unwrap();
        let association = [0x55; 16];
        let destination = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 4, 4), 53));
        transport
            .send(association, "GROUP-A", destination, b"request")
            .unwrap();
        assert!(transport
            .send(association, "GROUP-B", destination, b"request")
            .is_err());
        let mut payload = [0_u8; 64];
        transport.receive_into(&mut payload).unwrap();
        assert!(transport.receive_into(&mut payload).is_err());
        worker.join().unwrap();
    }

    #[test]
    fn transport_bounds_associations_and_rejects_credential_key_collisions() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        let core_endpoint = v4_endpoint(&core);
        let ingress = ingress(core_endpoint, 47, "GLOBAL", '1', '3');
        let mut transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_secs(1)).unwrap();
        let destination = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 443));
        for index in 1..=STRICT_CORE_UDP_MAX_ASSOCIATIONS {
            let mut association = [0_u8; 16];
            association[8..].copy_from_slice(&(index as u64).to_be_bytes());
            transport
                .send(association, "GLOBAL", destination, b"x")
                .unwrap();
        }
        assert_eq!(
            transport.association_count(),
            STRICT_CORE_UDP_MAX_ASSOCIATIONS
        );
        let mut overflow = [0_u8; 16];
        overflow[8..]
            .copy_from_slice(&((STRICT_CORE_UDP_MAX_ASSOCIATIONS + 1) as u64).to_be_bytes());
        assert!(transport
            .send(overflow, "GLOBAL", destination, b"x")
            .is_err());

        let first = format!("{}{}", "11".repeat(16), "22".repeat(16));
        let second = format!("{}{}", "11".repeat(16), "44".repeat(16));
        let duplicate_key_id = StrictProxyIngressSet::new(
            49,
            core_endpoint,
            vec![
                StrictProxyIngressEntry::new(
                    "GROUP-A".into(),
                    SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41001),
                    first,
                    "33".repeat(32),
                )
                .unwrap(),
                StrictProxyIngressEntry::new(
                    "GROUP-B".into(),
                    SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41002),
                    second,
                    "55".repeat(32),
                )
                .unwrap(),
            ],
        )
        .unwrap();
        assert!(
            StrictCoreUdpTransport::connect(&duplicate_key_id, Duration::from_secs(1)).is_err()
        );
    }

    #[test]
    fn transport_rejects_tampering_without_consuming_the_valid_reply_sequence() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let ingress = ingress(v4_endpoint(&core), 51, "GLOBAL", '1', '3');
        let worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(51, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (count, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..count], StrictUdpDataDirection::Outbound)
                .unwrap();
            let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let count = authenticator
                .encode(
                    &mut response,
                    StrictUdpDataDirection::Inbound,
                    decoded.association_id(),
                    1,
                    decoded.endpoint(),
                    b"valid",
                )
                .unwrap();
            response[count - 1] ^= 0x80;
            core.send_to(&response[..count], source).unwrap();
            response[count - 1] ^= 0x80;
            core.send_to(&response[..count], source).unwrap();
        });

        let mut transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_secs(1)).unwrap();
        let association = [0x66; 16];
        let destination = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(1, 1, 1, 1), 53));
        transport
            .send(association, "GLOBAL", destination, b"request")
            .unwrap();
        let mut payload = [0_u8; 64];
        assert!(transport.receive_into(&mut payload).is_err());
        let reply = transport.receive_into(&mut payload).unwrap();
        assert_eq!(reply.sequence(), 1);
        assert_eq!(&payload[..reply.payload_bytes()], b"valid");
        worker.join().unwrap();
    }

    #[test]
    fn transport_recovers_after_an_oversized_datagram() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let ingress = ingress(v4_endpoint(&core), 53, "GLOBAL", '1', '3');
        let worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(53, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (count, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..count], StrictUdpDataDirection::Outbound)
                .unwrap();
            core.send_to(&vec![0xAA; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1], source)
                .unwrap();
            let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let count = authenticator
                .encode(
                    &mut response,
                    StrictUdpDataDirection::Inbound,
                    decoded.association_id(),
                    1,
                    decoded.endpoint(),
                    b"valid",
                )
                .unwrap();
            core.send_to(&response[..count], source).unwrap();
        });

        let mut transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_secs(1)).unwrap();
        let association = [0x77; 16];
        let destination = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(9, 9, 9, 9), 443));
        transport
            .send(association, "GLOBAL", destination, b"request")
            .unwrap();
        let mut payload = [0_u8; 64];
        assert!(transport.receive_into(&mut payload).is_err());
        let reply = transport.receive_into(&mut payload).unwrap();
        assert_eq!(&payload[..reply.payload_bytes()], b"valid");
        worker.join().unwrap();
    }

    #[test]
    fn polling_timeout_is_not_a_transport_failure_and_preserves_the_next_reply() {
        let core = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        core.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let core_endpoint = v4_endpoint(&core);
        let ingress = ingress(core_endpoint, 61, "GLOBAL", '1', '3');
        let (request_seen_tx, request_seen_rx) = std::sync::mpsc::sync_channel(1);
        let (reply_now_tx, reply_now_rx) = std::sync::mpsc::sync_channel(1);
        let worker = thread::spawn(move || {
            let authenticator =
                StrictUdpDataAuthenticator::new(61, [0x11; 16], [0x33; 32]).unwrap();
            let mut request = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES + 1];
            let (count, source) = core.recv_from(&mut request).unwrap();
            let decoded = authenticator
                .decode(&request[..count], StrictUdpDataDirection::Outbound)
                .unwrap();
            request_seen_tx.send(()).unwrap();
            reply_now_rx.recv().unwrap();
            let mut response = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let count = authenticator
                .encode(
                    &mut response,
                    StrictUdpDataDirection::Inbound,
                    decoded.association_id(),
                    1,
                    decoded.endpoint(),
                    b"response",
                )
                .unwrap();
            core.send_to(&response[..count], source).unwrap();
        });

        let mut transport =
            StrictCoreUdpTransport::connect(&ingress, Duration::from_millis(20)).unwrap();
        let destination = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 443));
        transport
            .send([0x44; 16], "GLOBAL", destination, b"request")
            .unwrap();
        request_seen_rx.recv().unwrap();
        let mut payload = [0_u8; 64];
        assert!(transport.poll_receive_into(&mut payload).unwrap().is_none());
        reply_now_tx.send(()).unwrap();
        let reply = transport.poll_receive_into(&mut payload).unwrap().unwrap();
        assert_eq!(&payload[..reply.payload_bytes()], b"response");
        worker.join().unwrap();
    }

    fn ingress(
        endpoint: SocketAddrV4,
        generation: u64,
        target_group: &str,
        username: char,
        password: char,
    ) -> StrictProxyIngressSet {
        StrictProxyIngressSet::new(
            generation,
            endpoint,
            vec![ingress_entry(target_group, username, password)],
        )
        .unwrap()
    }

    fn ingress_entry(
        target_group: &str,
        username: char,
        password: char,
    ) -> StrictProxyIngressEntry {
        StrictProxyIngressEntry::new(
            target_group.into(),
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41000 + u16::from(username as u8)),
            username.to_string().repeat(64),
            password.to_string().repeat(64),
        )
        .unwrap()
    }

    fn v4_endpoint(socket: &UdpSocket) -> SocketAddrV4 {
        match socket.local_addr().unwrap() {
            SocketAddr::V4(endpoint) => endpoint,
            SocketAddr::V6(_) => unreachable!(),
        }
    }
}
