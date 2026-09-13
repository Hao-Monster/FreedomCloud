#![cfg(windows)]

use std::io::{Read, Write};
use std::net::{Ipv4Addr, Shutdown, TcpListener, TcpStream};
use std::thread;
use std::time::{Duration, Instant};

use flclash_strict_broker::{
    relay_windows_tcp_bidirectional, WindowsPipeShutdown, WindowsTcpRelayLimits,
};

fn connected_pair() -> (TcpStream, TcpStream) {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
    let (server, _) = listener.accept().unwrap();
    (client, server)
}

#[test]
fn relay_preserves_payload_and_bidirectional_half_close() {
    let (mut client, relay_client) = connected_pair();
    let (relay_upstream, mut server) = connected_pair();
    let request = (0..128 * 1024)
        .map(|index| (index % 251) as u8)
        .collect::<Vec<_>>();
    let response = (0..96 * 1024)
        .map(|index| (index % 239) as u8)
        .collect::<Vec<_>>();
    let expected_request = request.clone();
    let expected_response = response.clone();
    let server_worker = thread::spawn(move || {
        let mut received = Vec::new();
        server.read_to_end(&mut received).unwrap();
        assert_eq!(received, expected_request);
        server.write_all(&response).unwrap();
        server.shutdown(Shutdown::Write).unwrap();
    });
    let shutdown = WindowsPipeShutdown::new();
    let worker = thread::spawn(move || {
        relay_windows_tcp_bidirectional(
            relay_client,
            relay_upstream,
            &shutdown,
            WindowsTcpRelayLimits::new(Duration::from_secs(2)).unwrap(),
        )
        .unwrap()
    });

    client.write_all(&request).unwrap();
    client.shutdown(Shutdown::Write).unwrap();
    let mut received_response = Vec::new();
    client.read_to_end(&mut received_response).unwrap();
    assert_eq!(received_response, expected_response);

    server_worker.join().unwrap();
    let report = worker.join().unwrap();
    assert_eq!(report.client_to_upstream_bytes, request.len() as u64);
    assert_eq!(
        report.upstream_to_client_bytes,
        received_response.len() as u64
    );
}

#[test]
fn idle_relay_exits_within_its_bounded_deadline() {
    let (_client, relay_client) = connected_pair();
    let (relay_upstream, _server) = connected_pair();
    let started = Instant::now();

    assert!(relay_windows_tcp_bidirectional(
        relay_client,
        relay_upstream,
        &WindowsPipeShutdown::new(),
        WindowsTcpRelayLimits::new(Duration::from_millis(25)).unwrap(),
    )
    .is_err());
    assert!(started.elapsed() < Duration::from_secs(1));
}

#[test]
fn relay_limits_reject_zero_and_unbounded_idle_time() {
    assert!(WindowsTcpRelayLimits::new(Duration::ZERO).is_err());
    assert!(WindowsTcpRelayLimits::new(Duration::from_secs(30 * 60 + 1)).is_err());
}

#[test]
fn requested_shutdown_cancels_an_idle_relay_without_waiting_for_idle_timeout() {
    let (_client, relay_client) = connected_pair();
    let (relay_upstream, _server) = connected_pair();
    let shutdown = WindowsPipeShutdown::new();
    shutdown.request();
    let started = Instant::now();

    let report = relay_windows_tcp_bidirectional(
        relay_client,
        relay_upstream,
        &shutdown,
        WindowsTcpRelayLimits::new(Duration::from_secs(30)).unwrap(),
    )
    .unwrap();
    assert_eq!(report.client_to_upstream_bytes, 0);
    assert_eq!(report.upstream_to_client_bytes, 0);
    assert!(started.elapsed() < Duration::from_secs(1));
}
