#![cfg(windows)]

use std::io;
use std::sync::{mpsc, Arc, Condvar, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use flclash_strict_broker::{
    current_process_user_sid, exchange_windows_pipe_for_agent, BrokerAuthenticator,
    WindowsNamedPipeWorkerPool, WindowsPipeDeadlines, WindowsPipeShutdown,
};
use flclash_strict_contract::{BrokerErrorCode, BrokerResponse, STRICT_PROTOCOL_VERSION};
use windows_sys::Win32::Foundation::ERROR_PIPE_BUSY;

fn pipe_name(label: &str) -> String {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!(
        r"\\.\pipe\FlClashX.StrictBroker.{label}.{}.{}",
        std::process::id(),
        nonce
    )
}

fn status_frame(request_id: &str) -> Vec<u8> {
    format!(
        r#"{{"protocol":{},"requestId":"{request_id}","sessionCapability":"{}","command":{{"type":"status"}}}}"#,
        STRICT_PROTOCOL_VERSION,
        "11".repeat(32)
    )
    .into_bytes()
}

#[test]
fn worker_count_is_a_hard_concurrency_bound_and_shutdown_is_bounded() {
    let name = pipe_name("PoolBound");
    let deadlines = WindowsPipeDeadlines::new(
        Duration::from_millis(60),
        Duration::from_secs(1),
        Duration::from_secs(1),
    )
    .unwrap();
    let gate = Arc::new((Mutex::new(false), Condvar::new()));
    let worker_gate = Arc::clone(&gate);
    let (entered_tx, entered_rx) = mpsc::channel();
    let pool = WindowsNamedPipeWorkerPool::create(
        &name,
        &current_process_user_sid().unwrap(),
        BrokerAuthenticator::new([0x11; 32]),
        deadlines,
        1,
        move |authorized| {
            entered_tx.send(()).unwrap();
            let (lock, condition) = &*worker_gate;
            let mut released = lock.lock().unwrap();
            while !*released {
                released = condition.wait(released).unwrap();
            }
            BrokerResponse::error(
                &authorized.request().request_id,
                BrokerErrorCode::BackendUnavailable,
            )
            .unwrap()
        },
    )
    .unwrap();
    let shutdown = WindowsPipeShutdown::new();
    let service_shutdown = shutdown.clone();
    let service = std::thread::spawn(move || pool.run(service_shutdown).unwrap());

    let client_name = name.clone();
    let client = std::thread::spawn(move || {
        exchange_windows_pipe_for_agent(&client_name, &status_frame("pool-1")).unwrap()
    });
    entered_rx.recv_timeout(Duration::from_secs(2)).unwrap();

    let overload = exchange_windows_pipe_for_agent(&name, &status_frame("pool-overload"))
        .expect_err("a second concurrent client must be rejected");
    assert!(overload.chain().any(|cause| {
        cause
            .downcast_ref::<io::Error>()
            .is_some_and(|error| error.raw_os_error() == Some(ERROR_PIPE_BUSY as i32))
    }));

    let (lock, condition) = &*gate;
    *lock.lock().unwrap() = true;
    condition.notify_all();
    client.join().unwrap();

    let shutdown_started = Instant::now();
    shutdown.request();
    let report = service.join().unwrap();
    assert!(shutdown_started.elapsed() < Duration::from_secs(2));
    assert_eq!(report.worker_count, 1);
    assert_eq!(report.completed_requests, 1);
}

#[test]
fn invalid_worker_counts_are_rejected_before_pipe_creation() {
    let deadlines = WindowsPipeDeadlines::default();
    for worker_count in [0, 65] {
        let result = WindowsNamedPipeWorkerPool::create(
            &pipe_name("InvalidPool"),
            &current_process_user_sid().unwrap(),
            BrokerAuthenticator::new([0x11; 32]),
            deadlines,
            worker_count,
            |authorized| {
                BrokerResponse::error(&authorized.request().request_id, BrokerErrorCode::Internal)
                    .unwrap()
            },
        );
        assert!(result.is_err());
    }
}

#[test]
fn a_stuck_handler_loses_its_fixed_worker_without_blocking_service_exit() {
    let name = pipe_name("HandlerDeadline");
    let deadlines = WindowsPipeDeadlines::new(
        Duration::from_millis(60),
        Duration::from_secs(1),
        Duration::from_secs(1),
    )
    .unwrap();
    let pool = WindowsNamedPipeWorkerPool::create_with_handler_deadline(
        &name,
        &current_process_user_sid().unwrap(),
        BrokerAuthenticator::new([0x11; 32]),
        deadlines,
        1,
        Duration::from_millis(50),
        |authorized| {
            std::thread::sleep(Duration::from_millis(300));
            BrokerResponse::error(&authorized.request().request_id, BrokerErrorCode::Internal)
                .unwrap()
        },
    )
    .unwrap();
    let service = std::thread::spawn(move || pool.run(WindowsPipeShutdown::new()).unwrap());

    let started = Instant::now();
    let response =
        exchange_windows_pipe_for_agent(&name, &status_frame("handler-timeout")).unwrap();
    let report = service.join().unwrap();

    assert!(started.elapsed() < Duration::from_secs(2));
    assert!(matches!(
        response.body,
        flclash_strict_contract::BrokerResponseBody::Error {
            code: BrokerErrorCode::BackendUnavailable
        }
    ));
    assert_eq!(report.handler_timeouts, 1);
    assert_eq!(report.completed_requests, 1);
}
