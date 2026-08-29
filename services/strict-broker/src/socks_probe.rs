use std::io::{Read, Write};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpStream};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};

const SOCKS_VERSION: u8 = 0x05;
const USERNAME_PASSWORD_METHOD: u8 = 0x02;
const USERNAME_PASSWORD_VERSION: u8 = 0x01;
const SOCKS_CONNECT: u8 = 0x01;
const MAX_PROBE_TIMEOUT: Duration = Duration::from_secs(30);

pub struct Socks5ProxyIngress {
    endpoint: SocketAddrV4,
    username: String,
    password: String,
}

impl Socks5ProxyIngress {
    pub fn new(endpoint: SocketAddrV4, username: String, password: String) -> Result<Self> {
        if endpoint.ip() != &Ipv4Addr::LOCALHOST || endpoint.port() == 0 {
            bail!("SOCKS health ingress must be exact IPv4 loopback");
        }
        validate_credential(&username)?;
        validate_credential(&password)?;
        Ok(Self {
            endpoint,
            username,
            password,
        })
    }

    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }
}

pub enum Socks5ConnectTarget {
    Domain { host: String, port: u16 },
    Ip(SocketAddr),
}

impl Socks5ConnectTarget {
    pub fn domain(host: impl Into<String>, port: u16) -> Result<Self> {
        let host = host.into();
        validate_domain(&host)?;
        if port == 0 {
            bail!("SOCKS health target port is invalid");
        }
        Ok(Self::Domain { host, port })
    }

    pub fn ip(endpoint: SocketAddr) -> Result<Self> {
        if endpoint.port() == 0 {
            bail!("SOCKS health target port is invalid");
        }
        Ok(Self::Ip(endpoint))
    }
}

pub fn probe_socks5_connect(
    ingress: &Socks5ProxyIngress,
    target: &Socks5ConnectTarget,
    timeout: Duration,
) -> Result<()> {
    if timeout.is_zero() || timeout > MAX_PROBE_TIMEOUT {
        bail!("SOCKS health probe timeout is invalid");
    }
    let deadline = Instant::now() + timeout;
    let mut stream = TcpStream::connect_timeout(&SocketAddr::V4(ingress.endpoint), timeout)
        .context("connect SOCKS health ingress")?;

    write_deadline(
        &mut stream,
        &[SOCKS_VERSION, 0x01, USERNAME_PASSWORD_METHOD],
        deadline,
    )?;
    let mut method = [0_u8; 2];
    read_deadline(&mut stream, &mut method, deadline)?;
    if method != [SOCKS_VERSION, USERNAME_PASSWORD_METHOD] {
        bail!("SOCKS health ingress did not require the configured authentication");
    }

    let mut authentication =
        Vec::with_capacity(3 + ingress.username.len() + ingress.password.len());
    authentication.push(USERNAME_PASSWORD_VERSION);
    authentication.push(ingress.username.len() as u8);
    authentication.extend_from_slice(ingress.username.as_bytes());
    authentication.push(ingress.password.len() as u8);
    authentication.extend_from_slice(ingress.password.as_bytes());
    write_deadline(&mut stream, &authentication, deadline)?;
    let mut authentication_result = [0_u8; 2];
    read_deadline(&mut stream, &mut authentication_result, deadline)?;
    if authentication_result != [USERNAME_PASSWORD_VERSION, 0x00] {
        bail!("SOCKS health ingress rejected authentication");
    }

    let connect = encode_connect_request(target);
    write_deadline(&mut stream, &connect, deadline)?;
    let mut reply = [0_u8; 4];
    read_deadline(&mut stream, &mut reply, deadline)?;
    if reply[0] != SOCKS_VERSION || reply[2] != 0x00 {
        bail!("SOCKS health ingress returned an invalid CONNECT response");
    }
    if reply[1] != 0x00 {
        bail!("SOCKS health ingress rejected CONNECT");
    }
    consume_bound_address(&mut stream, reply[3], deadline)?;
    Ok(())
}

