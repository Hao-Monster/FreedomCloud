use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6};

use anyhow::{bail, Context, Result};
use hmac::{Hmac, Mac};
use sha2::Sha256;

pub const STRICT_UDP_DATA_HEADER_BYTES: usize = 80;
pub const STRICT_UDP_DATA_MAX_PAYLOAD_BYTES: usize = 16 * 1024;
pub const STRICT_UDP_DATA_MAX_FRAME_BYTES: usize =
    STRICT_UDP_DATA_HEADER_BYTES + STRICT_UDP_DATA_MAX_PAYLOAD_BYTES + 32;

const MAGIC: &[u8; 4] = b"FCXD";
const VERSION: u8 = 1;
const OUTBOUND: u8 = 1;
const INBOUND: u8 = 2;
const IPV4: u8 = 4;
const IPV6: u8 = 6;
const KEY_ID_BYTES: usize = 16;
const ASSOCIATION_ID_BYTES: usize = 16;
const TAG_BYTES: usize = 32;
const VERSION_OFFSET: usize = 4;
const KIND_OFFSET: usize = 5;
const FLAGS_OFFSET: usize = 6;
const GENERATION_OFFSET: usize = 8;
const KEY_ID_OFFSET: usize = 16;
const ASSOCIATION_ID_OFFSET: usize = 32;
const SEQUENCE_OFFSET: usize = 48;
const ADDRESS_FAMILY_OFFSET: usize = 56;
const PORT_OFFSET: usize = 58;
const ADDRESS_OFFSET: usize = 60;
const PAYLOAD_LENGTH_OFFSET: usize = 76;

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StrictUdpDataDirection {
    Outbound,
    Inbound,
}

pub(crate) fn decode_strict_udp_credential(value: &str, label: &str) -> Result<[u8; 32]> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("strict UDP {label} credential is invalid");
    }
    let mut decoded = [0_u8; 32];
    for (index, byte) in decoded.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16)
            .with_context(|| format!("strict UDP {label} credential is not hexadecimal"))?;
    }
    if decoded.iter().all(|byte| *byte == 0) {
        bail!("strict UDP {label} credential cannot be zero");
    }
    Ok(decoded)
}

impl StrictUdpDataDirection {
    fn kind(self) -> u8 {
        match self {
            Self::Outbound => OUTBOUND,
            Self::Inbound => INBOUND,
        }
    }
}

pub struct StrictUdpDataAuthenticator {
    generation: u64,
    key_id: [u8; KEY_ID_BYTES],
    key: [u8; TAG_BYTES],
}

impl StrictUdpDataAuthenticator {
    pub fn new(generation: u64, key_id: [u8; KEY_ID_BYTES], key: [u8; TAG_BYTES]) -> Result<Self> {
        if generation == 0
            || key_id.iter().all(|byte| *byte == 0)
            || key.iter().all(|byte| *byte == 0)
        {
            bail!("strict UDP data authentication identity is invalid");
        }
        Ok(Self {
            generation,
            key_id,
            key,
        })
    }

    pub fn encode(
        &self,
        output: &mut [u8],
        direction: StrictUdpDataDirection,
        association_id: [u8; ASSOCIATION_ID_BYTES],
        sequence: u64,
        endpoint: SocketAddr,
        payload: &[u8],
    ) -> Result<usize> {
        if association_id.iter().all(|byte| *byte == 0) || sequence == 0 {
            bail!("strict UDP data association correlation is invalid");
        }
        if payload.is_empty() || payload.len() > STRICT_UDP_DATA_MAX_PAYLOAD_BYTES {
            bail!("strict UDP data payload size is invalid");
        }
        validate_endpoint(endpoint)?;
        let frame_bytes = STRICT_UDP_DATA_HEADER_BYTES
            .checked_add(payload.len())
            .and_then(|value| value.checked_add(TAG_BYTES))
            .context("strict UDP data frame size overflow")?;
        if output.len() < frame_bytes {
            bail!("strict UDP data output buffer is too small");
        }

        output[..STRICT_UDP_DATA_HEADER_BYTES].fill(0);
        output[..MAGIC.len()].copy_from_slice(MAGIC);
        output[VERSION_OFFSET] = VERSION;
        output[KIND_OFFSET] = direction.kind();
        output[GENERATION_OFFSET..KEY_ID_OFFSET].copy_from_slice(&self.generation.to_be_bytes());
        output[KEY_ID_OFFSET..ASSOCIATION_ID_OFFSET].copy_from_slice(&self.key_id);
        output[ASSOCIATION_ID_OFFSET..SEQUENCE_OFFSET].copy_from_slice(&association_id);
        output[SEQUENCE_OFFSET..ADDRESS_FAMILY_OFFSET].copy_from_slice(&sequence.to_be_bytes());
        write_endpoint(&mut output[..STRICT_UDP_DATA_HEADER_BYTES], endpoint);
        output[PAYLOAD_LENGTH_OFFSET..PAYLOAD_LENGTH_OFFSET + 2]
            .copy_from_slice(&(payload.len() as u16).to_be_bytes());
        let tag_offset = STRICT_UDP_DATA_HEADER_BYTES + payload.len();
        output[STRICT_UDP_DATA_HEADER_BYTES..tag_offset].copy_from_slice(payload);
        let mut mac =
            HmacSha256::new_from_slice(&self.key).context("initialize strict UDP data HMAC")?;
        mac.update(&output[..tag_offset]);
        output[tag_offset..frame_bytes].copy_from_slice(&mac.finalize().into_bytes());
        Ok(frame_bytes)
    }

