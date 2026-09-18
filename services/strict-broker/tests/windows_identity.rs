#![cfg(windows)]

use std::fs;
use std::net::{Ipv4Addr, TcpListener};
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command};

use flclash_strict_broker::{
    inspect_windows_driver, inspect_windows_executable, verify_windows_driver,
    verify_windows_packaged_agent_image, verify_windows_packaged_agent_process,
    verify_windows_packaged_agent_process_with_image, verify_windows_packaged_core_image,
    verify_windows_packaged_core_listener_owner_with_image,
    verify_windows_packaged_core_process_with_image, verify_windows_packaged_driver,
    IdentityVerifier, StrictPackageManifest, WindowsIdentityVerifier,
};
use flclash_strict_contract::{StrictIdentity, StrictPolicyBundle, StrictPolicyEntry};
use sha2::{Digest, Sha256};
use windows_sys::Win32::System::Threading::CREATE_NO_WINDOW;

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn packaged_core_process_is_bound_to_pid_path_file_and_publisher() {
    let system_binary = PathBuf::from(std::env::var_os("WINDIR").unwrap())
        .join("System32")
        .join("cmd.exe");
    let inspected = inspect_windows_executable(&system_binary).unwrap();
    let file_sha256 = format!("{:x}", Sha256::digest(fs::read(&system_binary).unwrap()));
    let manifest = StrictPackageManifest::parse(
        format!(
            r#"{{"protocol":2,"packageVersion":"core-process-test","driverBuildId":"{}","driverFileSha256":"{}","driverPublisherCertificateSha256":"{}","brokerFileSha256":"{}","brokerPublisherCertificateSha256":"{}","agentFileSha256":"{}","agentPublisherCertificateSha256":"{}","coreFileSha256":"{file_sha256}","corePublisherCertificateSha256":"{}"}}"#,
            "12".repeat(16),
            "23".repeat(32),
            "34".repeat(32),
            "45".repeat(32),
            "56".repeat(32),
            "67".repeat(32),
            "78".repeat(32),
            inspected.publisher_certificate_sha256,
        )
        .as_bytes(),
    )
    .unwrap();
    let child = Command::new(&system_binary)
        .args(["/d", "/c", "ping -n 10 127.0.0.1 >nul"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .unwrap();
    let mut child = ChildGuard(child);

    let image = verify_windows_packaged_core_image(&inspected.canonical_path, &manifest).unwrap();
    assert_eq!(image.canonical_path(), inspected.canonical_path);
    assert_eq!(image.file_sha256(), file_sha256);
    let lease = verify_windows_packaged_core_process_with_image(child.0.id(), &image).unwrap();
    assert_eq!(lease.process_id(), child.0.id());
    assert_eq!(lease.canonical_path(), inspected.canonical_path);
    assert!(lease.is_running().unwrap());

    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
    let endpoint = match listener.local_addr().unwrap() {
        std::net::SocketAddr::V4(endpoint) => endpoint,
        _ => unreachable!(),
    };
    assert!(verify_windows_packaged_core_listener_owner_with_image(&[endpoint], &image).is_err());

    child.0.kill().unwrap();
    child.0.wait().unwrap();
    assert!(!lease.is_running().unwrap());
}

#[test]
fn signed_windows_executable_is_reopened_and_matches_pinned_identity() {
    let system_binary = PathBuf::from(std::env::var_os("WINDIR").unwrap())
        .join("System32")
        .join("notepad.exe");
    let inspected = inspect_windows_executable(&system_binary).unwrap();
    let identity = StrictIdentity {
        identity_id: "10000000-0000-4000-8000-000000000001".into(),
        canonical_path: inspected.canonical_path.clone(),
        wfp_app_id_sha256: inspected.wfp_app_id_sha256.clone(),
        publisher_certificate_sha256: inspected.publisher_certificate_sha256.clone(),
        verified_children: Vec::new(),
    };
    let policy =
        StrictPolicyBundle::new(1, vec![StrictPolicyEntry::block(identity.clone())]).unwrap();
    let mut verifier = WindowsIdentityVerifier;

    let verification = verifier.verify(&policy).unwrap();
    assert_eq!(verification.lease().executable_count(), 1);
    assert_eq!(verification.app_ids().app_id_count(), 1);

    let mut mismatched = identity;
    mismatched.wfp_app_id_sha256 = "00".repeat(32);
    let mismatched =
        StrictPolicyBundle::new(2, vec![StrictPolicyEntry::block(mismatched)]).unwrap();
    assert!(verifier.verify(&mismatched).is_err());
}

#[test]
fn unsigned_test_binary_is_not_accepted_as_a_strict_identity() {
    assert!(inspect_windows_executable(std::env::current_exe().unwrap()).is_err());
}

#[test]
fn signed_windows_driver_is_locked_and_publisher_pinned() {
    let system_driver = PathBuf::from(std::env::var_os("WINDIR").unwrap())
        .join("System32")
        .join("drivers")
        .join("null.sys");
    let inspected = inspect_windows_driver(&system_driver).unwrap();
    assert!(inspected
        .canonical_path()
        .to_ascii_lowercase()
        .ends_with(r"\system32\drivers\null.sys"));
    assert_eq!(inspected.publisher_certificate_sha256().len(), 64);
    assert_eq!(inspected.file_sha256().len(), 64);

    verify_windows_driver(&system_driver, inspected.publisher_certificate_sha256()).unwrap();
    verify_windows_packaged_driver(
        &system_driver,
        inspected.file_sha256(),
        inspected.publisher_certificate_sha256(),
    )
    .unwrap();
    assert!(verify_windows_driver(&system_driver, &"00".repeat(32)).is_err());
    assert!(verify_windows_packaged_driver(
        &system_driver,
        &"00".repeat(32),
        inspected.publisher_certificate_sha256(),
    )
    .is_err());
}

#[test]
fn packaged_agent_process_is_bound_to_pid_path_file_and_publisher() {
    let system_binary = PathBuf::from(std::env::var_os("WINDIR").unwrap())
        .join("System32")
        .join("cmd.exe");
    let inspected = inspect_windows_executable(&system_binary).unwrap();
    let file_sha256 = format!("{:x}", Sha256::digest(fs::read(&system_binary).unwrap()));
    let manifest = StrictPackageManifest::parse(
        format!(
            r#"{{"protocol":2,"packageVersion":"agent-process-test","driverBuildId":"{}","driverFileSha256":"{}","driverPublisherCertificateSha256":"{}","brokerFileSha256":"{}","brokerPublisherCertificateSha256":"{}","agentFileSha256":"{file_sha256}","agentPublisherCertificateSha256":"{}","coreFileSha256":"{file_sha256}","corePublisherCertificateSha256":"{}"}}"#,
            "12".repeat(16),
            "23".repeat(32),
            "34".repeat(32),
            "45".repeat(32),
            "56".repeat(32),
            inspected.publisher_certificate_sha256,
            inspected.publisher_certificate_sha256,
        )
        .as_bytes(),
    )
    .unwrap();
    assert!(verify_windows_packaged_agent_process(
        std::process::id(),
        &inspected.canonical_path,
        &manifest,
    )
    .is_err());
    let child = Command::new(&system_binary)
        .args(["/d", "/c", "ping -n 10 127.0.0.1 >nul"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .unwrap();
    let mut child = ChildGuard(child);

    let image = verify_windows_packaged_agent_image(&inspected.canonical_path, &manifest).unwrap();
    assert_eq!(image.canonical_path(), inspected.canonical_path);
    assert_eq!(image.file_sha256(), file_sha256);
    assert_eq!(
        image.publisher_certificate_sha256(),
        inspected.publisher_certificate_sha256
    );
    let lease = verify_windows_packaged_agent_process_with_image(child.0.id(), &image).unwrap();
    assert_eq!(lease.process_id(), child.0.id());
    assert_eq!(lease.canonical_path(), inspected.canonical_path);
    assert!(lease.is_running().unwrap());

    child.0.kill().unwrap();
    child.0.wait().unwrap();
    assert!(!lease.is_running().unwrap());
}
