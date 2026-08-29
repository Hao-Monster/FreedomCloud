use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

use anyhow::{bail, Context, Result};

const REDIRECT_CONTEXT_MAGIC: u32 = 0x4358_4346;
const REDIRECT_CONTEXT_PROTOCOL: u16 = 1;
const REDIRECT_CONTEXT_BYTES: usize = 112;
const MAX_TARGET_GROUPS: usize = 128;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StrictRedirectTransport {
    Tcp,
    Udp,
}

impl StrictRedirectTransport {
    fn protocol_number(self) -> u8 {
        match self {
            Self::Tcp => 6,
            Self::Udp => 17,
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct StrictRedirectLeaseBinding {
    generation: u64,
    previous_generation: Option<u64>,
    revision: u64,
    policy_digest: [u8; 32],
    nonce: [u8; 16],
    target_group_count: u16,
}

impl StrictRedirectLeaseBinding {
    pub fn new(
        generation: u64,
        revision: u64,
        policy_digest: &str,
        nonce: [u8; 16],
        target_group_count: usize,
    ) -> Result<Self> {
        if generation == 0 || revision == 0 {
            bail!("strict redirect lease generation and revision must be positive");
        }
        let policy_digest = decode_sha256(policy_digest)?;
        if policy_digest.iter().all(|byte| *byte == 0) || nonce.iter().all(|byte| *byte == 0) {
            bail!("strict redirect lease identity is empty");
        }
        if target_group_count == 0 || target_group_count > MAX_TARGET_GROUPS {
            bail!("strict redirect lease target-group count is invalid");
        }
        Ok(Self {
            generation,
            previous_generation: None,
            revision,
            policy_digest,
            nonce,
            target_group_count: target_group_count as u16,
        })
    }

    pub(crate) fn renewed(&self, generation: u64) -> Result<Self> {
        if generation <= self.generation {
            bail!("strict redirect lease generation did not advance");
        }
        let mut renewed = self.clone();
        renewed.previous_generation = Some(self.generation);
        renewed.generation = generation;
        Ok(renewed)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StrictRedirectContext {
    target_group_index: u16,
    original_destination: SocketAddr,
    transport: StrictRedirectTransport,
}

impl StrictRedirectContext {
    pub fn target_group_index(&self) -> u16 {
        self.target_group_index
    }

    pub fn original_destination(&self) -> SocketAddr {
        self.original_destination
    }

    pub fn transport(&self) -> StrictRedirectTransport {
        self.transport
    }
}

pub fn parse_strict_redirect_context(
    bytes: &[u8],
    binding: &StrictRedirectLeaseBinding,
    expected_transport: StrictRedirectTransport,
) -> Result<StrictRedirectContext> {
    if bytes.len() != REDIRECT_CONTEXT_BYTES
        || read_u32(bytes, 0)? != REDIRECT_CONTEXT_MAGIC
        || read_u16(bytes, 4)? != REDIRECT_CONTEXT_PROTOCOL
        || read_u16(bytes, 6)? as usize != REDIRECT_CONTEXT_BYTES
        || {
            let generation = read_u64(bytes, 8)?;
            generation != binding.generation && binding.previous_generation != Some(generation)
        }
        || read_u64(bytes, 16)? != binding.revision
        || !constant_time_eq(&bytes[24..56], &binding.policy_digest)
        || !constant_time_eq(&bytes[56..72], &binding.nonce)
        || bytes[78..80].iter().any(|byte| *byte != 0)
        || bytes[96..112].iter().any(|byte| *byte != 0)
    {
        bail!("strict redirect context is not bound to the active lease");
    }

    let target_group_index = read_u16(bytes, 72)?;
    if target_group_index >= binding.target_group_count {
        bail!("strict redirect context target group is out of range");
    }
    if bytes[75] != expected_transport.protocol_number() {
        bail!("strict redirect context transport does not match the listener");
    }
    let port = read_u16(bytes, 76)?;
    if port == 0 {
        bail!("strict redirect context destination port is invalid");
    }

    let ip = match bytes[74] {
        4 => {
            if bytes[84..96].iter().any(|byte| *byte != 0) {
                bail!("strict IPv4 redirect context has nonzero tail bytes");
            }
            let address = Ipv4Addr::new(bytes[80], bytes[81], bytes[82], bytes[83]);
            if address.is_unspecified()
                || address.is_loopback()
                || address.is_multicast()
                || address == Ipv4Addr::BROADCAST
            {
                bail!("strict IPv4 redirect destination is unsafe");
            }
            IpAddr::V4(address)
        }
        6 => {
            let address = Ipv6Addr::from(
                <[u8; 16]>::try_from(&bytes[80..96])
                    .expect("redirect context contains an exact IPv6 field"),
            );
            if address.is_unspecified() || address.is_loopback() || address.is_multicast() {
                bail!("strict IPv6 redirect destination is unsafe");
            }
            IpAddr::V6(address)
        }
        _ => bail!("strict redirect context address family is invalid"),
    };

    Ok(StrictRedirectContext {
        target_group_index,
        original_destination: SocketAddr::new(ip, port),
        transport: expected_transport,
    })
}

fn decode_sha256(value: &str) -> Result<[u8; 32]> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("strict redirect policy digest is invalid");
    }
    let mut output = [0_u8; 32];
    for (index, byte) in output.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16)
            .context("strict redirect policy digest is not hexadecimal")?;
    }
    Ok(output)
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.iter()
        .zip(right)
        .fold(0_u8, |difference, (left, right)| {
            difference | (left ^ right)
        })
        == 0
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16> {
    Ok(u16::from_le_bytes(
        bytes
            .get(offset..offset + 2)
            .context("strict redirect context integer is truncated")?
            .try_into()
            .expect("validated integer length"),
    ))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32> {
    Ok(u32::from_le_bytes(
        bytes
            .get(offset..offset + 4)
            .context("strict redirect context integer is truncated")?
            .try_into()
            .expect("validated integer length"),
    ))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64> {
    Ok(u64::from_le_bytes(
        bytes
            .get(offset..offset + 8)
            .context("strict redirect context integer is truncated")?
            .try_into()
            .expect("validated integer length"),
    ))
}

#[cfg(test)]
mod tests {
    #[test]
    fn kernel_header_tracks_the_redirect_context_contract() {
        let header = include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../windows/strict-driver/include/flclash_strict_wire.h"
        ));
        for required in [
            "FCX_STRICT_REDIRECT_CONTEXT_MAGIC",
            "FCX_STRICT_REDIRECT_CONTEXT_PROTOCOL",
            "FCX_STRICT_REDIRECT_CONTEXT_BYTES ((UINT16)112u)",
            "typedef struct _FCX_STRICT_REDIRECT_CONTEXT",
            "C_ASSERT(sizeof(FCX_STRICT_REDIRECT_CONTEXT) == FCX_STRICT_REDIRECT_CONTEXT_BYTES)",
        ] {
            assert!(header.contains(required), "missing kernel ABI: {required}");
        }
    }
}