    pub fn decode<'a>(
        &self,
        frame: &'a [u8],
        expected_direction: StrictUdpDataDirection,
    ) -> Result<StrictUdpDataFrame<'a>> {
        if frame.len() < STRICT_UDP_DATA_HEADER_BYTES + 1 + TAG_BYTES
            || frame.len() > STRICT_UDP_DATA_MAX_FRAME_BYTES
        {
            bail!("strict UDP data frame size is invalid");
        }
        let payload_bytes = usize::from(u16::from_be_bytes([
            frame[PAYLOAD_LENGTH_OFFSET],
            frame[PAYLOAD_LENGTH_OFFSET + 1],
        ]));
        if payload_bytes == 0
            || payload_bytes > STRICT_UDP_DATA_MAX_PAYLOAD_BYTES
            || frame.len() != STRICT_UDP_DATA_HEADER_BYTES + payload_bytes + TAG_BYTES
        {
            bail!("strict UDP data payload length is invalid");
        }
        if &frame[..MAGIC.len()] != MAGIC
            || frame[VERSION_OFFSET] != VERSION
            || frame[KIND_OFFSET] != expected_direction.kind()
            || frame[FLAGS_OFFSET] != 0
            || frame[FLAGS_OFFSET + 1] != 0
            || frame[ADDRESS_FAMILY_OFFSET + 1] != 0
            || frame[PAYLOAD_LENGTH_OFFSET + 2] != 0
            || frame[PAYLOAD_LENGTH_OFFSET + 3] != 0
            || frame[GENERATION_OFFSET..KEY_ID_OFFSET] != self.generation.to_be_bytes()
            || frame[KEY_ID_OFFSET..ASSOCIATION_ID_OFFSET] != self.key_id
        {
            bail!("strict UDP data frame correlation failed");
        }

        let tag_offset = frame.len() - TAG_BYTES;
        let mut mac =
            HmacSha256::new_from_slice(&self.key).context("initialize strict UDP data HMAC")?;
        mac.update(&frame[..tag_offset]);
        mac.verify_slice(&frame[tag_offset..])
            .context("strict UDP data frame authentication failed")?;

        let mut association_id = [0_u8; ASSOCIATION_ID_BYTES];
        association_id.copy_from_slice(&frame[ASSOCIATION_ID_OFFSET..SEQUENCE_OFFSET]);
        let sequence = u64::from_be_bytes(
            frame[SEQUENCE_OFFSET..ADDRESS_FAMILY_OFFSET]
                .try_into()
                .expect("strict UDP sequence has a fixed width"),
        );
        if association_id.iter().all(|byte| *byte == 0) || sequence == 0 {
            bail!("strict UDP data association correlation is invalid");
        }
        let endpoint = parse_endpoint(frame)?;
        Ok(StrictUdpDataFrame {
            direction: expected_direction,
            association_id,
            sequence,
            endpoint,
            payload: &frame[STRICT_UDP_DATA_HEADER_BYTES..tag_offset],
        })
    }
}

