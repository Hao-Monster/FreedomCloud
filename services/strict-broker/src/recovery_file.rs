use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::{RecoveryMarker, RecoveryRecord, RecoveryStore};

const STATE_FILE_NAME: &str = "strict-recovery-v1.json";
const MAX_STATE_BYTES: u64 = 2 * 1024 * 1024;
const RECOVERY_FILE_PROTOCOL: u32 = 1;
static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StoredRecoveryRecord {
    protocol: u32,
    high_watermark: u64,
    marker: Option<RecoveryMarker>,
}

impl StoredRecoveryRecord {
    fn validate(self) -> Result<RecoveryRecord> {
        if self.protocol != RECOVERY_FILE_PROTOCOL {
            bail!("unsupported strict recovery file protocol");
        }
        if let Some(marker) = &self.marker {
            marker.validate()?;
            if self.high_watermark < marker.revision {
                bail!("strict recovery high watermark is below the active revision");
            }
        }
        Ok(RecoveryRecord {
            high_watermark: self.high_watermark,
            marker: self.marker,
        })
    }
}

/// File-backed state for a single Broker instance.
///
/// The directory must be provisioned before construction with a protected ACL
/// limited to LocalSystem and Administrators. On Windows the public constructor
/// verifies that exact ACL and rejects reparse points; it intentionally never
/// creates or relaxes directory permissions.
pub struct FileRecoveryStore {
    root: PathBuf,
    state_path: PathBuf,
    #[cfg(windows)]
    verify_file_acl: bool,
}

impl FileRecoveryStore {
    pub fn from_presecured_directory(path: impl AsRef<Path>) -> Result<Self> {
        #[cfg(windows)]
        crate::WindowsRecoveryAclVerifier::verify_directory(path.as_ref())?;
        Self::from_verified_topology(path, cfg!(windows))
    }

    fn from_verified_topology(path: impl AsRef<Path>, verify_file_acl: bool) -> Result<Self> {
        let root = path.as_ref();
        if !root.is_absolute() {
            bail!("strict recovery directory must be absolute");
        }
        validate_directory(root)?;
        #[cfg(not(windows))]
        let _ = verify_file_acl;
        Ok(Self {
            root: root.to_path_buf(),
            state_path: root.join(STATE_FILE_NAME),
            #[cfg(windows)]
            verify_file_acl,
        })
    }

    fn read_record(&self) -> Result<RecoveryRecord> {
        validate_directory(&self.root)?;
        let mut file = match open_read_no_reparse(&self.state_path) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Ok(RecoveryRecord::default());
            }
            Err(error) => return Err(error).context("open strict recovery state"),
        };
        let metadata = file.metadata().context("inspect strict recovery state")?;
        validate_regular_file_metadata(&metadata)?;
        #[cfg(windows)]
        if self.verify_file_acl {
            crate::WindowsRecoveryAclVerifier::verify_file_handle(&file)?;
        }
        if metadata.len() > MAX_STATE_BYTES {
            bail!("strict recovery state exceeds its size limit");
        }

        let mut bytes = Vec::with_capacity(metadata.len() as usize);
        Read::take(&mut file, MAX_STATE_BYTES + 1)
            .read_to_end(&mut bytes)
            .context("read strict recovery state")?;
        if bytes.len() as u64 > MAX_STATE_BYTES {
            bail!("strict recovery state exceeds its size limit");
        }
        let stored: StoredRecoveryRecord =
            serde_json::from_slice(&bytes).context("parse strict recovery state")?;
        stored.validate()
    }

    fn write_record(&self, record: &RecoveryRecord) -> Result<()> {
        validate_directory(&self.root)?;
        match fs::symlink_metadata(&self.state_path) {
            Ok(metadata) => validate_regular_file_metadata(&metadata)?,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("inspect strict recovery state path"),
        }
        let stored = StoredRecoveryRecord {
            protocol: RECOVERY_FILE_PROTOCOL,
            high_watermark: record.high_watermark,
            marker: record.marker.clone(),
        };
        let bytes = serde_json::to_vec(&stored).context("serialize strict recovery state")?;
        if bytes.len() as u64 > MAX_STATE_BYTES {
            bail!("strict recovery state exceeds its size limit");
        }

        let (temporary_path, mut temporary_file) = self.create_temporary_file()?;
        let write_result = (|| -> Result<()> {
            temporary_file
                .write_all(&bytes)
                .context("write strict recovery temporary state")?;
            temporary_file
                .sync_all()
                .context("flush strict recovery temporary state")?;
            drop(temporary_file);
            replace_file(&temporary_path, &self.state_path)
                .context("atomically replace strict recovery state")?;
            Ok(())
        })();
        if write_result.is_err() {
            let _ = fs::remove_file(&temporary_path);
        }
        write_result
    }

    fn create_temporary_file(&self) -> Result<(PathBuf, File)> {
        for _ in 0..32 {
            let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = self.root.join(format!(
                ".strict-recovery-{}-{sequence}.tmp",
                std::process::id()
            ));
            match OpenOptions::new().write(true).create_new(true).open(&path) {
                Ok(file) => {
                    #[cfg(windows)]
                    if self.verify_file_acl {
                        if let Err(error) =
                            crate::WindowsRecoveryAclVerifier::verify_file_handle(&file)
                        {
                            drop(file);
                            let _ = fs::remove_file(&path);
                            return Err(error)
                                .context("verify strict recovery temporary state ACL");
                        }
                    }
                    return Ok((path, file));
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => {
                    return Err(error).context("create strict recovery temporary state");
                }
            }
        }
        bail!("could not allocate a strict recovery temporary state file")
    }
}

