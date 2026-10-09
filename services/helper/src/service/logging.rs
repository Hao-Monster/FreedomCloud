use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, SyncSender, TrySendError};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const CHANNEL_CAPACITY: usize = 256;
const MAX_LINE_CHARS: usize = 16 * 1024;
const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_ROTATED_FILES: usize = 3;
const LOG_DIRECTORY: &str = "FlClashX";
const LOG_FILE_NAME: &str = "FlClashHelperService.log";

#[derive(Clone)]
pub struct ServiceLogger {
    sender: SyncSender<LogMessage>,
}

enum LogMessage { Line(String), Flush(SyncSender<()>) }

impl ServiceLogger {
    #[cfg(test)]
    pub(super) fn discard_for_test() -> Arc<Self> {
        let (sender, _) = mpsc::sync_channel(1);
        Arc::new(Self { sender })
    }

    pub fn new_default() -> Arc<Self> {
        let path = default_log_path();
        let (sender, receiver) = mpsc::sync_channel(CHANNEL_CAPACITY);
        let writer_path = path.clone();
        let spawned = thread::Builder::new()
            .name("flclash-helper-log".to_owned())
            .spawn(move || run_writer(writer_path, receiver))
            .is_ok();
        if !spawned {
            eprintln!("FlClashHelperService: unable to start persistent log writer");
        }
        Arc::new(Self { sender })
    }

    pub fn log(&self, message: impl AsRef<str>) {
        let line = sanitize(message.as_ref());
        match self.sender.try_send(LogMessage::Line(line)) {
            Ok(()) | Err(TrySendError::Disconnected(_)) => {}
            Err(TrySendError::Full(_)) => {
                // Keep service memory bounded even when Core is noisy or the
                // filesystem is temporarily unavailable.
            }
        }
    }

    /// A stalled filesystem must not hang service shutdown.
    pub fn flush(&self, limit: Duration) -> bool {
        let (tx, rx) = mpsc::sync_channel(1);
        self.sender.try_send(LogMessage::Flush(tx)).is_ok() && rx.recv_timeout(limit).is_ok()
    }
}

fn default_log_path() -> PathBuf {
    let root = std::env::var_os("ProgramData")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::current_exe()
                .ok()
                .and_then(|path| path.parent().map(Path::to_path_buf))
                .unwrap_or_else(|| PathBuf::from("."))
        });
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

fn run_writer(path: PathBuf, receiver: mpsc::Receiver<LogMessage>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut file = open_file(&path);
    while let Ok(message) = receiver.recv() {
        let message = match message {
            LogMessage::Line(line) => line,
            LogMessage::Flush(done) => {
                if file.as_mut().is_some_and(|current| current.flush().is_ok()) {
                    let _ = done.send(());
                }
                continue;
            }
        };
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resource_log_flush_is_bounded_when_queue_is_full_or_closed() {
        let (sender, receiver) = mpsc::sync_channel(1);
        let logger = ServiceLogger { sender };
        logger.log("fills queue");
        let started = std::time::Instant::now();
        assert!(!logger.flush(Duration::from_millis(25)));
        assert!(started.elapsed() < Duration::from_secs(1));
        drop(receiver);
        assert!(!logger.flush(Duration::from_millis(25)));
    }
}
