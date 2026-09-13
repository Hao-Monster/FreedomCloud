use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::sync::Arc;
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

const CHANNEL_CAPACITY: usize = 256;
const MAX_LINE_CHARS: usize = 16 * 1024;
const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_ROTATED_FILES: usize = 3;
const LOG_DIRECTORY: &str = "FlClashX.StrictBroker";
const LOG_FILE_NAME: &str = "FlClashStrictBroker.log";

#[derive(Clone)]
pub struct StrictBrokerLogger {
    sender: SyncSender<String>,
}

impl StrictBrokerLogger {
    pub fn new_default() -> Arc<Self> {
        let path = default_log_path();
        let (sender, receiver) = mpsc::sync_channel(CHANNEL_CAPACITY);
        let writer_path = path.clone();
        let spawned = thread::Builder::new()
            .name("flclash-strict-broker-log".to_owned())
            .spawn(move || run_writer(writer_path, receiver))
            .is_ok();
        if !spawned {
            eprintln!("FlClashStrictBroker: unable to start persistent log writer");
        }
        Arc::new(Self { sender })
    }

    pub fn log(&self, message: impl AsRef<str>) {
        let line = sanitize(message.as_ref());
        match self.sender.try_send(line) {
            Ok(()) | Err(TrySendError::Disconnected(_)) => {}
            Err(TrySendError::Full(_)) => {
                // The Broker must keep its control path bounded even if a
                // dependency emits more diagnostics than the disk can accept.
            }
        }
    }
}

fn default_log_path() -> PathBuf {
    let root = std::env::var_os("ProgramData")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
    root.join(LOG_DIRECTORY).join("logs").join(LOG_FILE_NAME)
}

fn sanitize(message: &str) -> String {
    let mut output = String::with_capacity(message.len().min(MAX_LINE_CHARS));
    for character in message.chars().take(MAX_LINE_CHARS) {
        if matches!(character, '\r' | '\n') {
            output.push(' ');
        } else {
            output.push(character);
        }
    }
    output
}

fn run_writer(path: PathBuf, receiver: mpsc::Receiver<String>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut file = open_file(&path);
    while let Ok(message) = receiver.recv() {
        let line = format!("[unix_ms={}] {message}\n", unix_millis());
        let should_rotate = file
            .as_ref()
            .and_then(|current| current.metadata().ok())
            .is_none_or(|metadata| {
                metadata.len().saturating_add(line.len() as u64) > MAX_FILE_BYTES
            });
        if should_rotate {
            let _ = file.take();
            rotate(&path);
            file = open_file(&path);
        }
        let Some(current) = file.as_mut() else {
            continue;
        };
        if current.write_all(line.as_bytes()).is_ok() {
            let _ = current.flush();
        } else {
            file = open_file(&path);
        }
    }
}

fn open_file(path: &Path) -> Option<File> {
    OpenOptions::new().create(true).append(true).open(path).ok()
}

fn rotate(path: &Path) {
    for index in (1..MAX_ROTATED_FILES).rev() {
        let source = rotated_path(path, index);
        let target = rotated_path(path, index + 1);
        let _ = fs::remove_file(&target);
        let _ = fs::rename(&source, &target);
    }
    let first = rotated_path(path, 1);
    let _ = fs::remove_file(&first);
    let _ = fs::rename(path, first);
}

fn rotated_path(path: &Path, index: usize) -> PathBuf {
    let mut value = path.as_os_str().to_os_string();
    value.push(format!(".{index}"));
    PathBuf::from(value)
}

fn unix_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis())
}
