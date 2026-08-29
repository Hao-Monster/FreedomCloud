use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use flclash_strict_broker::{FileRecoveryStore, RecoveryMarker, RecoveryStore};
use flclash_strict_contract::{StrictIdentity, StrictPolicyBundle, StrictPolicyEntry};

struct TestDirectory(PathBuf);

impl TestDirectory {
    fn new(label: &str) -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "flclash-strict-broker-{label}-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn hex(character: char) -> String {
    std::iter::repeat_n(character, 64).collect()
}

fn policy(revision: u64) -> StrictPolicyBundle {
    StrictPolicyBundle::new(
        revision,
        vec![StrictPolicyEntry::block(StrictIdentity {
            identity_id: "10000000-0000-4000-8000-000000000001".into(),
            canonical_path: r"C:\Apps\Recovery\app.exe".into(),
            wfp_app_id_sha256: hex('a'),
            publisher_certificate_sha256: hex('b'),
            verified_children: Vec::new(),
        })],
    )
    .unwrap()
}

#[test]
fn marker_round_trip_and_clear_preserve_revision_high_watermark() {
    let directory = TestDirectory::new("roundtrip");
    let mut store = FileRecoveryStore::from_presecured_directory(directory.path()).unwrap();
    let desired = policy(41);
    let marker = RecoveryMarker::blocking(desired.clone(), desired.canonical_digest().unwrap(), 3);

    store.persist(&marker).unwrap();
    let loaded = store.load().unwrap();
    assert_eq!(loaded.high_watermark, 41);
    assert_eq!(loaded.marker, Some(marker));

    store.clear_marker().unwrap();
    let cleared = store.load().unwrap();
    assert_eq!(cleared.high_watermark, 41);
    assert!(cleared.marker.is_none());

    let stale = policy(40);
    let stale_marker =
        RecoveryMarker::blocking(stale.clone(), stale.canonical_digest().unwrap(), 4);
    assert!(store.persist(&stale_marker).is_err());
}

#[test]
fn tampered_marker_is_rejected_without_replacing_valid_state() {
    let directory = TestDirectory::new("tamper");
    let mut store = FileRecoveryStore::from_presecured_directory(directory.path()).unwrap();
    let desired = policy(42);
    let valid = RecoveryMarker::blocking(desired.clone(), desired.canonical_digest().unwrap(), 5);
    store.persist(&valid).unwrap();

    let tampered = RecoveryMarker::blocking(desired, hex('0'), 6);
    assert!(store.persist(&tampered).is_err());

    assert_eq!(store.load().unwrap().marker, Some(valid));
}

#[test]
fn relative_directory_and_oversized_state_are_rejected() {
    assert!(FileRecoveryStore::from_presecured_directory("relative-state").is_err());

    let directory = TestDirectory::new("oversized");
    let state_path = directory.path().join("strict-recovery-v1.json");
    fs::write(&state_path, vec![b'x'; 2 * 1024 * 1024 + 1]).unwrap();
    let mut store = FileRecoveryStore::from_presecured_directory(directory.path()).unwrap();

    assert!(store.load().is_err());
}