fn encode_connect_request(target: &Socks5ConnectTarget) -> Vec<u8> {
    let mut request = vec![SOCKS_VERSION, SOCKS_CONNECT, 0x00];
    match target {
        Socks5ConnectTarget::Domain { host, port } => {
            request.push(0x03);
            request.push(host.len() as u8);
            request.extend_from_slice(host.as_bytes());
            request.extend_from_slice(&port.to_be_bytes());
        }
        Socks5ConnectTarget::Ip(SocketAddr::V4(endpoint)) => {
            request.push(0x01);
            request.extend_from_slice(&endpoint.ip().octets());
            request.extend_from_slice(&endpoint.port().to_be_bytes());
        }
        Socks5ConnectTarget::Ip(SocketAddr::V6(endpoint)) => {
            request.push(0x04);
            request.extend_from_slice(&endpoint.ip().octets());
            request.extend_from_slice(&endpoint.port().to_be_bytes());
        }
    }
    request
}

fn consume_bound_address(
    stream: &mut TcpStream,
    address_type: u8,
    deadline: Instant,
) -> Result<()> {
    let address_bytes = match address_type {
        0x01 => 4,
        0x04 => 16,
        0x03 => {
            let mut length = [0_u8; 1];
            read_deadline(stream, &mut length, deadline)?;
            if length[0] == 0 {
                bail!("SOCKS health ingress returned an empty bound domain");
            }
            usize::from(length[0])
        }
        _ => bail!("SOCKS health ingress returned an invalid address type"),
    };
    let mut remainder = vec![0_u8; address_bytes + 2];
    read_deadline(stream, &mut remainder, deadline)
}

fn write_deadline(stream: &mut TcpStream, bytes: &[u8], deadline: Instant) -> Result<()> {
    let remaining = remaining(deadline)?;
    stream.set_write_timeout(Some(remaining))?;
    stream.write_all(bytes).context("write SOCKS health frame")
}

fn read_deadline(stream: &mut TcpStream, bytes: &mut [u8], deadline: Instant) -> Result<()> {
    let remaining = remaining(deadline)?;
    stream.set_read_timeout(Some(remaining))?;
    stream.read_exact(bytes).context("read SOCKS health frame")
}

fn remaining(deadline: Instant) -> Result<Duration> {
    let remaining = deadline.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
        bail!("SOCKS health probe exceeded its deadline");
    }
    Ok(remaining)
}

fn validate_credential(value: &str) -> Result<()> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("SOCKS health credential is invalid");
    }
    Ok(())
}

