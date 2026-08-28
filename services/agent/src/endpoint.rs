use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use fs2::FileExt;
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};

use crate::protocol::PROTOCOL_VERSION;

pub const ENDPOINT_FILE_NAME: &str = "flclashx-agent-v1.json";
const LOCK_FILE_NAME: &str = "flclashx-agent-v1.lock";
pub const HELPER_TOKEN_FILE_NAME: &str = "flclashx-helper-v1.token";

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
pub struct EndpointDocument {
    pub protocol: u32,
    pub port: u16,
    pub token: String,
    pub pid: u32,
}

pub struct EndpointGuard {
    endpoint_path: PathBuf,
    token: String,
    _lock: File,
}

impl EndpointGuard {
    pub fn acquire(home: &Path, address: SocketAddr) -> Result<(Self, EndpointDocument)> {
        let lock_path = home.join(LOCK_FILE_NAME);
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&lock_path)
            .context("unable to open Agent singleton lock")?;
        lock.try_lock_exclusive()
            .context("another FlClashAgent instance already owns this user data directory")?;
        restrict_to_owner(&lock_path)?;

        let token = random_token();
        let document = EndpointDocument {
            protocol: PROTOCOL_VERSION,
            port: address.port(),
            token: token.clone(),
            pid: std::process::id(),
        };
        let endpoint_path = home.join(ENDPOINT_FILE_NAME);
        write_atomic(&endpoint_path, &serde_json::to_vec(&document)?)?;

        Ok((
            Self {
                endpoint_path,
                token,
                _lock: lock,
            },
            document,
        ))
    }
}

impl Drop for EndpointGuard {
    fn drop(&mut self) {
        let belongs_to_self = fs::read(&self.endpoint_path)
            .ok()
            .and_then(|data| serde_json::from_slice::<EndpointDocument>(&data).ok())
            .is_some_and(|document| document.token == self.token);
        if belongs_to_self {
            let _ = fs::remove_file(&self.endpoint_path);
        }
    }
}

pub(crate) fn random_token() -> String {
    let mut bytes = [0_u8; 32];
    OsRng.fill_bytes(&mut bytes);
    let mut token = String::with_capacity(64);
    const HEX: &[u8; 16] = b"0123456789abcdef";
    for byte in bytes {
        token.push(HEX[usize::from(byte >> 4)] as char);
        token.push(HEX[usize::from(byte & 0x0f)] as char);
    }
    token
}

pub fn load_or_create_helper_token(home: &Path) -> Result<String> {
    let path = home.join(HELPER_TOKEN_FILE_NAME);
    match OpenOptions::new().create_new(true).write(true).open(&path) {
        Ok(mut file) => {
            restrict_to_owner(&path)?;
            let token = random_token();
            file.write_all(token.as_bytes())?;
            file.sync_all()?;
            Ok(token)
        }
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            let metadata = fs::metadata(&path).context("unable to inspect Helper token")?;
            if !metadata.is_file() || metadata.len() != 64 {
                anyhow::bail!("invalid Helper token file");
            }
            let token = fs::read_to_string(&path).context("unable to read Helper token")?;
            if token.len() != 64 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                anyhow::bail!("invalid Helper token file");
            }
            Ok(token.to_ascii_lowercase())
        }
        Err(error) => Err(error).context("unable to create Helper token"),
    }
}

fn write_atomic(path: &Path, data: &[u8]) -> Result<()> {
    let pending = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&pending)?;
    restrict_to_owner(&pending)?;
    file.write_all(data)?;
    file.sync_all()?;
    drop(file);
    if path.exists() {
        fs::remove_file(path)?;
    }
    fs::rename(pending, path)?;
    Ok(())
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) -> Result<()> {
    // The file inherits the per-user Application Support directory ACL on
    // Windows. The Agent additionally requires a fresh 256-bit token.
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "flclashx-agent-endpoint-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(&path).expect("create temp directory");
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn helper_token_is_random_bounded_and_stable() {
        let home = TempDir::new();
        let first = load_or_create_helper_token(&home.0).expect("create token");
        let second = load_or_create_helper_token(&home.0).expect("reuse token");

        assert_eq!(first, second);
        assert_eq!(first.len(), 64);
        assert!(first.bytes().all(|byte| byte.is_ascii_hexdigit()));
    }

    #[test]
    fn malformed_existing_helper_token_is_not_repaired_silently() {
        let home = TempDir::new();
        fs::write(home.0.join(HELPER_TOKEN_FILE_NAME), b"partial").expect("write token");
        assert!(load_or_create_helper_token(&home.0).is_err());
    }
}
