use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6};

use anyhow::{bail, Context, Result};

pub const STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES: usize = 256 * 1024;
pub const STRICT_DRIVER_DATAGRAM_MAX_RECORDS: usize = 64;
pub const STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES: usize = 16 * 1024;
pub const STRICT_DRIVER_DATAGRAM_BATCH_HEADER_BYTES: usize = 96;
pub const STRICT_DRIVER_DATAGRAM_RECORD_HEADER_BYTES: usize = 80;

const MAGIC: &[u8; 4] = b"FCXB";
const PROTOCOL: u16 = 1;
const BATCH_HEADER_BYTES: usize = STRICT_DRIVER_DATAGRAM_BATCH_HEADER_BYTES;
const RECORD_HEADER_BYTES: usize = STRICT_DRIVER_DATAGRAM_RECORD_HEADER_BYTES;
const IP_PROTOCOL_UDP: u8 = 17;
const ADDRESS_FAMILY_V4: u8 = 4;
const ADDRESS_FAMILY_V6: u8 = 6;
const KNOWN_FLAGS: u32 = StrictDriverDatagramFlags::DNS.0 | StrictDriverDatagramFlags::QUIC.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StrictDriverDatagramBatchKind {
    Captured,
    Reply,
}

impl StrictDriverDatagramBatchKind {
    fn wire_value(self) -> u8 {
        match self {
            Self::Captured => 1,
            Self::Reply => 2,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub struct StrictDriverDatagramLeaseIdentity {
    lease_generation: u64,
    revision: u64,
    policy_digest: [u8; 32],
    lease_nonce: [u8; 16],
}

impl StrictDriverDatagramLeaseIdentity {
    pub fn new(
        lease_generation: u64,
        revision: u64,
        policy_digest: [u8; 32],
        lease_nonce: [u8; 16],
    ) -> Result<Self> {
        if lease_generation == 0
            || revision == 0
            || policy_digest.iter().all(|byte| *byte == 0)
            || lease_nonce.iter().all(|byte| *byte == 0)
        {
            bail!("strict driver datagram lease identity is invalid");
        }
        Ok(Self {
            lease_generation,
            revision,
            policy_digest,
            lease_nonce,
        })
    }

    pub fn lease_generation(&self) -> u64 {
        self.lease_generation
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub struct StrictDriverDatagramLeaseWindow {
    current: StrictDriverDatagramLeaseIdentity,
    previous: Option<StrictDriverDatagramLeaseIdentity>,
}

impl StrictDriverDatagramLeaseWindow {
    pub fn new(current: StrictDriverDatagramLeaseIdentity) -> Self {
        Self {
            current,
            previous: None,
        }
    }

    pub fn renewed(self, next: StrictDriverDatagramLeaseIdentity) -> Result<Self> {
        if next.lease_generation <= self.current.lease_generation
            || next.revision != self.current.revision
            || next.policy_digest != self.current.policy_digest
            || next.lease_nonce != self.current.lease_nonce
        {
            bail!("strict driver datagram lease renewal identity is invalid");
        }
        Ok(Self {
            current: next,
            previous: Some(self.current),
        })
    }

    pub fn current(&self) -> StrictDriverDatagramLeaseIdentity {
        self.current
    }

    pub fn accepts(&self, identity: StrictDriverDatagramLeaseIdentity) -> bool {
        identity == self.current || self.previous == Some(identity)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct StrictDriverDatagramFlags(u32);

impl StrictDriverDatagramFlags {
    pub const NONE: Self = Self(0);
    pub const DNS: Self = Self(1 << 0);
    pub const QUIC: Self = Self(1 << 1);

    pub fn contains(self, flag: Self) -> bool {
        self.0 & flag.0 == flag.0
    }
}

pub struct StrictDriverDatagramBatchBuilder<'a> {
    output: &'a mut [u8],
    cursor: usize,
    record_count: usize,
}

impl<'a> StrictDriverDatagramBatchBuilder<'a> {
    pub fn new(
        output: &'a mut [u8],
        kind: StrictDriverDatagramBatchKind,
        identity: StrictDriverDatagramLeaseIdentity,
    ) -> Result<Self> {
        if output.len() < BATCH_HEADER_BYTES {
            bail!("strict driver datagram batch output is too small");
        }
        output[..BATCH_HEADER_BYTES].fill(0);
        output[..MAGIC.len()].copy_from_slice(MAGIC);
        write_u16(output, 4, PROTOCOL);
        write_u16(output, 6, BATCH_HEADER_BYTES as u16);
        output[8] = kind.wire_value();
        write_u64(output, 24, identity.lease_generation);
        write_u64(output, 32, identity.revision);
        output[40..72].copy_from_slice(&identity.policy_digest);
        output[72..88].copy_from_slice(&identity.lease_nonce);
        Ok(Self {
            output,
            cursor: BATCH_HEADER_BYTES,
            record_count: 0,
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn push(
        &mut self,
        flow_token: u64,
        sequence: u64,
        target_group_index: u16,
        flags: StrictDriverDatagramFlags,
        local_endpoint: SocketAddr,
        remote_endpoint: SocketAddr,
        payload: &[u8],
    ) -> Result<()> {
        validate_record(
            flow_token,
            sequence,
            target_group_index,
            flags,
            local_endpoint,
            remote_endpoint,
            payload.len(),
        )?;
        if self.record_count >= STRICT_DRIVER_DATAGRAM_MAX_RECORDS {
            bail!("strict driver datagram batch record limit is reached");
        }
        let unpadded_bytes = RECORD_HEADER_BYTES
            .checked_add(payload.len())
            .context("strict driver datagram record size overflow")?;
        let record_bytes = align_to_eight(unpadded_bytes)?;
        let next = self
            .cursor
            .checked_add(record_bytes)
            .context("strict driver datagram batch size overflow")?;
        if next > self.output.len() || next > STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES {
            bail!("strict driver datagram batch output capacity is exceeded");
        }

        let record = &mut self.output[self.cursor..next];
        record.fill(0);
        write_u32(record, 0, record_bytes as u32);
        write_u32(record, 4, payload.len() as u32);
        write_u64(record, 8, flow_token);
        write_u64(record, 16, sequence);
        write_u16(record, 24, target_group_index);
        record[27] = IP_PROTOCOL_UDP;
        write_u32(record, 28, flags.0);
        write_endpoint(record, local_endpoint, remote_endpoint)?;
        record[RECORD_HEADER_BYTES..RECORD_HEADER_BYTES + payload.len()].copy_from_slice(payload);
        self.cursor = next;
        self.record_count += 1;
        Ok(())
    }

    pub fn finish(self) -> Result<&'a [u8]> {
        if self.record_count == 0 {
            bail!("strict driver datagram batch cannot be empty");
        }
        write_u32(self.output, 12, self.cursor as u32);
        write_u32(self.output, 16, self.record_count as u32);
        Ok(&self.output[..self.cursor])
    }
}

pub struct StrictDriverDatagramBatch<'a> {
    input: &'a [u8],
    record_count: usize,
}

impl<'a> StrictDriverDatagramBatch<'a> {
    pub fn decode(
        input: &'a [u8],
        expected_kind: StrictDriverDatagramBatchKind,
        expected_identity: StrictDriverDatagramLeaseIdentity,
    ) -> Result<Self> {
        Self::decode_where(input, expected_kind, |identity| {
            identity == expected_identity
        })
    }

    pub fn decode_with_window(
        input: &'a [u8],
        expected_kind: StrictDriverDatagramBatchKind,
        expected_window: StrictDriverDatagramLeaseWindow,
    ) -> Result<Self> {
        Self::decode_where(input, expected_kind, |identity| {
            expected_window.accepts(identity)
        })
    }

    fn decode_where(
        input: &'a [u8],
        expected_kind: StrictDriverDatagramBatchKind,
        identity_is_accepted: impl FnOnce(StrictDriverDatagramLeaseIdentity) -> bool,
    ) -> Result<Self> {
        if input.len() < BATCH_HEADER_BYTES
            || input.len() > STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES
            || &input[..MAGIC.len()] != MAGIC
            || read_u16(input, 4)? != PROTOCOL
            || usize::from(read_u16(input, 6)?) != BATCH_HEADER_BYTES
            || input[8] != expected_kind.wire_value()
            || input[9..12].iter().any(|byte| *byte != 0)
            || read_u32(input, 12)? as usize != input.len()
            || input[20..24].iter().any(|byte| *byte != 0)
            || input[88..BATCH_HEADER_BYTES].iter().any(|byte| *byte != 0)
        {
            bail!("strict driver datagram batch header is invalid");
        }
        let record_count = read_u32(input, 16)? as usize;
        if record_count == 0 || record_count > STRICT_DRIVER_DATAGRAM_MAX_RECORDS {
            bail!("strict driver datagram batch record count is invalid");
        }
        let identity = StrictDriverDatagramLeaseIdentity::new(
            read_u64(input, 24)?,
            read_u64(input, 32)?,
            input[40..72]
                .try_into()
                .expect("strict driver policy digest has a fixed width"),
            input[72..88]
                .try_into()
                .expect("strict driver lease nonce has a fixed width"),
        )?;
        if !identity_is_accepted(identity) {
            bail!("strict driver datagram batch lease identity is stale or mismatched");
        }

        let mut cursor = BATCH_HEADER_BYTES;
        for _ in 0..record_count {
            let record = validated_record_slice(input, cursor)?;
            cursor = cursor
                .checked_add(record.len())
                .context("strict driver datagram batch cursor overflow")?;
        }
        if cursor != input.len() {
            bail!("strict driver datagram batch has trailing bytes");
        }
        Ok(Self {
            input,
            record_count,
        })
    }

    pub fn record_count(&self) -> usize {
        self.record_count
    }

    pub fn records(&self) -> StrictDriverDatagramRecords<'_> {
        StrictDriverDatagramRecords {
            input: self.input,
            cursor: BATCH_HEADER_BYTES,
            remaining: self.record_count,
        }
    }
}

pub struct StrictDriverDatagramRecords<'a> {
    input: &'a [u8],
    cursor: usize,
    remaining: usize,
}

impl<'a> Iterator for StrictDriverDatagramRecords<'a> {
    type Item = StrictDriverDatagramRecord<'a>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.remaining == 0 {
            return None;
        }
        let record = validated_record_slice(self.input, self.cursor)
            .expect("decoded strict driver datagram records remain valid");
        self.cursor += record.len();
        self.remaining -= 1;
        Some(StrictDriverDatagramRecord { input: record })
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        (self.remaining, Some(self.remaining))
    }
}

impl ExactSizeIterator for StrictDriverDatagramRecords<'_> {}

pub struct StrictDriverDatagramRecord<'a> {
    input: &'a [u8],
}

impl StrictDriverDatagramRecord<'_> {
    pub fn flow_token(&self) -> u64 {
        read_u64(self.input, 8).expect("validated flow token")
    }

    pub fn sequence(&self) -> u64 {
        read_u64(self.input, 16).expect("validated datagram sequence")
    }

    pub fn target_group_index(&self) -> u16 {
        read_u16(self.input, 24).expect("validated target-group index")
    }

    pub fn flags(&self) -> StrictDriverDatagramFlags {
        StrictDriverDatagramFlags(read_u32(self.input, 28).expect("validated datagram flags"))
    }

    pub fn local_endpoint(&self) -> SocketAddr {
        parse_endpoint(self.input, true).expect("validated local endpoint")
    }

    pub fn remote_endpoint(&self) -> SocketAddr {
        parse_endpoint(self.input, false).expect("validated remote endpoint")
    }

    pub fn payload(&self) -> &[u8] {
        let payload_bytes =
            read_u32(self.input, 4).expect("validated datagram payload length") as usize;
        &self.input[RECORD_HEADER_BYTES..RECORD_HEADER_BYTES + payload_bytes]
    }
}

fn validated_record_slice(input: &[u8], cursor: usize) -> Result<&[u8]> {
    let header = input
        .get(cursor..cursor + RECORD_HEADER_BYTES)
        .context("strict driver datagram record header is truncated")?;
    let record_bytes = read_u32(header, 0)? as usize;
    let payload_bytes = read_u32(header, 4)? as usize;
    let expected_record_bytes = align_to_eight(
        RECORD_HEADER_BYTES
            .checked_add(payload_bytes)
            .context("strict driver datagram record size overflow")?,
    )?;
    if record_bytes != expected_record_bytes
        || payload_bytes == 0
        || payload_bytes > STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES
    {
        bail!("strict driver datagram record size is invalid");
    }
    let end = cursor
        .checked_add(record_bytes)
        .context("strict driver datagram record offset overflow")?;
    let record = input
        .get(cursor..end)
        .context("strict driver datagram record is truncated")?;
    let flags = StrictDriverDatagramFlags(read_u32(record, 28)?);
    let local_endpoint = parse_endpoint(record, true)?;
    let remote_endpoint = parse_endpoint(record, false)?;
    validate_record(
        read_u64(record, 8)?,
        read_u64(record, 16)?,
        read_u16(record, 24)?,
        flags,
        local_endpoint,
        remote_endpoint,
        payload_bytes,
    )?;
    if record[27] != IP_PROTOCOL_UDP
        || record[68..RECORD_HEADER_BYTES]
            .iter()
            .any(|byte| *byte != 0)
        || record[RECORD_HEADER_BYTES + payload_bytes..]
            .iter()
            .any(|byte| *byte != 0)
    {
        bail!("strict driver datagram record is noncanonical");
    }
    Ok(record)
}

#[allow(clippy::too_many_arguments)]
fn validate_record(
    flow_token: u64,
    sequence: u64,
    target_group_index: u16,
    flags: StrictDriverDatagramFlags,
    local_endpoint: SocketAddr,
    remote_endpoint: SocketAddr,
    payload_bytes: usize,
) -> Result<()> {
    if flow_token == 0
        || sequence == 0
        || target_group_index >= 128
        || flags.0 & !KNOWN_FLAGS != 0
        || payload_bytes == 0
        || payload_bytes > STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES
        || !safe_local_endpoint(local_endpoint)
        || !safe_remote_endpoint(remote_endpoint)
        || local_endpoint.is_ipv4() != remote_endpoint.is_ipv4()
    {
        bail!("strict driver datagram record metadata is invalid");
    }
    Ok(())
}

fn safe_local_endpoint(endpoint: SocketAddr) -> bool {
    if endpoint.port() == 0 {
        return false;
    }
    match endpoint {
        SocketAddr::V4(endpoint) => {
            !endpoint.ip().is_unspecified()
                && !endpoint.ip().is_multicast()
                && *endpoint.ip() != Ipv4Addr::BROADCAST
        }
        SocketAddr::V6(endpoint) => {
            endpoint.flowinfo() == 0
                && endpoint.scope_id() == 0
                && !endpoint.ip().is_unspecified()
                && !endpoint.ip().is_multicast()
                && endpoint.ip().to_ipv4_mapped().is_none()
        }
    }
}

fn safe_remote_endpoint(endpoint: SocketAddr) -> bool {
    if endpoint.port() == 0 {
        return false;
    }
    match endpoint {
        SocketAddr::V4(endpoint) => {
            !endpoint.ip().is_unspecified()
                && !endpoint.ip().is_loopback()
                && !endpoint.ip().is_multicast()
                && !endpoint.ip().is_link_local()
                && *endpoint.ip() != Ipv4Addr::BROADCAST
        }
        SocketAddr::V6(endpoint) => {
            let first_segment = endpoint.ip().segments()[0];
            endpoint.flowinfo() == 0
                && endpoint.scope_id() == 0
                && !endpoint.ip().is_unspecified()
                && !endpoint.ip().is_loopback()
                && !endpoint.ip().is_multicast()
                && first_segment & 0xffc0 != 0xfe80
                && endpoint.ip().to_ipv4_mapped().is_none()
        }
    }
}

fn write_endpoint(record: &mut [u8], local: SocketAddr, remote: SocketAddr) -> Result<()> {
    write_u16(record, 32, local.port());
    write_u16(record, 34, remote.port());
    match (local.ip(), remote.ip()) {
        (IpAddr::V4(local), IpAddr::V4(remote)) => {
            record[26] = ADDRESS_FAMILY_V4;
            record[36..40].copy_from_slice(&local.octets());
            record[52..56].copy_from_slice(&remote.octets());
        }
        (IpAddr::V6(local), IpAddr::V6(remote)) => {
            record[26] = ADDRESS_FAMILY_V6;
            record[36..52].copy_from_slice(&local.octets());
            record[52..68].copy_from_slice(&remote.octets());
        }
        _ => bail!("strict driver datagram endpoint families are inconsistent"),
    }
    Ok(())
}

fn parse_endpoint(record: &[u8], local: bool) -> Result<SocketAddr> {
    let port = read_u16(record, if local { 32 } else { 34 })?;
    let address_offset = if local { 36 } else { 52 };
    match record[26] {
        ADDRESS_FAMILY_V4 => {
            if record[address_offset + 4..address_offset + 16]
                .iter()
                .any(|byte| *byte != 0)
            {
                bail!("strict driver datagram IPv4 address padding is noncanonical");
            }
            Ok(SocketAddr::V4(SocketAddrV4::new(
                Ipv4Addr::new(
                    record[address_offset],
                    record[address_offset + 1],
                    record[address_offset + 2],
                    record[address_offset + 3],
                ),
                port,
            )))
        }
        ADDRESS_FAMILY_V6 => Ok(SocketAddr::V6(SocketAddrV6::new(
            Ipv6Addr::from(
                <[u8; 16]>::try_from(&record[address_offset..address_offset + 16])
                    .expect("strict driver IPv6 address has a fixed width"),
            ),
            port,
            0,
            0,
        ))),
        _ => bail!("strict driver datagram address family is invalid"),
    }
}

fn align_to_eight(value: usize) -> Result<usize> {
    value
        .checked_add(7)
        .map(|value| value & !7)
        .context("strict driver datagram alignment overflow")
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
    Ok(u16::from_le_bytes(
        input
            .get(offset..offset + 2)
            .context("strict driver datagram u16 is truncated")?
            .try_into()
            .expect("strict driver datagram u16 has a fixed width"),
    ))
}

fn read_u32(input: &[u8], offset: usize) -> Result<u32> {
    Ok(u32::from_le_bytes(
        input
            .get(offset..offset + 4)
            .context("strict driver datagram u32 is truncated")?
            .try_into()
            .expect("strict driver datagram u32 has a fixed width"),
    ))
}

fn read_u64(input: &[u8], offset: usize) -> Result<u64> {
    Ok(u64::from_le_bytes(
        input
            .get(offset..offset + 8)
            .context("strict driver datagram u64 is truncated")?
            .try_into()
            .expect("strict driver datagram u64 has a fixed width"),
    ))
}

#[cfg(test)]
mod tests {
    use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6};