pub fn strict_udp_data_frame_key_id(frame: &[u8]) -> Result<[u8; KEY_ID_BYTES]> {
    if frame.len() < ASSOCIATION_ID_OFFSET
        || &frame[..MAGIC.len()] != MAGIC
        || frame[VERSION_OFFSET] != VERSION
    {
        bail!("strict UDP data frame identity is invalid");
    }
    let mut key_id = [0_u8; KEY_ID_BYTES];
    key_id.copy_from_slice(&frame[KEY_ID_OFFSET..ASSOCIATION_ID_OFFSET]);
    if key_id.iter().all(|byte| *byte == 0) {
        bail!("strict UDP data frame identity is invalid");
    }
    Ok(key_id)
}

pub struct StrictUdpDataFrame<'a> {
    direction: StrictUdpDataDirection,
    association_id: [u8; ASSOCIATION_ID_BYTES],
    sequence: u64,
    endpoint: SocketAddr,
    payload: &'a [u8],
}

impl<'a> StrictUdpDataFrame<'a> {
    pub fn direction(&self) -> StrictUdpDataDirection {
        self.direction
    }

    pub fn association_id(&self) -> [u8; ASSOCIATION_ID_BYTES] {
        self.association_id
    }

    pub fn sequence(&self) -> u64 {
        self.sequence
    }

    pub fn endpoint(&self) -> SocketAddr {
        self.endpoint
    }

    pub fn payload(&self) -> &'a [u8] {
        self.payload
    }
}

#[derive(Default)]
pub struct StrictUdpReplayWindow {
    highest: u64,
    bitmap: u64,
}

impl StrictUdpReplayWindow {
    pub fn accept(&mut self, sequence: u64) -> bool {
        if sequence == 0 {
            return false;
        }
        if self.highest == 0 {
            self.highest = sequence;
            self.bitmap = 1;
            return true;
        }
        if sequence > self.highest {
            let shift = sequence - self.highest;
            self.bitmap = if shift >= u64::BITS.into() {
                1
            } else {
                (self.bitmap << shift) | 1
            };
            self.highest = sequence;
            return true;
        }
        let offset = self.highest - sequence;
        if offset >= u64::BITS.into() {
            return false;
        }
        let mask = 1_u64 << offset;
        if self.bitmap & mask != 0 {
            return false;
        }
        self.bitmap |= mask;
        true
    }
}

fn validate_endpoint(endpoint: SocketAddr) -> Result<()> {
    if endpoint.port() == 0 {
        bail!("strict UDP data endpoint port is invalid");
    }
    match endpoint {
        SocketAddr::V4(endpoint) if safe_ipv4(*endpoint.ip()) => Ok(()),
        SocketAddr::V6(endpoint)
            if endpoint.flowinfo() == 0
                && endpoint.scope_id() == 0
                && safe_ipv6(*endpoint.ip()) =>
        {
            Ok(())
        }
        _ => bail!("strict UDP data endpoint address is unsafe"),
    }
}

fn safe_ipv4(address: Ipv4Addr) -> bool {
    !address.is_unspecified()
        && !address.is_loopback()
        && !address.is_multicast()
        && !address.is_link_local()
        && address != Ipv4Addr::BROADCAST
}

fn safe_ipv6(address: Ipv6Addr) -> bool {
    let first_segment = address.segments()[0];
    !address.is_unspecified()
        && !address.is_loopback()
        && !address.is_multicast()
        && first_segment & 0xffc0 != 0xfe80
        && address.to_ipv4_mapped().is_none()
}

fn write_endpoint(frame: &mut [u8], endpoint: SocketAddr) {
    frame[PORT_OFFSET..ADDRESS_OFFSET].copy_from_slice(&endpoint.port().to_be_bytes());
    match endpoint.ip() {
        IpAddr::V4(address) => {
            frame[ADDRESS_FAMILY_OFFSET] = IPV4;
            frame[ADDRESS_OFFSET..ADDRESS_OFFSET + 4].copy_from_slice(&address.octets());
        }
        IpAddr::V6(address) => {
            frame[ADDRESS_FAMILY_OFFSET] = IPV6;
            frame[ADDRESS_OFFSET..PAYLOAD_LENGTH_OFFSET].copy_from_slice(&address.octets());
        }
    }
}

