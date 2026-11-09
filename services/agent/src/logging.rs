use std::fs::{self, File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, SyncSender, TryRecvError, TrySendError};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

const CHANNEL_CAPACITY: usize = 256;
const MAX_LINE_CHARS: usize = 16 * 1024;
const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_ROTATED_FILES: usize = 3;
const MAX_BOOTSTRAP_FILE_BYTES: u64 = 64 * 1024;
const LOG_BUFFER_BYTES: usize = 32 * 1024;

#[derive(Clone)]
pub struct AgentLogger {
    sender: SyncSender<String>,
    dropped: Arc<AtomicU64>,
}

impl AgentLogger {
    pub fn new(home: &Path) -> Arc<Self> {
        let path = home.join("logs").join("FlClashAgent.log");
        let (sender, receiver) = mpsc::sync_channel(CHANNEL_CAPACITY);
        let dropped = Arc::new(AtomicU64::new(0));
        let writer_dropped = Arc::clone(&dropped);
        let writer_path = path.clone();
        let spawned = thread::Builder::new()
            .name("flclash-agent-log".to_owned())
            .spawn(move || run_writer(writer_path, receiver, writer_dropped))
            .is_ok();
        if !spawned {
            eprintln!("FlClashAgent: unable to start persistent log writer");
        }
        Arc::new(Self { sender, dropped })
    }

    pub fn log(&self, message: impl AsRef<str>) {
        let line = sanitize(message.as_ref());
        match self.sender.try_send(line) {
            Ok(()) => {}
            Err(TrySendError::Disconnected(_) | TrySendError::Full(_)) => {
                self.dropped.fetch_add(1, Ordering::Relaxed);
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

struct BufferedLogFile {
    writer: BufWriter<File>,
    written_bytes: u64,
}

fn run_writer(path: PathBuf, receiver: mpsc::Receiver<String>, dropped: Arc<AtomicU64>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut file = open_file(&path);
    while let Ok(first_message) = receiver.recv() {
        let count = dropped.swap(0, Ordering::Relaxed);
        if count > 0 {
            write_log_line(&path, &mut file, &format!("event=logger_dropped count={count}"));
        }
        write_log_line(&path, &mut file, &first_message);
        loop {
            match receiver.try_recv() {
                Ok(next_message) => write_log_line(&path, &mut file, &next_message),
                Err(TryRecvError::Empty | TryRecvError::Disconnected) => break,
            }
        }
        if let Some(current) = file.as_mut() {
            if current.writer.flush().is_err() {
                file = open_file(&path);
            }
        }
    }
}

fn write_log_line(path: &Path, file: &mut Option<BufferedLogFile>, message: &str) {
    let line = format!("[unix_ms={}] {message}\n", unix_millis());
    let line_bytes = line.len() as u64;
    let should_rotate = file
        .as_ref()
        .is_none_or(|current| current.written_bytes.saturating_add(line_bytes) > MAX_FILE_BYTES);
    if should_rotate {
        if let Some(mut previous) = file.take() {
            let _ = previous.writer.flush();
        }
        rotate(path);
        *file = open_file(path);
    }
    let Some(current) = file.as_mut() else {
        return;
    };
    if current.writer.write_all(line.as_bytes()).is_ok() {
        current.written_bytes = current.written_bytes.saturating_add(line_bytes);
    } else {
        *file = open_file(path);
    }
}

fn open_file(path: &Path) -> Option<BufferedLogFile> {
    let file = OpenOptions::new().create(true).append(true).open(path).ok()?;
    let written_bytes = file.metadata().map(|metadata| metadata.len()).unwrap_or(0);
    Some(BufferedLogFile {
        writer: BufWriter::with_capacity(LOG_BUFFER_BYTES, file),
        written_bytes,
    })
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
    fn counts_full_and_disconnected_queue_drops() {
        let (sender, receiver) = mpsc::sync_channel(1);
        let logger = AgentLogger { sender, dropped: Arc::new(AtomicU64::new(0)) };
        logger.log("accepted");
        logger.log("queue full");
        assert_eq!(logger.dropped.load(Ordering::Relaxed), 1);
        drop(receiver);
        logger.log("disconnected");
        assert_eq!(logger.dropped.load(Ordering::Relaxed), 2);
    }
}
