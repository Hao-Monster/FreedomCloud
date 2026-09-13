#![cfg(windows)]

use std::net::{Ipv4Addr, SocketAddrV4, TcpListener, TcpStream};
use std::time::Duration;

use flclash_strict_broker::{
    connect_windows_redirected_outbound, query_windows_redirect_socket, StrictRedirectLeaseBinding,
    StrictRedirectTransport,
};

#[test]
fn ordinary_loopback_socket_cannot_forge_kernel_redirect_metadata() {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
    let (accepted, _) = listener.accept().unwrap();
    let binding = StrictRedirectLeaseBinding::new(1, 1, &"ab".repeat(32), [0x11; 16], 1).unwrap();

    assert!(
        query_windows_redirect_socket(&accepted, &binding, StrictRedirectTransport::Tcp).is_err()
    );
    drop(client);
}

#[test]
fn outbound_socket_rejects_untrusted_or_oversized_redirect_records_before_connect() {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let endpoint = match listener.local_addr().unwrap() {
        std::net::SocketAddr::V4(endpoint) => endpoint,
        _ => unreachable!(),
    };

    assert!(
        connect_windows_redirected_outbound(endpoint, &[0x11; 32], Duration::from_secs(1)).is_err()
    );
    assert!(connect_windows_redirected_outbound(
        SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, endpoint.port()),
        &[0x11; 32],
        Duration::from_secs(1),
    )
    .is_err());
    assert!(connect_windows_redirected_outbound(
        endpoint,
        &vec![0x11; 64 * 1024 + 1],
        Duration::from_secs(1),
    )
    .is_err());
}
