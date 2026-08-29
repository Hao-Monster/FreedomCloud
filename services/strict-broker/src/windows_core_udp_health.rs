use std::net::{Ipv4Addr, SocketAddrV4, UdpSocket};
use std::time::Duration;

use anyhow::{bail, Context, Result};
use hmac::{Hmac, Mac};
use sha2::Sha256;

const FRAME_BYTES: usize = 80;
const KEY_ID_BYTES: usize = 16;
const TAG_OFFSET: usize = 48;
const MAGIC: &[u8; 4] = b"FCXU";
const VERSION: u8 = 1;
const PING: u8 = 1;
const PONG: u8 = 2;
const MAX_TIMEOUT: Duration = Duration::from_secs(30);

type HmacSha256 = Hmac<Sha256>;

pub(crate) fn probe_core_udp_health(
    endpoint: SocketAddrV4,
    generation: u64,
    username: &str,
    password: &str,
    nonce: [u8; 16],
    timeout: Duration,
) -> Result<()> {
    if endpoint.ip() != &Ipv4Addr::LOCALHOST || endpoint.port() == 0 {
        bail!("strict Core UDP health endpoint is not exact IPv4 loopback");
    }
    if generation == 0 || timeout.is_zero() || timeout > MAX_TIMEOUT {
        bail!("strict Core UDP health probe parameters are invalid");
    }
    if nonce.iter().all(|byte| *byte == 0) {
        bail!("strict Core UDP health nonce is invalid");
    }
    let username = decode_credential(username, "username")?;
    let password = decode_credential(password, "password")?;
    let mut key_id = [0_u8; KEY_ID_BYTES];
    key_id.copy_from_slice(&username[..KEY_ID_BYTES]);
    let ping = build_frame(PING, generation, key_id, nonce, &password)?;

    let socket = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0))
        .context("bind strict Core UDP health probe")?;
    socket
        .set_read_timeout(Some(timeout))
        .context("set strict Core UDP health read timeout")?;
    socket
        .set_write_timeout(Some(timeout))
        .context("set strict Core UDP health write timeout")?;
    socket
        .connect(endpoint)
        .context("connect strict Core UDP health probe")?;
    if socket.send(&ping)? != ping.len() {
        bail!("strict Core UDP health ping was truncated");
    }

    let mut response = [0_u8; FRAME_BYTES + 1];
    let count = socket
        .recv(&mut response)
        .context("receive strict Core UDP health pong")?;
    if count != FRAME_BYTES {
        bail!("strict Core UDP health pong size is invalid");
    }
    validate_pong(
        &response[..FRAME_BYTES],
        generation,
        key_id,
        nonce,
        &password,
    )
}

fn build_frame(
    kind: u8,
    generation: u64,
    key_id: [u8; KEY_ID_BYTES],
    nonce: [u8; 16],
    key: &[u8; 32],
) -> Result<[u8; FRAME_BYTES]> {
    let mut frame = [0_u8; FRAME_BYTES];
    frame[..4].copy_from_slice(MAGIC);
    frame[4] = VERSION;
    frame[5] = kind;
    frame[8..16].copy_from_slice(&generation.to_be_bytes());
    frame[16..32].copy_from_slice(&key_id);
    frame[32..48].copy_from_slice(&nonce);
    let mut mac = HmacSha256::new_from_slice(key).context("initialize strict UDP health HMAC")?;
    mac.update(&frame[..TAG_OFFSET]);
    frame[TAG_OFFSET..].copy_from_slice(&mac.finalize().into_bytes());
    Ok(frame)
}

fn validate_pong(
    frame: &[u8],
    generation: u64,
    key_id: [u8; KEY_ID_BYTES],
    nonce: [u8; 16],
    key: &[u8; 32],
) -> Result<()> {
    if frame.len() != FRAME_BYTES
        || &frame[..4] != MAGIC
        || frame[4] != VERSION
        || frame[5] != PONG
        || frame[6] != 0
        || frame[7] != 0
        || frame[8..16] != generation.to_be_bytes()
        || frame[16..32] != key_id
        || frame[32..48] != nonce
    {
        bail!("strict Core UDP health pong correlation failed");
    }
    let mut mac = HmacSha256::new_from_slice(key).context("initialize strict UDP health HMAC")?;
    mac.update(&frame[..TAG_OFFSET]);
    mac.verify_slice(&frame[TAG_OFFSET..])
        .context("strict Core UDP health pong authentication failed")
}

fn decode_credential(value: &str, label: &str) -> Result<[u8; 32]> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("strict Core UDP health {label} is invalid");
    }
    let mut decoded = [0_u8; 32];
    for (index, byte) in decoded.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16)
            .with_context(|| format!("strict Core UDP health {label} is not hexadecimal"))?;
    }
    if decoded.iter().all(|byte| *byte == 0) {
        bail!("strict Core UDP health {label} cannot be zero");
    }
    Ok(decoded)
}

#[cfg(test)]
mod tests {
    use std::fmt::Write;
    use std::thread;

    use super::*;

    #[test]
    fn frame_has_stable_authenticated_wire_shape() {
        let key_id = [0x11; KEY_ID_BYTES];
        let nonce = [0x22; 16];
        let key = [0x33; 32];
        let frame = build_frame(PING, 7, key_id, nonce, &key).unwrap();

        assert_eq!(frame.len(), FRAME_BYTES);
        assert_eq!(&frame[..4], MAGIC);
        assert_eq!(&frame[8..16], &7_u64.to_be_bytes());
        assert_eq!(
            hex(&frame[TAG_OFFSET..]),
            "99b007f39a825086c1ee37b3e4a1f2b6d67c0395ba78186422a5aa19ca32b2c4"
        );
    }

    #[test]
    fn loopback_probe_requires_a_correlated_authenticated_pong() {
        let server = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0)).unwrap();
        let endpoint = match server.local_addr().unwrap() {
            std::net::SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };
        let key = [0x33; 32];
        let worker = thread::spawn(move || {
            let mut ping = [0_u8; FRAME_BYTES];
            let (count, source) = server.recv_from(&mut ping).unwrap();
            assert_eq!(count, FRAME_BYTES);
            let mut key_id = [0_u8; KEY_ID_BYTES];
            key_id.copy_from_slice(&ping[16..32]);
            let mut nonce = [0_u8; 16];
            nonce.copy_from_slice(&ping[32..48]);
            let pong = build_frame(PONG, 7, key_id, nonce, &key).unwrap();
            server.send_to(&pong, source).unwrap();
        });

        probe_core_udp_health(
            endpoint,
            7,
            &"11".repeat(32),
            &"33".repeat(32),
            [0x22; 16],
            Duration::from_secs(1),
        )
        .unwrap();
        worker.join().unwrap();
    }

    #[test]
    fn pong_rejects_tampering_and_wrong_correlation() {
        let key_id = [0x11; KEY_ID_BYTES];
        let nonce = [0x22; 16];
        let key = [0x33; 32];
        let pong = build_frame(PONG, 7, key_id, nonce, &key).unwrap();
        assert!(validate_pong(&pong, 7, key_id, nonce, &key).is_ok());

        let mut tampered = pong;
        tampered[TAG_OFFSET] ^= 0x80;
        assert!(validate_pong(&tampered, 7, key_id, nonce, &key).is_err());
        assert!(validate_pong(&pong, 8, key_id, nonce, &key).is_err());
        assert!(validate_pong(&pong, 7, key_id, [0x44; 16], &key).is_err());
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
}
