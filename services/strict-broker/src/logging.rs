use std::fs::{self, File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, SyncSender, TryRecvError, TrySendError};
use std::sync::Arc;
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

const CHANNEL_CAPACITY: usize = 256;
const MAX_LINE_CHARS: usize = 16 * 1024;
const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_ROTATED_FILES: usize = 3;
const LOG_BUFFER_BYTES: usize = 32 * 1024;
const LOG_DIRECTORY: &str = "FreedomNet.StrictBroker";
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

struct BufferedLogFile {
    writer: BufWriter<File>,
    written_bytes: u64,
}

fn run_writer(path: PathBuf, receiver: mpsc::Receiver<String>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut file = open_file(&path);
    while let Ok(first_message) = receiver.recv() {
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
