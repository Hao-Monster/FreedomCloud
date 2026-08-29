#![cfg(windows)]

use std::cell::Cell;
use std::fs;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command};
use std::time::Duration;

use flclash_strict_broker::{
    current_process_user_sid, exchange_windows_pipe_for_agent, inspect_windows_executable,
    verify_windows_packaged_agent_process, BrokerSessionRegistry, BrokerSessionResource,
    StrictPackageManifest, WindowsBrokerPipeSession, WindowsPipeDeadlines,
    WindowsVerifiedActivationRequest,
};
use flclash_strict_contract::{
    BrokerActivationRequest, BrokerErrorCode, BrokerResponse, BrokerResponseBody,
    STRICT_PROTOCOL_VERSION,
};
use sha2::{Digest, Sha256};
use windows_sys::Win32::System::Threading::CREATE_NO_WINDOW;

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn packaged_command_process() -> (
    ChildGuard,
    flclash_strict_broker::WindowsAgentProcessTrustLease,
) {
    let binary = PathBuf::from(std::env::var_os("WINDIR").unwrap())
        .join("System32")
        .join("cmd.exe");
    let inspected = inspect_windows_executable(&binary).unwrap();
    let file_sha256 = format!("{:x}", Sha256::digest(fs::read(&binary).unwrap()));
    let package = StrictPackageManifest::parse(
        format!(
            r#"{{"protocol":2,"packageVersion":"session-test","driverBuildId":"{}","driverFileSha256":"{}","driverPublisherCertificateSha256":"{}","agentFileSha256":"{file_sha256}","agentPublisherCertificateSha256":"{}","coreFileSha256":"{file_sha256}","corePublisherCertificateSha256":"{}"}}"#,
            "12".repeat(16),
            "23".repeat(32),
            "34".repeat(32),
            inspected.publisher_certificate_sha256,
            inspected.publisher_certificate_sha256,
        )
        .as_bytes(),
    )
    .unwrap();
    let child = Command::new(&binary)
        .args(["/d", "/c", "ping -n 10 127.0.0.1 >nul"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .unwrap();
    let child = ChildGuard(child);
    let lease =
        verify_windows_packaged_agent_process(child.0.id(), &inspected.canonical_path, &package)
            .unwrap();
    (child, lease)
}

#[test]
fn agent_exit_forces_cleanup_before_bounded_pipe_session_shutdown() {
    let (mut child, agent) = packaged_command_process();
    let capability = "11".repeat(32);
    let activation = WindowsVerifiedActivationRequest {
        request: BrokerActivationRequest {
            protocol: STRICT_PROTOCOL_VERSION,
            request_id: "session-activation".into(),
            session_capability: capability.clone(),
        },
        client_sid: current_process_user_sid().unwrap(),
        client_session_id: 1,
        agent,
    };
    let deadlines = WindowsPipeDeadlines::new(
        Duration::from_millis(50),
        Duration::from_secs(1),
        Duration::from_secs(1),
    )
    .unwrap();
    // A non-SYSTEM local test process deliberately lacks FILE_CREATE_PIPE_INSTANCE
    // on the owner data pipe; LocalSystem multi-instance remains a VM gate.
    let session = WindowsBrokerPipeSession::start(activation, deadlines, 1, |authorized| {
        BrokerResponse::error(&authorized.request().request_id, BrokerErrorCode::Internal).unwrap()
    })
    .unwrap();
    let pipe_name = session.pipe_name().to_owned();
    assert_eq!(
        session.activation_response().unwrap().request_id,
        "session-activation"
    );
    let mut registry = BrokerSessionRegistry::default();
    assert_eq!(registry.activate(session, || Ok(())).unwrap(), 1);
    assert!(registry.active().unwrap().is_alive().unwrap());

    let frame = format!(
        r#"{{"protocol":{STRICT_PROTOCOL_VERSION},"requestId":"session-status","sessionCapability":"{capability}","command":{{"type":"status"}}}}"#
    );
    let response = exchange_windows_pipe_for_agent(&pipe_name, frame.as_bytes()).unwrap();
    assert!(matches!(
        response.body,
        BrokerResponseBody::Error {
            code: BrokerErrorCode::Internal
        }
    ));

    child.0.kill().unwrap();
    child.0.wait().unwrap();
    let cleanups = Cell::new(0);
    assert!(registry
        .reap_exited(|| {
            cleanups.set(cleanups.get() + 1);
            Ok(())
        })
        .unwrap());
    assert_eq!(cleanups.get(), 1);
    assert!(registry.active().is_none());
}
