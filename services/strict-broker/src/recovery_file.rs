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
/// The directory must be provisioned before construction with an ACL limited to
/// LocalSystem and Administrators. This type verifies path topology and avoids
/// following Windows reparse points, but intentionally does not create or relax
/// directory permissions.
pub struct FileRecoveryStore {
    root: PathBuf,
    state_path: PathBuf,
}

impl FileRecoveryStore {
    pub fn from_presecured_directory(path: impl AsRef<Path>) -> Result<Self> {
        let root = path.as_ref();
        if !root.is_absolute() {
            bail!("strict recovery directory must be absolute");
        }
        validate_directory(root)?;
        Ok(Self {
            root: root.to_path_buf(),
            state_path: root.join(STATE_FILE_NAME),
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
                Ok(file) => return Ok((path, file)),
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
