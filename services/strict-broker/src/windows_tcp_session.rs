use std::collections::BTreeSet;
use std::net::{SocketAddrV4, TcpStream};
use std::time::Duration;

use anyhow::{bail, Result};

use crate::{
    connect_windows_redirected_outbound, establish_socks5_connect, query_windows_redirect_socket,
    relay_windows_tcp_bidirectional, Socks5ConnectTarget, Socks5ProxyIngress,
    StrictRedirectContext, StrictRedirectLeaseBinding, StrictRedirectTransport,
    WindowsCoreListenerTrustLease, WindowsPipeShutdown, WindowsTcpRelayLimits,
    WindowsTcpRelayReport,
};

const MAX_SESSION_TIMEOUT: Duration = Duration::from_secs(30);

pub struct WindowsStrictTcpSessionPlan {
    core_owner: CoreOwnership,
    binding: StrictRedirectLeaseBinding,
    ingresses: Vec<Socks5ProxyIngress>,
    connect_timeout: Duration,
    handshake_timeout: Duration,
    relay_limits: WindowsTcpRelayLimits,
}

enum CoreOwnership {
    Verified(WindowsCoreListenerTrustLease),
    #[cfg(test)]
    TestOnly,
}

impl WindowsStrictTcpSessionPlan {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        core_owner: WindowsCoreListenerTrustLease,
        lease_generation: u64,
        revision: u64,
        policy_digest: &str,
        lease_nonce: [u8; 16],
        ingresses: Vec<Socks5ProxyIngress>,
        connect_timeout: Duration,
        handshake_timeout: Duration,
        relay_limits: WindowsTcpRelayLimits,
    ) -> Result<Self> {
        let endpoints = ingresses
            .iter()
            .map(Socks5ProxyIngress::endpoint)
            .collect::<Vec<_>>();
        if core_owner.endpoints() != endpoints || !core_owner.is_running()? {
            bail!("strict TCP session Core ownership lease does not match its ingresses");
        }
        Self::build(
            CoreOwnership::Verified(core_owner),
            lease_generation,
            revision,
            policy_digest,
            lease_nonce,
            ingresses,
            connect_timeout,
            handshake_timeout,
            relay_limits,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn build(
        core_owner: CoreOwnership,
        lease_generation: u64,
        revision: u64,
        policy_digest: &str,
        lease_nonce: [u8; 16],
        ingresses: Vec<Socks5ProxyIngress>,
        connect_timeout: Duration,
        handshake_timeout: Duration,
        relay_limits: WindowsTcpRelayLimits,
    ) -> Result<Self> {
        validate_session_timeout(connect_timeout)?;
        validate_session_timeout(handshake_timeout)?;
        let mut endpoints = BTreeSet::new();
        if ingresses.is_empty()
            || ingresses
                .iter()
                .any(|ingress| !endpoints.insert(ingress.endpoint()))
        {
            bail!("strict TCP session Core ingress set is empty or ambiguous");
        }
        let binding = StrictRedirectLeaseBinding::new(
            lease_generation,
            revision,
            policy_digest,
            lease_nonce,
            ingresses.len(),
        )?;
        Ok(Self {
            core_owner,
            binding,
            ingresses,
            connect_timeout,
            handshake_timeout,
            relay_limits,
        })
    }

    pub fn target_group_count(&self) -> usize {
        self.ingresses.len()
    }

    pub fn core_endpoints(&self) -> Vec<SocketAddrV4> {
        self.ingresses
            .iter()
            .map(Socks5ProxyIngress::endpoint)
            .collect()
    }

    fn ensure_core_running(&self) -> Result<()> {
        match &self.core_owner {
            CoreOwnership::Verified(owner) if owner.is_running()? => Ok(()),
            CoreOwnership::Verified(_) => bail!("strict TCP session Core owner exited"),
            #[cfg(test)]
            CoreOwnership::TestOnly => Ok(()),
        }
    }

    #[cfg(test)]
    #[allow(clippy::too_many_arguments)]
    fn new_for_test(
        lease_generation: u64,
        revision: u64,
        policy_digest: &str,
        lease_nonce: [u8; 16],
        ingresses: Vec<Socks5ProxyIngress>,
        connect_timeout: Duration,
        handshake_timeout: Duration,
        relay_limits: WindowsTcpRelayLimits,
    ) -> Result<Self> {
        Self::build(
            CoreOwnership::TestOnly,
            lease_generation,
            revision,
            policy_digest,
            lease_nonce,
            ingresses,
            connect_timeout,
            handshake_timeout,
            relay_limits,
        )
    }
}

pub fn handle_windows_strict_tcp_connection(
    client: TcpStream,
    plan: &WindowsStrictTcpSessionPlan,
    shutdown: &WindowsPipeShutdown,
) -> Result<WindowsTcpRelayReport> {
    if shutdown.is_requested() {
        bail!("strict TCP session was cancelled before metadata validation");
    }
    plan.ensure_core_running()?;
    let metadata =
        query_windows_redirect_socket(&client, &plan.binding, StrictRedirectTransport::Tcp)?;
    connect_and_relay_with(
        client,
        plan,
        metadata.context(),
        metadata.redirect_records(),
        shutdown,
        connect_windows_redirected_outbound,
    )
}

fn connect_and_relay_with<C>(
    client: TcpStream,
    plan: &WindowsStrictTcpSessionPlan,
    context: StrictRedirectContext,
    redirect_records: &[u8],
    shutdown: &WindowsPipeShutdown,
    connector: C,
) -> Result<WindowsTcpRelayReport>
where
    C: FnOnce(SocketAddrV4, &[u8], Duration) -> Result<TcpStream>,
{
    let ingress = plan
        .ingresses
        .get(usize::from(context.target_group_index()))
        .ok_or_else(|| anyhow::anyhow!("strict TCP session target group is unavailable"))?;
    if shutdown.is_requested() {
        bail!("strict TCP session was cancelled before Core connect");
    }
    plan.ensure_core_running()?;
    let core_socket = connector(ingress.endpoint(), redirect_records, plan.connect_timeout)?;
    let target = Socks5ConnectTarget::ip(context.original_destination())?;
    let upstream = establish_socks5_connect(core_socket, ingress, &target, plan.handshake_timeout)?;
    if shutdown.is_requested() {
        bail!("strict TCP session was cancelled before relay");
    }
    relay_windows_tcp_bidirectional(client, upstream, shutdown, plan.relay_limits)
}

fn validate_session_timeout(timeout: Duration) -> Result<()> {
    if timeout.as_millis() == 0 || timeout > MAX_SESSION_TIMEOUT {
        bail!("strict TCP session timeout is invalid");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::{Ipv4Addr, Shutdown, SocketAddr, TcpListener};
    use std::thread;

    use crate::parse_strict_redirect_context;

    use super::*;

    const CONTEXT_BYTES: usize = 112;

    fn put_u16(bytes: &mut [u8], offset: usize, value: u16) {
        bytes[offset..offset + 2].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u32(bytes: &mut [u8], offset: usize, value: u32) {
        bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }

    fn put_u64(bytes: &mut [u8], offset: usize, value: u64) {
        bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
    }

    fn context(plan: &WindowsStrictTcpSessionPlan) -> StrictRedirectContext {
        let mut bytes = vec![0_u8; CONTEXT_BYTES];
        put_u32(&mut bytes, 0, 0x4358_4346);
        put_u16(&mut bytes, 4, 1);
        put_u16(&mut bytes, 6, CONTEXT_BYTES as u16);
        put_u64(&mut bytes, 8, 3);
        put_u64(&mut bytes, 16, 7);
        bytes[24..56].copy_from_slice(&[0xab; 32]);
        bytes[56..72].copy_from_slice(&[0x11; 16]);
        put_u16(&mut bytes, 72, 1);
        bytes[74] = 4;
        bytes[75] = 6;
        put_u16(&mut bytes, 76, 443);
        bytes[80..84].copy_from_slice(&[203, 0, 113, 10]);
        parse_strict_redirect_context(&bytes, &plan.binding, StrictRedirectTransport::Tcp).unwrap()
    }

    fn credential(character: char) -> String {
        std::iter::repeat_n(character, 64).collect()
    }

    fn connected_pair() -> (TcpStream, TcpStream) {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (server, _) = listener.accept().unwrap();
        (client, server)
    }

    fn ingress(port: u16, character: char) -> Socks5ProxyIngress {
        Socks5ProxyIngress::new(
            SocketAddrV4::new(Ipv4Addr::LOCALHOST, port),
            credential(character),
            credential(character),
        )
        .unwrap()
    }

    #[test]
    fn session_plan_is_lease_bound_and_rejects_ambiguous_core_ingresses() {
        let limits = WindowsTcpRelayLimits::new(Duration::from_secs(60)).unwrap();
        let plan = WindowsStrictTcpSessionPlan::new_for_test(
            3,
            7,
            &"ab".repeat(32),
            [0x11; 16],
            vec![ingress(41001, '1'), ingress(41002, '2')],
            Duration::from_secs(2),
            Duration::from_secs(2),
            limits,
        )
        .unwrap();
        assert_eq!(plan.target_group_count(), 2);
        assert_eq!(
            plan.core_endpoints(),
            vec![
                SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41001),
                SocketAddrV4::new(Ipv4Addr::LOCALHOST, 41002),
            ]
        );

        assert!(WindowsStrictTcpSessionPlan::new_for_test(
            3,
            7,
            &"ab".repeat(32),
            [0x11; 16],
            vec![ingress(41001, '3'), ingress(41001, '4')],
            Duration::from_secs(2),
            Duration::from_secs(2),
            limits,
        )
        .is_err());
        assert!(WindowsStrictTcpSessionPlan::new_for_test(
            3,
            7,
            &"ab".repeat(32),
            [0x11; 16],
            Vec::new(),
            Duration::from_secs(2),
            Duration::from_secs(2),
            limits,
        )
        .is_err());
    }

    #[test]
    fn selected_group_connects_authenticated_core_and_relays_without_fallback() {
        let unused = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let core = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let core_endpoint = match core.local_addr().unwrap() {
            SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };
        let unused_endpoint = match unused.local_addr().unwrap() {
            SocketAddr::V4(endpoint) => endpoint,
            _ => unreachable!(),
        };
        let username = credential('2');
        let password = credential('3');
        let server_username = username.clone();
        let server_password = password.clone();
        let core_worker = thread::spawn(move || {
            let (mut stream, _) = core.accept().unwrap();
            let mut greeting = [0_u8; 3];
            stream.read_exact(&mut greeting).unwrap();
            assert_eq!(greeting, [0x05, 0x01, 0x02]);
            stream.write_all(&[0x05, 0x02]).unwrap();

            let mut auth_header = [0_u8; 2];
            stream.read_exact(&mut auth_header).unwrap();
            let mut received_username = vec![0_u8; usize::from(auth_header[1])];
            stream.read_exact(&mut received_username).unwrap();
            let mut password_length = [0_u8; 1];
            stream.read_exact(&mut password_length).unwrap();
            let mut received_password = vec![0_u8; usize::from(password_length[0])];
            stream.read_exact(&mut received_password).unwrap();
            assert_eq!(received_username, server_username.as_bytes());
            assert_eq!(received_password, server_password.as_bytes());
            stream.write_all(&[0x01, 0x00]).unwrap();

            let mut connect = [0_u8; 10];
            stream.read_exact(&mut connect).unwrap();
            assert_eq!(connect, [0x05, 0x01, 0x00, 0x01, 203, 0, 113, 10, 1, 187]);
            stream
                .write_all(&[0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 1])
                .unwrap();

            let mut request = Vec::new();
            stream.read_to_end(&mut request).unwrap();
            assert_eq!(request, b"strict-request");
            stream.write_all(b"strict-response").unwrap();
            stream.shutdown(Shutdown::Write).unwrap();
        });
        let plan = WindowsStrictTcpSessionPlan::new_for_test(
            3,
            7,
            &"ab".repeat(32),
            [0x11; 16],
            vec![
                Socks5ProxyIngress::new(unused_endpoint, credential('0'), credential('1')).unwrap(),
                Socks5ProxyIngress::new(core_endpoint, username, password).unwrap(),
            ],
            Duration::from_secs(1),
            Duration::from_secs(1),
            WindowsTcpRelayLimits::new(Duration::from_secs(2)).unwrap(),
        )
        .unwrap();
        let context = context(&plan);
        let records = [0x55; 32];
        let shutdown = WindowsPipeShutdown::new();
        let (mut application, broker_client) = connected_pair();
        let handler_shutdown = shutdown.clone();
        let handler = thread::spawn(move || {
            connect_and_relay_with(
                broker_client,
                &plan,
                context,
                &records,
                &handler_shutdown,
                |endpoint, actual_records, timeout| {
                    assert_eq!(endpoint, core_endpoint);
                    assert_eq!(actual_records, records);
                    Ok(TcpStream::connect_timeout(
                        &SocketAddr::V4(endpoint),
                        timeout,
                    )?)
                },
            )
            .unwrap()
        });

        application.write_all(b"strict-request").unwrap();
        application.shutdown(Shutdown::Write).unwrap();
        let mut response = Vec::new();
        application.read_to_end(&mut response).unwrap();
        assert_eq!(response, b"strict-response");
        let report = handler.join().unwrap();
        assert_eq!(report.client_to_upstream_bytes, 14);
        assert_eq!(report.upstream_to_client_bytes, 15);
        core_worker.join().unwrap();
    }
}
