#![cfg(windows)]

use std::path::PathBuf;

use flclash_strict_broker::{
    inspect_windows_executable, IdentityVerifier, WindowsIdentityVerifier,
};
use flclash_strict_contract::{StrictIdentity, StrictPolicyBundle, StrictPolicyEntry};

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