fn parse_endpoint(frame: &[u8]) -> Result<SocketAddr> {
    let port = u16::from_be_bytes([frame[PORT_OFFSET], frame[PORT_OFFSET + 1]]);
    let endpoint = match frame[ADDRESS_FAMILY_OFFSET] {
        IPV4 => {
            if frame[ADDRESS_OFFSET + 4..PAYLOAD_LENGTH_OFFSET]
                .iter()
                .any(|byte| *byte != 0)
            {
                bail!("strict UDP data IPv4 padding is noncanonical");
            }
            SocketAddr::V4(SocketAddrV4::new(
                Ipv4Addr::new(
                    frame[ADDRESS_OFFSET],
                    frame[ADDRESS_OFFSET + 1],
                    frame[ADDRESS_OFFSET + 2],
                    frame[ADDRESS_OFFSET + 3],
                ),
                port,
            ))
        }
        IPV6 => {
            let address = Ipv6Addr::from(
                <[u8; 16]>::try_from(&frame[ADDRESS_OFFSET..PAYLOAD_LENGTH_OFFSET])
                    .expect("strict UDP IPv6 address has a fixed width"),
            );
            SocketAddr::V6(SocketAddrV6::new(address, port, 0, 0))
        }
        _ => bail!("strict UDP data address family is invalid"),
    };
    validate_endpoint(endpoint)?;
    Ok(endpoint)
}

