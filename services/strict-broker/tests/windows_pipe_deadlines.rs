#![cfg(windows)]

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{FromRawHandle, OwnedHandle};
use std::ptr::{null, null_mut};
use std::sync::mpsc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use flclash_strict_broker::{
    current_process_user_sid, BrokerAuthenticator, WindowsNamedPipeInstance, WindowsPipeDeadlines,
};
use windows_sys::Win32::Foundation::{GENERIC_READ, GENERIC_WRITE, INVALID_HANDLE_VALUE};
use windows_sys::Win32::Storage::FileSystem::{
    CreateFileW, OPEN_EXISTING, SECURITY_IDENTIFICATION, SECURITY_SQOS_PRESENT,
};

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

fn open_silent_client(pipe_name: &str) -> OwnedHandle {
    let pipe_name: Vec<u16> = OsStr::new(pipe_name).encode_wide().chain(Some(0)).collect();
    // SAFETY: the path is NUL-terminated and the optional pointers are null.
    let handle = unsafe {
        CreateFileW(
            pipe_name.as_ptr(),
            GENERIC_READ | GENERIC_WRITE,
            0,
            null(),
            OPEN_EXISTING,
            SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
            null_mut(),
        )
    };
    assert_ne!(handle, INVALID_HANDLE_VALUE);
    // SAFETY: CreateFileW returned a unique owned handle.
    unsafe { OwnedHandle::from_raw_handle(handle) }
}

#[test]
fn connect_without_a_client_is_cancelled_at_the_total_deadline() {
    let deadlines = WindowsPipeDeadlines::new(
        Duration::from_millis(60),
        Duration::from_secs(1),
        Duration::from_secs(1),
    )
    .unwrap();
    let instance = WindowsNamedPipeInstance::create_with_deadlines(
        &pipe_name("ConnectDeadline"),
        &current_process_user_sid().unwrap(),
        deadlines,
    )
    .unwrap();

    let started = Instant::now();
    let error = match instance.connect_and_authenticate(&BrokerAuthenticator::new([0x11; 32])) {
        Ok(_) => panic!("connection unexpectedly succeeded"),
        Err(error) => error,
    };

    assert!(error.to_string().contains("deadline"));
    assert!(started.elapsed() < Duration::from_secs(2));
}

#[test]
fn a_silent_connected_client_cannot_hold_the_request_reader() {
    let name = pipe_name("ReadDeadline");
    let deadlines = WindowsPipeDeadlines::new(
        Duration::from_secs(1),
        Duration::from_millis(60),
        Duration::from_secs(1),
    )
    .unwrap();
    let instance = WindowsNamedPipeInstance::create_with_deadlines(
        &name,
        &current_process_user_sid().unwrap(),
        deadlines,
    )
    .unwrap();
    let (connected_tx, connected_rx) = mpsc::channel();
    let client = std::thread::spawn(move || {
        let handle = open_silent_client(&name);
        connected_tx.send(()).unwrap();
        std::thread::sleep(Duration::from_millis(300));
        drop(handle);
    });
    connected_rx.recv_timeout(Duration::from_secs(1)).unwrap();

    let started = Instant::now();
    let error = match instance.connect_and_authenticate(&BrokerAuthenticator::new([0x11; 32])) {
        Ok(_) => panic!("silent client unexpectedly produced a request"),
        Err(error) => error,
    };

    assert!(error.to_string().contains("deadline"));
    assert!(started.elapsed() < Duration::from_secs(2));
    client.join().unwrap();
}

#[test]
fn zero_or_unreasonably_large_deadlines_are_rejected() {
    assert!(WindowsPipeDeadlines::new(
        Duration::ZERO,
        Duration::from_secs(1),
        Duration::from_secs(1)
    )
    .is_err());
    assert!(WindowsPipeDeadlines::new(
        Duration::from_secs(1),
        Duration::from_secs(301),
        Duration::from_secs(1)
    )
    .is_err());
}
