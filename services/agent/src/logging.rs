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
const MAX_BOOTSTRAP_FILE_BYTES: u64 = 64 * 1024;

#[derive(Clone)]
pub struct AgentLogger {
    sender: SyncSender<String>,
}

impl AgentLogger {
    pub fn new(home: &Path) -> Arc<Self> {
        let path = home.join("logs").join("FlClashAgent.log");
        let (sender, receiver) = mpsc::sync_channel(CHANNEL_CAPACITY);
        let writer_path = path.clone();
        let spawned = thread::Builder::new()
            .name("flclash-agent-log".to_owned())
            .spawn(move || run_writer(writer_path, receiver))
            .is_ok();
        if !spawned {
            eprintln!("FlClashAgent: unable to start persistent log writer");
        }
        Arc::new(Self { sender })
    }

    pub fn log(&self, message: impl AsRef<str>) {
        let line = sanitize(message.as_ref());
        match self.sender.try_send(line) {
            Ok(()) | Err(TrySendError::Disconnected(_)) => {}
            Err(TrySendError::Full(_)) => {
                // The queue is intentionally bounded. Dropping the newest
                // diagnostic is preferable to retaining unbounded memory on a
                // noisy Core or a stalled filesystem.
            }
        }
    }
}

/// Persist failures that occur before a valid `--home` argument is available.
///
/// The normal logger is intentionally home-directory scoped. Argument parsing
/// happens before that directory can be trusted, so this rare fatal path uses
/// the same per-user application data root without spawning a background
/// writer that could be terminated before it flushes.
pub fn log_bootstrap_failure(message: impl AsRef<str>) {
    let path = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .map(|root| {
            root.join("com.follow")
                .join("clashx")
                .join("logs")
                .join("FlClashAgent.bootstrap.log")
        })
        .or_else(|| {
            std::env::var_os("LOCALAPPDATA")
                .map(PathBuf::from)
                .map(|root| {
                    root.join("FlClashX")
                        .join("logs")
                        .join("FlClashAgent.bootstrap.log")
                })
        })
        .or_else(|| {
            std::env::current_exe()
                .ok()
                .and_then(|path| path.parent().map(Path::to_path_buf))
                .map(|root| root.join("logs").join("FlClashAgent.bootstrap.log"))
        });
    let Some(path) = path else {
        return;
    };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if fs::metadata(&path)
        .map(|metadata| metadata.len() > MAX_BOOTSTRAP_FILE_BYTES)
        .unwrap_or(false)
    {
        let _ = fs::write(&path, []);
    }
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let line = format!(
        "[unix_ms={}] bootstrap: {}\n",
        unix_millis(),
        sanitize(message.as_ref())
    );
    let _ = file.write_all(line.as_bytes());
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