    use super::*;

    #[test]
    fn batch_round_trip_is_canonical_and_borrowed() {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let mut storage = [0_u8; STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES];
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut storage,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        builder
            .push(
                1,
                1,
                3,
                StrictDriverDatagramFlags::DNS,
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(10, 0, 0, 2), 53000)),
                SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::new(8, 8, 8, 8), 53)),
                b"dns",
            )
            .unwrap();
        builder
            .push(
                2,
                1,
                4,
                StrictDriverDatagramFlags::QUIC,
                SocketAddr::V6(SocketAddrV6::new(
                    Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1),
                    53001,
                    0,
                    0,
                )),
                SocketAddr::V6(SocketAddrV6::new(
                    Ipv6Addr::new(0x2001, 0x4860, 0x4860, 0, 0, 0, 0, 0x8888),
                    443,
                    0,
                    0,
                )),
                b"quic",
            )
            .unwrap();
        let bytes = builder.finish().unwrap();

        let batch = StrictDriverDatagramBatch::decode(
            bytes,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        assert_eq!(batch.record_count(), 2);
        let records: Vec<_> = batch.records().collect();
        assert_eq!(records[0].flow_token(), 1);
        assert_eq!(records[0].target_group_index(), 3);
        assert_eq!(records[0].payload(), b"dns");
        assert_eq!(records[1].flags(), StrictDriverDatagramFlags::QUIC);
        assert_eq!(records[1].remote_endpoint().port(), 443);
        assert_eq!(records[1].payload(), b"quic");
    }

    #[test]
    fn batch_rejects_wrong_identity_tampering_and_noncanonical_padding() {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let mut storage = [0_u8; 512];
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut storage,
            StrictDriverDatagramBatchKind::Reply,
            identity,
        )
        .unwrap();
        builder
            .push(
                1,
                1,
                3,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "1.1.1.1:443".parse().unwrap(),
                b"reply",
            )
            .unwrap();
        let encoded = builder.finish().unwrap().to_vec();

        let wrong = StrictDriverDatagramLeaseIdentity::new(8, 91, [0xab; 32], [0x5a; 16]).unwrap();
        assert!(StrictDriverDatagramBatch::decode(
            &encoded,
            StrictDriverDatagramBatchKind::Reply,
            wrong,
        )
        .is_err());
        assert!(StrictDriverDatagramBatch::decode(
            &encoded,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .is_err());

        let mut tampered = encoded.clone();
        *tampered.last_mut().unwrap() = 1;
        assert!(StrictDriverDatagramBatch::decode(
            &tampered,
            StrictDriverDatagramBatchKind::Reply,
            identity,
        )
        .is_err());
        tampered = encoded;
        tampered[88] = 1;
        assert!(StrictDriverDatagramBatch::decode(
            &tampered,
            StrictDriverDatagramBatchKind::Reply,
            identity,
        )
        .is_err());

        let mut unknown_flags = tampered;
        unknown_flags[88] = 0;
        unknown_flags[BATCH_HEADER_BYTES + 28] = 0x80;
        assert!(StrictDriverDatagramBatch::decode(
            &unknown_flags,
            StrictDriverDatagramBatchKind::Reply,
            identity,
        )
        .is_err());
    }

    #[test]
    fn builder_enforces_payload_record_and_endpoint_bounds() {
        let identity =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let mut storage = [0_u8; STRICT_DRIVER_DATAGRAM_MAX_BATCH_BYTES];
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut storage,
            StrictDriverDatagramBatchKind::Captured,
            identity,
        )
        .unwrap();
        assert!(builder
            .push(
                0,
                1,
                0,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "1.1.1.1:443".parse().unwrap(),
                b"payload",
            )
            .is_err());
        assert!(builder
            .push(
                1,
                1,
                0,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "127.0.0.1:443".parse().unwrap(),
                b"payload",
            )
            .is_err());
        assert!(builder
            .push(
                1,
                1,
                0,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "1.1.1.1:443".parse().unwrap(),
                &vec![0; STRICT_DRIVER_DATAGRAM_MAX_PAYLOAD_BYTES + 1],
            )
            .is_err());
        assert!(builder
            .push(
                1,
                1,
                0,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "1.1.1.1:443".parse().unwrap(),
                &[],
            )
            .is_err());
        for token in 1..=STRICT_DRIVER_DATAGRAM_MAX_RECORDS as u64 {
            builder
                .push(
                    token,
                    1,
                    0,
                    StrictDriverDatagramFlags::NONE,
                    "10.0.0.2:53000".parse().unwrap(),
                    "1.1.1.1:443".parse().unwrap(),
                    b"x",
                )
                .unwrap();
        }
        assert!(builder
            .push(
                65,
                1,
                0,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "1.1.1.1:443".parse().unwrap(),
                b"x",
            )
            .is_err());
        let batch = builder.finish().unwrap();
        assert_eq!(
            StrictDriverDatagramBatch::decode(
                batch,
                StrictDriverDatagramBatchKind::Captured,
                identity,
            )
            .unwrap()
            .record_count(),
            STRICT_DRIVER_DATAGRAM_MAX_RECORDS
        );
    }

    #[test]
    fn lease_window_accepts_only_current_and_previous_attested_generation() {
        let identity7 =
            StrictDriverDatagramLeaseIdentity::new(7, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let identity8 =
            StrictDriverDatagramLeaseIdentity::new(8, 91, [0xab; 32], [0x5a; 16]).unwrap();
        let identity9 =
            StrictDriverDatagramLeaseIdentity::new(9, 91, [0xab; 32], [0x5a; 16]).unwrap();

        let window = StrictDriverDatagramLeaseWindow::new(identity7)
            .renewed(identity8)
            .unwrap();
        assert!(window.accepts(identity7));
        assert!(window.accepts(identity8));
        assert!(!window.accepts(identity9));
        let window = window.renewed(identity9).unwrap();
        assert!(!window.accepts(identity7));
        assert!(window.accepts(identity8));
        assert!(window.accepts(identity9));

        assert!(window
            .renewed(
                StrictDriverDatagramLeaseIdentity::new(10, 92, [0xab; 32], [0x5a; 16]).unwrap()
            )
            .is_err());
        assert!(window
            .renewed(
                StrictDriverDatagramLeaseIdentity::new(10, 91, [0xac; 32], [0x5a; 16]).unwrap()
            )
            .is_err());
        assert!(window
            .renewed(
                StrictDriverDatagramLeaseIdentity::new(10, 91, [0xab; 32], [0x5b; 16]).unwrap()
            )
            .is_err());
        assert!(window.renewed(identity9).is_err());

        let mut storage = [0_u8; 512];
        let mut builder = StrictDriverDatagramBatchBuilder::new(
            &mut storage,
            StrictDriverDatagramBatchKind::Captured,
            identity8,
        )
        .unwrap();
        builder
            .push(
                1,
                1,
                0,
                StrictDriverDatagramFlags::NONE,
                "10.0.0.2:53000".parse().unwrap(),
                "1.1.1.1:443".parse().unwrap(),
                b"payload",
            )
            .unwrap();
        let encoded = builder.finish().unwrap();
        assert_eq!(
            StrictDriverDatagramBatch::decode_with_window(
                encoded,
                StrictDriverDatagramBatchKind::Captured,
                window,
            )
            .unwrap()
            .record_count(),
            1
        );
    }
}