fn validate_domain(host: &str) -> Result<()> {
    if host.is_empty()
        || host.len() > 253
        || !host.is_ascii()
        || host.starts_with('.')
        || host.ends_with('.')
        || host.split('.').any(|label| {
            label.is_empty()
                || label.len() > 63
                || label.starts_with('-')
                || label.ends_with('-')
                || !label
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        })
    {
        bail!("SOCKS health target domain is invalid");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::{Ipv4Addr, SocketAddrV4, TcpListener};
    use std::thread;
    use std::time::{Duration, Instant};

    use super::*;

    fn credential(character: char) -> String {
        std::iter::repeat_n(character, 64).collect()
    }

    fn spawn_fake_socks(
        username: String,
        password: String,
        reply_code: u8,
    ) -> (SocketAddrV4, thread::JoinHandle<Vec<u8>>) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let endpoint = match listener.local_addr().unwrap() {
            std::net::SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut greeting = [0_u8; 3];
            stream.read_exact(&mut greeting).unwrap();
            assert_eq!(greeting, [0x05, 0x01, 0x02]);
            stream.write_all(&[0x05, 0x02]).unwrap();

            let mut auth_header = [0_u8; 2];
            stream.read_exact(&mut auth_header).unwrap();
            assert_eq!(auth_header[0], 0x01);
            let mut received_username = vec![0_u8; usize::from(auth_header[1])];
            stream.read_exact(&mut received_username).unwrap();
            let mut password_length = [0_u8; 1];
            stream.read_exact(&mut password_length).unwrap();
            let mut received_password = vec![0_u8; usize::from(password_length[0])];
            stream.read_exact(&mut received_password).unwrap();
            assert_eq!(received_username, username.as_bytes());
            assert_eq!(received_password, password.as_bytes());
            stream.write_all(&[0x01, 0x00]).unwrap();

            let mut connect_header = [0_u8; 4];
            stream.read_exact(&mut connect_header).unwrap();
            assert_eq!(connect_header, [0x05, 0x01, 0x00, 0x03]);
            let mut host_length = [0_u8; 1];
            stream.read_exact(&mut host_length).unwrap();
            let mut host = vec![0_u8; usize::from(host_length[0])];
            stream.read_exact(&mut host).unwrap();
            let mut port = [0_u8; 2];
            stream.read_exact(&mut port).unwrap();
            stream
                .write_all(&[0x05, reply_code, 0x00, 0x01, 127, 0, 0, 1, 0, 1])
                .unwrap();
            [host, port.to_vec()].concat()
        });
        (endpoint, worker)
    }

    #[test]
    fn authenticated_connect_proves_more_than_a_tcp_accept() {
        let username = credential('a');
        let password = credential('b');
        let (endpoint, worker) = spawn_fake_socks(username.clone(), password.clone(), 0x00);
        let ingress = Socks5ProxyIngress::new(endpoint, username, password).unwrap();

        probe_socks5_connect(
            &ingress,
            &Socks5ConnectTarget::domain("health.example", 443).unwrap(),
            Duration::from_secs(1),
        )
        .unwrap();

        let request = worker.join().unwrap();
        assert_eq!(&request[..14], b"health.example");
        assert_eq!(&request[14..], &443_u16.to_be_bytes());
    }

    #[test]
    fn socks_connect_rejection_fails_health() {
        let username = credential('c');
        let password = credential('d');
        let (endpoint, worker) = spawn_fake_socks(username.clone(), password.clone(), 0x05);
        let ingress = Socks5ProxyIngress::new(endpoint, username, password).unwrap();

        assert!(probe_socks5_connect(
            &ingress,
            &Socks5ConnectTarget::domain("health.example", 80).unwrap(),
            Duration::from_secs(1),
        )
        .is_err());
        worker.join().unwrap();
    }

    #[test]
    fn ingress_and_target_inputs_are_closed_and_bounded() {
        assert!(Socks5ProxyIngress::new(
            SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 1080),
            credential('a'),
            credential('b'),
        )
        .is_err());
        assert!(Socks5ProxyIngress::new(
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, 1080),
            "user".into(),
            credential('b'),
        )
        .is_err());
        assert!(Socks5ConnectTarget::domain("bad\n.example", 443).is_err());
        assert!(Socks5ConnectTarget::domain("health.example", 0).is_err());
    }

    #[test]
    fn stalled_socks_handshake_obeys_one_total_deadline() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let endpoint = match listener.local_addr().unwrap() {
            std::net::SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };
        let worker = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut greeting = [0_u8; 3];
            stream.read_exact(&mut greeting).unwrap();
            let mut closed = [0_u8; 1];
            let _ = stream.read(&mut closed);
        });
        let ingress = Socks5ProxyIngress::new(endpoint, credential('e'), credential('f')).unwrap();
        let started = Instant::now();
        assert!(probe_socks5_connect(
            &ingress,
            &Socks5ConnectTarget::domain("health.example", 443).unwrap(),
            Duration::from_millis(25),
        )
        .is_err());
        assert!(started.elapsed() < Duration::from_secs(1));
        worker.join().unwrap();
    }
}
