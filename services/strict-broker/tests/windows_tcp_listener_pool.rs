#![cfg(windows)]

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use flclash_strict_broker::{WindowsPipeShutdown, WindowsTcpListenerPool};

#[test]
fn dual_stack_loopback_listeners_dispatch_to_a_fixed_worker_pool() {
    let (handled_tx, handled_rx) = mpsc::sync_channel(2);
    let pool = WindowsTcpListenerPool::bind(2, move |mut stream, _shutdown| {
        stream.write_all(b"x")?;
        handled_tx.send(()).unwrap();
        Ok(())
    })
    .unwrap();
    let endpoints = pool.endpoints();
    let shutdown = WindowsPipeShutdown::new();
    let worker_shutdown = shutdown.clone();
    let worker = thread::spawn(move || pool.run(worker_shutdown).unwrap());

    for endpoint in [
        SocketAddr::V4(endpoints.v4()),
        SocketAddr::V6(endpoints.v6()),
    ] {
        let mut client = TcpStream::connect_timeout(&endpoint, Duration::from_secs(1)).unwrap();
        let mut response = [0_u8; 1];
        client.read_exact(&mut response).unwrap();
        assert_eq!(response, [b'x']);
    }
    handled_rx.recv_timeout(Duration::from_secs(1)).unwrap();
    handled_rx.recv_timeout(Duration::from_secs(1)).unwrap();

    let started = Instant::now();
    shutdown.request();
    let report = worker.join().unwrap();
    assert!(started.elapsed() < Duration::from_secs(1));
    assert_eq!(report.listener_count, 2);
    assert_eq!(report.worker_count, 2);
    assert_eq!(report.accepted_connections, 2);
    assert_eq!(report.completed_connections, 2);
    assert_eq!(report.rejected_connections, 0);
    assert_eq!(report.handler_failures, 0);
    assert_eq!(report.handler_panics, 0);
}

#[test]
fn invalid_worker_counts_are_rejected_before_binding() {
    assert!(WindowsTcpListenerPool::bind(0, |_stream, _shutdown| Ok(())).is_err());
    assert!(WindowsTcpListenerPool::bind(65, |_stream, _shutdown| Ok(())).is_err());
}

#[test]
fn a_panicking_handler_is_isolated_and_the_worker_lane_survives() {
    let (attempt_tx, attempt_rx) = mpsc::sync_channel(2);
    let pool = WindowsTcpListenerPool::bind(1, move |mut stream, _shutdown| {
        let attempt = attempt_tx.send(());
        if attempt.is_err() {
            return Ok(());
        }
        stream.write_all(b"p")?;
        panic!("injected relay handler panic");
    })
    .unwrap();
    let endpoint = SocketAddr::V4(pool.endpoints().v4());
    let shutdown = WindowsPipeShutdown::new();
    let worker_shutdown = shutdown.clone();
    let worker = thread::spawn(move || pool.run(worker_shutdown).unwrap());

    for _ in 0..2 {
        let mut client = TcpStream::connect_timeout(&endpoint, Duration::from_secs(1)).unwrap();
        let mut response = [0_u8; 1];
        client.read_exact(&mut response).unwrap();
        assert_eq!(response, [b'p']);
        attempt_rx.recv_timeout(Duration::from_secs(1)).unwrap();
    }
    shutdown.request();
    let report = worker.join().unwrap();
    assert_eq!(report.handler_panics, 2);
    assert_eq!(report.completed_connections, 0);
}