#[cfg(test)]
mod tests {
    use std::fmt::Write;
    use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6};

    use super::*;

    #[test]
    fn outbound_frame_matches_core_wire_vector() {
        let authenticator = StrictUdpDataAuthenticator::new(7, [0x11; 16], [0x33; 32]).unwrap();
        let mut frame = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
        let count = authenticator
            .encode(
                &mut frame,
                StrictUdpDataDirection::Outbound,
                [0x44; 16],
                9,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 443)),
                b"strict-udp-vector",
            )
            .unwrap();

        assert_eq!(count, STRICT_UDP_DATA_HEADER_BYTES + 17 + 32);
        assert_eq!(
            hex(&frame[count - 32..count]),
            "8715701d2e9a6cdaf7713968a7a55a1e91b0cea2d9cf447a2a8014f6f35079a9"
        );
        let decoded = authenticator
            .decode(&frame[..count], StrictUdpDataDirection::Outbound)
            .unwrap();
        assert_eq!(decoded.direction(), StrictUdpDataDirection::Outbound);
        assert_eq!(decoded.association_id(), [0x44; 16]);
        assert_eq!(decoded.sequence(), 9);
        assert_eq!(
            decoded.endpoint(),
            SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 443))
        );
        assert_eq!(decoded.payload(), b"strict-udp-vector");
    }

    #[test]
    fn round_trip_supports_canonical_ipv4_and_ipv6_in_both_directions() {
        let authenticator = StrictUdpDataAuthenticator::new(11, [0x22; 16], [0x55; 32]).unwrap();
        let cases = [
            (
                StrictUdpDataDirection::Outbound,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(10, 0, 0, 1), 53)),
            ),
            (
                StrictUdpDataDirection::Inbound,
                SocketAddr::V6(SocketAddrV6::new(
                    Ipv6Addr::new(0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888),
                    443,
                    0,
                    0,
                )),
            ),
        ];
        for (direction, endpoint) in cases {
            let mut frame = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
            let count = authenticator
                .encode(&mut frame, direction, [0x77; 16], 1, endpoint, b"payload")
                .unwrap();
            let decoded = authenticator.decode(&frame[..count], direction).unwrap();
            assert_eq!(decoded.direction(), direction);
            assert_eq!(decoded.endpoint(), endpoint);
            assert_eq!(decoded.payload(), b"payload");
        }
    }

    #[test]
    fn parser_rejects_tampering_wrong_correlation_and_noncanonical_shapes() {
        let authenticator = StrictUdpDataAuthenticator::new(13, [0x22; 16], [0x55; 32]).unwrap();
        let mut frame = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
        let count = authenticator
            .encode(
                &mut frame,
                StrictUdpDataDirection::Inbound,
                [0x77; 16],
                3,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 4, 4), 53)),
                b"reply",
            )
            .unwrap();

        assert!(authenticator
            .decode(&frame[..count], StrictUdpDataDirection::Outbound)
            .is_err());
        frame[count - 1] ^= 0x80;
        assert!(authenticator
            .decode(&frame[..count], StrictUdpDataDirection::Inbound)
            .is_err());
        frame[count - 1] ^= 0x80;
        frame[57] = 1;
        assert!(authenticator
            .decode(&frame[..count], StrictUdpDataDirection::Inbound)
            .is_err());
        frame[57] = 0;
        frame[64] = 1;
        resign(&mut frame[..count], &[0x55; 32]);
        assert!(authenticator
            .decode(&frame[..count], StrictUdpDataDirection::Inbound)
            .is_err());
        frame[64] = 0;
        frame[ADDRESS_OFFSET] = 127;
        frame[ADDRESS_OFFSET + 1] = 0;
        frame[ADDRESS_OFFSET + 2] = 0;
        frame[ADDRESS_OFFSET + 3] = 1;
        resign(&mut frame[..count], &[0x55; 32]);
        assert!(authenticator
            .decode(&frame[..count], StrictUdpDataDirection::Inbound)
            .is_err());
        assert!(authenticator
            .decode(&frame[..count - 1], StrictUdpDataDirection::Inbound)
            .is_err());
    }

    #[test]
    fn encoder_rejects_unsafe_endpoints_ids_sequences_and_payload_sizes() {
        assert!(StrictUdpDataAuthenticator::new(0, [0x22; 16], [0x55; 32]).is_err());
        assert!(StrictUdpDataAuthenticator::new(1, [0; 16], [0x55; 32]).is_err());
        assert!(StrictUdpDataAuthenticator::new(1, [0x22; 16], [0; 32]).is_err());
        let authenticator = StrictUdpDataAuthenticator::new(1, [0x22; 16], [0x55; 32]).unwrap();
        let mut frame = [0_u8; STRICT_UDP_DATA_MAX_FRAME_BYTES];
        for endpoint in [
            SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 53)),
            SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 53)),
            SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::BROADCAST, 53)),
            SocketAddr::V6(SocketAddrV6::new(Ipv6Addr::LOCALHOST, 53, 0, 0)),
            SocketAddr::V6(SocketAddrV6::new(Ipv6Addr::UNSPECIFIED, 53, 0, 0)),
        ] {
            assert!(authenticator
                .encode(
                    &mut frame,
                    StrictUdpDataDirection::Outbound,
                    [1; 16],
                    1,
                    endpoint,
                    b"payload",
                )
                .is_err());
        }
        assert!(authenticator
            .encode(
                &mut frame,
                StrictUdpDataDirection::Outbound,
                [0; 16],
                1,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 53)),
                b"payload",
            )
            .is_err());
        assert!(authenticator
            .encode(
                &mut frame,
                StrictUdpDataDirection::Outbound,
                [1; 16],
                0,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 53)),
                b"payload",
            )
            .is_err());
        assert!(authenticator
            .encode(
                &mut frame,
                StrictUdpDataDirection::Outbound,
                [1; 16],
                1,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 53)),
                &[],
            )
            .is_err());
        assert!(authenticator
            .encode(
                &mut frame,
                StrictUdpDataDirection::Outbound,
                [1; 16],
                1,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 53)),
                &vec![0; STRICT_UDP_DATA_MAX_PAYLOAD_BYTES + 1],
            )
            .is_err());
    }

    #[test]
    fn replay_window_accepts_bounded_reordering_only_once() {
        let mut window = StrictUdpReplayWindow::default();
        for sequence in [100, 98, 99, 37, 200] {
            assert!(window.accept(sequence));
        }
        for sequence in [0, 100, 37, 136] {
            assert!(!window.accept(sequence));
        }
    }

    #[test]
    fn credential_decoder_requires_nonzero_fixed_width_hex() {
        assert_eq!(
            decode_strict_udp_credential(&"11".repeat(32), "username").unwrap(),
            [0x11; 32]
        );
        for value in [
            "",
            "11",
            &"00".repeat(32),
            &format!("{}g1", "11".repeat(31)),
        ] {
            assert!(decode_strict_udp_credential(value, "username").is_err());
        }
    }

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().fold(
            String::with_capacity(bytes.len() * 2),
            |mut output, byte| {
                write!(output, "{byte:02x}").expect("write to String");
                output
            },
        )
    }

    fn resign(frame: &mut [u8], key: &[u8; 32]) {
        let tag_offset = frame.len() - 32;
        let (message, tag) = frame.split_at_mut(tag_offset);
        let mut mac = HmacSha256::new_from_slice(key).unwrap();
        mac.update(message);
        tag.copy_from_slice(&mac.finalize().into_bytes());
    }
}