impl RecoveryStore for FileRecoveryStore {
    fn load(&mut self) -> Result<RecoveryRecord> {
        self.read_record()
    }

    fn persist(&mut self, marker: &RecoveryMarker) -> Result<()> {
        marker.validate()?;
        let current = self.read_record()?;
        if marker.revision < current.high_watermark {
            bail!("strict recovery revision rollback rejected");
        }
        self.write_record(&RecoveryRecord {
            high_watermark: current.high_watermark.max(marker.revision),
            marker: Some(marker.clone()),
        })
    }

    fn clear_marker(&mut self) -> Result<()> {
        let current = self.read_record()?;
        self.write_record(&RecoveryRecord {
            high_watermark: current.high_watermark,
            marker: None,
        })
    }
}

fn validate_directory(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path).context("inspect strict recovery directory")?;
    if !metadata.is_dir() || is_reparse_or_symlink(&metadata) {
        bail!("strict recovery directory is not a plain directory");
    }
    Ok(())
}

fn validate_regular_file_metadata(metadata: &fs::Metadata) -> Result<()> {
    if !metadata.is_file() || is_reparse_or_symlink(metadata) {
        bail!("strict recovery state is not a plain file");
    }
    Ok(())
}

#[cfg(windows)]
fn is_reparse_or_symlink(metadata: &fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;

    const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x0400;
    metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
}

#[cfg(not(windows))]
fn is_reparse_or_symlink(metadata: &fs::Metadata) -> bool {
    metadata.file_type().is_symlink()
}

#[cfg(windows)]
fn open_read_no_reparse(path: &Path) -> io::Result<File> {
    use std::os::windows::fs::OpenOptionsExt;

    const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
    OpenOptions::new()
        .read(true)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT)
        .open(path)
}

#[cfg(not(windows))]
fn open_read_no_reparse(path: &Path) -> io::Result<File> {
    OpenOptions::new().read(true).open(path)
}

#[cfg(windows)]
fn replace_file(source: &Path, destination: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;

    const MOVEFILE_REPLACE_EXISTING: u32 = 0x0000_0001;
    const MOVEFILE_WRITE_THROUGH: u32 = 0x0000_0008;

    #[link(name = "Kernel32")]
    unsafe extern "system" {
        fn MoveFileExW(
            existing_file_name: *const u16,
            new_file_name: *const u16,
            flags: u32,
        ) -> i32;
    }

    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    // SAFETY: both buffers are immutable, NUL-terminated UTF-16 strings for the call duration.
    let result = unsafe {
        MoveFileExW(
            source.as_ptr(),
            destination.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn replace_file(source: &Path, destination: &Path) -> io::Result<()> {
    fs::rename(source, destination)
}

#[cfg(test)]
mod tests {
    use std::time::{SystemTime, UNIX_EPOCH};

    use flclash_strict_contract::{StrictIdentity, StrictPolicyBundle, StrictPolicyEntry};

    use super::*;

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

    fn test_store(directory: &TestDirectory) -> FileRecoveryStore {
        FileRecoveryStore::from_verified_topology(directory.path(), false).unwrap()
    }

    #[test]
    fn marker_round_trip_and_clear_preserve_revision_high_watermark() {
        let directory = TestDirectory::new("roundtrip");
        let mut store = test_store(&directory);
        let desired = policy(41);
        let marker =
            RecoveryMarker::blocking(desired.clone(), desired.canonical_digest().unwrap(), 3);

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
        let mut store = test_store(&directory);
        let desired = policy(42);
        let valid =
            RecoveryMarker::blocking(desired.clone(), desired.canonical_digest().unwrap(), 5);
        store.persist(&valid).unwrap();

        let tampered = RecoveryMarker::blocking(desired, hex('0'), 6);
        assert!(store.persist(&tampered).is_err());
        assert_eq!(store.load().unwrap().marker, Some(valid));
    }

    #[test]
    fn relative_directory_and_oversized_state_are_rejected() {
        assert!(FileRecoveryStore::from_verified_topology("relative-state", false).is_err());

        let directory = TestDirectory::new("oversized");
        let state_path = directory.path().join("strict-recovery-v1.json");
        fs::write(&state_path, vec![b'x'; 2 * 1024 * 1024 + 1]).unwrap();
        let mut store = test_store(&directory);

        assert!(store.load().is_err());
    }

    #[cfg(windows)]
    #[test]
    fn public_constructor_rejects_an_ordinary_user_writable_temp_directory() {
        let directory = TestDirectory::new("acl-rejection");
        assert!(FileRecoveryStore::from_presecured_directory(directory.path()).is_err());
    }
}
