use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
#[cfg(any(test, all(feature = "windows-service", target_os = "windows")))]
use std::time::Instant;
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
    output: Arc<CoreOutputActivity>,
    dropped_lines: Arc<AtomicU64>,
}

enum LogMessage {
    Line(String),
    Flush(SyncSender<Result<(), LogFlushError>>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LogFlushError {
    QueueFull,
    WriterDisconnected,
    TimedOut,
    Output(String),
    DroppedLines(u64),
}

impl std::fmt::Display for LogFlushError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::QueueFull => formatter.write_str("log flush queue is full"),
            Self::WriterDisconnected => formatter.write_str("log writer is disconnected"),
            Self::TimedOut => formatter.write_str("log flush acknowledgement timed out"),
            Self::Output(error) => write!(formatter, "log output failed: {error}"),
            Self::DroppedLines(count) => write!(formatter, "log queue dropped {count} lines"),
        }
    }
}

#[derive(Default)]
struct CoreOutputActivity {
    active: Mutex<usize>,
    completed: Condvar,
    failed: AtomicU64,
}

pub(super) struct CoreOutputGuard(Arc<CoreOutputActivity>);

impl Drop for CoreOutputGuard {
    fn drop(&mut self) {
        if thread::panicking() {
            self.0.failed.fetch_add(1, Ordering::Relaxed);
        }
        let mut active = self
            .0
            .active
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        *active -= 1;
        self.0.completed.notify_all();
    }
}

#[derive(Debug)]
#[cfg(any(test, all(feature = "windows-service", target_os = "windows")))]
pub(super) struct CoreOutputFinishError {
    pending_readers: usize,
    failed_readers: u64,
    flush: Option<LogFlushError>,
}

#[cfg(any(test, all(feature = "windows-service", target_os = "windows")))]
impl std::fmt::Display for CoreOutputFinishError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "Core output finish incomplete: {} readers pending, {} reader failures",
            self.pending_readers, self.failed_readers
        )?;
        if let Some(error) = &self.flush {
            write!(formatter, "; {error}")?;
        }
        Ok(())
    }
}

impl ServiceLogger {
    #[cfg(test)]
    pub(super) fn discard_for_test() -> Arc<Self> {
        let (sender, _) = mpsc::sync_channel(1);
        Arc::new(Self::from_sender(sender))
    }

    pub fn new_default() -> Arc<Self> {
        Self::new_at_path(default_log_path())
    }

    pub(super) fn new_at_path(path: PathBuf) -> Arc<Self> {
        Self::start_writer(path, MAX_FILE_BYTES)
    }

    fn from_sender(sender: SyncSender<LogMessage>) -> Self {
        Self {
            sender,
            output: Arc::new(CoreOutputActivity::default()),
            dropped_lines: Arc::new(AtomicU64::new(0)),
        }
    }

    fn start_writer(path: PathBuf, max_file_bytes: u64) -> Arc<Self> {
        let (sender, receiver) = mpsc::sync_channel(CHANNEL_CAPACITY);
        let spawned = thread::Builder::new()
            .name("flclash-helper-log".to_owned())
            .spawn(move || run_writer(path, receiver, max_file_bytes))
            .is_ok();
        if !spawned {
            eprintln!("FlClashHelperService: unable to start persistent log writer");
        }
        Arc::new(Self::from_sender(sender))
    }

    pub fn log(&self, message: impl AsRef<str>) {
        let line = sanitize(message.as_ref());
        match self.sender.try_send(LogMessage::Line(line)) {
            Ok(()) | Err(TrySendError::Disconnected(_)) => {}
            Err(TrySendError::Full(_)) => {
                // Keep service memory bounded even when Core is noisy or the
                // filesystem is temporarily unavailable. Keep loss observable
                // at the shutdown barrier without changing producer latency.
                self.dropped_lines.fetch_add(1, Ordering::Relaxed);
            }
        }
    }

    /// A stalled filesystem must not hang service shutdown.
    pub fn flush(&self, limit: Duration) -> Result<(), LogFlushError> {
        let (tx, rx) = mpsc::sync_channel(1);
        self.sender
            .try_send(LogMessage::Flush(tx))
            .map_err(|error| match error {
                TrySendError::Full(_) => LogFlushError::QueueFull,
                TrySendError::Disconnected(_) => LogFlushError::WriterDisconnected,
            })?;
        rx.recv_timeout(limit).map_err(|error| match error {
            RecvTimeoutError::Timeout => LogFlushError::TimedOut,
            RecvTimeoutError::Disconnected => LogFlushError::WriterDisconnected,
        })??;
        match self.dropped_lines.load(Ordering::Relaxed) {
            0 => Ok(()),
            count => Err(LogFlushError::DroppedLines(count)),
        }
    }

    pub(super) fn register_core_output(&self) -> CoreOutputGuard {
        let mut active = self
            .output
            .active
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        *active += 1;
        CoreOutputGuard(self.output.clone())
    }

    pub(super) fn record_core_output_failure(&self) {
        self.output.failed.fetch_add(1, Ordering::Relaxed);
    }

    #[cfg(any(test, all(feature = "windows-service", target_os = "windows")))]
    fn drain_core_output(&self, limit: Duration) -> usize {
        let deadline = Instant::now() + limit;
        let mut active = self
            .output
            .active
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        while *active != 0 {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                break;
            }
            let (next, _) = self
                .output
                .completed
                .wait_timeout(active, remaining)
                .unwrap_or_else(|error| error.into_inner());
            active = next;
        }
        *active
    }

    /// Call only after Core exit is confirmed and new starts are gated. A child
    /// exit alone does not mean its stdout/stderr readers have enqueued the tail.
    #[cfg(any(test, all(feature = "windows-service", target_os = "windows")))]
    pub(super) fn finish_core_output(
        &self,
        drain_limit: Duration,
        flush_limit: Duration,
    ) -> Result<(), CoreOutputFinishError> {
        let pending_readers = self.drain_core_output(drain_limit);
        let failed_readers = self.output.failed.load(Ordering::Relaxed);
        self.log("service Core exit confirmed; stopping Helper");
        let flush = self.flush(flush_limit).err();
        if pending_readers == 0 && failed_readers == 0 && flush.is_none() {
            Ok(())
        } else {
            Err(CoreOutputFinishError {
                pending_readers,
                failed_readers,
                flush,
            })
        }
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

fn run_writer(path: PathBuf, receiver: mpsc::Receiver<LogMessage>, max_file_bytes: u64) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let file = open_file(&path).ok();
    write_messages(path, receiver, max_file_bytes, file);
}

fn write_messages(
    path: PathBuf,
    receiver: mpsc::Receiver<LogMessage>,
    max_file_bytes: u64,
    mut file: Option<File>,
) {
    // A later successful reopen cannot restore a line already lost to I/O.
    // Retain only the first error, keeping diagnostics and memory bounded.
    let mut first_output_error: Option<String> = None;
    while let Ok(message) = receiver.recv() {
        let message = match message {
            LogMessage::Line(line) => line,
            LogMessage::Flush(done) => {
                let result = file
                    .as_mut()
                    .ok_or_else(|| io::Error::other("log file is unavailable"))
                    .and_then(Write::flush);
                if let Err(error) = result {
                    first_output_error.get_or_insert_with(|| error.to_string());
                }
                let result = first_output_error
                    .as_ref()
                    .map_or(Ok(()), |error| Err(LogFlushError::Output(error.clone())));
                let _ = done.send(result);
                continue;
            }
        };
        let line = format!("[unix_ms={}] {message}\n", unix_millis());
        if let Err(error) = write_line(&path, &mut file, line.as_bytes(), max_file_bytes) {
            first_output_error.get_or_insert_with(|| error.to_string());
            file = None;
        }
    }
}

fn write_line(
    path: &Path,
    file: &mut Option<File>,
    line: &[u8],
    max_file_bytes: u64,
) -> io::Result<()> {
    if file.is_none() {
        *file = Some(open_file(path)?);
    }
    let length = file.as_ref().expect("file opened above").metadata()?.len();
    if length.saturating_add(line.len() as u64) > max_file_bytes {
        *file = None;
        rotate(path)?;
        *file = Some(open_file(path)?);
    }
    let current = file.as_mut().expect("file opened above");
    current.write_all(line)?;
    current.flush()
}

fn open_file(path: &Path) -> io::Result<File> {
    OpenOptions::new().create(true).append(true).open(path)
}

fn remove_if_present(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        result => result,
    }
}

fn rotate(path: &Path) -> io::Result<()> {
    for index in (1..MAX_ROTATED_FILES).rev() {
        let source = rotated_path(path, index);
        let target = rotated_path(path, index + 1);
        if source.try_exists()? {
            remove_if_present(&target)?;
            fs::rename(&source, &target)?;
        }
    }
    let first = rotated_path(path, 1);
    remove_if_present(&first)?;
    fs::rename(path, first)
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

    struct LogDirectory(PathBuf);

    impl LogDirectory {
        fn new() -> Self {
            static NEXT: AtomicU64 = AtomicU64::new(0);
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "flclashx-helper-r1-{}-{nonce}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for LogDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn resource_r1_flush_ack_timeout_and_disconnect_are_distinct() {
        let (sender, receiver) = mpsc::sync_channel(1);
        let logger = ServiceLogger::from_sender(sender);
        let started = Instant::now();
        assert_eq!(
            logger.flush(Duration::from_millis(20)),
            Err(LogFlushError::TimedOut)
        );
        assert!(started.elapsed() < Duration::from_secs(1));
        drop(receiver);
        assert_eq!(
            logger.flush(Duration::from_secs(1)),
            Err(LogFlushError::WriterDisconnected)
        );
    }

    #[test]
    fn resource_r1_dropped_queue_lines_remain_visible_after_successful_flush() {
        let (sender, receiver) = mpsc::sync_channel(1);
        let logger = ServiceLogger::from_sender(sender);
        logger.log("accepted");
        logger.log("dropped");
        assert!(matches!(receiver.recv().unwrap(), LogMessage::Line(line) if line == "accepted"));
        let writer = thread::spawn(move || {
            for message in receiver {
                if let LogMessage::Flush(done) = message {
                    done.send(Ok(())).unwrap();
                }
            }
        });
        for _ in 0..2 {
            assert_eq!(
                logger.flush(Duration::from_secs(1)),
                Err(LogFlushError::DroppedLines(1))
            );
        }
        drop(logger);
        writer.join().unwrap();
    }

    #[test]
    fn resource_r1_drain_times_out_without_claiming_a_complete_tail() {
        let root = LogDirectory::new();
        let path = root.0.join("helper.log");
        let logger = ServiceLogger::new_at_path(path.clone());
        let guard = logger.register_core_output();
        logger.log("already queued");
        let started = Instant::now();
        let error = logger
            .finish_core_output(Duration::from_millis(20), Duration::from_secs(1))
            .unwrap_err();
        assert_eq!(error.pending_readers, 1);
        assert_eq!(error.failed_readers, 0);
        assert!(
            error.flush.is_none(),
            "queued diagnostics should still be flushed"
        );
        assert!(started.elapsed() < Duration::from_secs(1));
        assert!(fs::read_to_string(path).unwrap().contains("already queued"));
        drop(guard);
        assert!(logger
            .finish_core_output(Duration::from_secs(1), Duration::from_secs(1))
            .is_ok());
    }

    #[test]
    fn resource_r1_output_guards_release_on_unwind_and_unstarted_thread_drop() {
        let logger = ServiceLogger::discard_for_test();
        let guard = logger.register_core_output();
        let not_started = move || {
            let _guard = guard;
        };
        drop(not_started); // thread creation failure drops the captured closure.
        assert_eq!(logger.drain_core_output(Duration::ZERO), 0);
        let guard = logger.register_core_output();
        assert!(std::panic::catch_unwind(move || {
            let _guard = guard;
            panic!("reader fixture");
        })
        .is_err());
        assert_eq!(logger.drain_core_output(Duration::ZERO), 0);
        assert_eq!(logger.output.failed.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn resource_r1_shared_writer_rotates_interleaved_sources_once() {
        let root = LogDirectory::new();
        let path = root.0.join("helper.log");
        let logger = ServiceLogger::start_writer(path.clone(), 180);
        let core = logger.clone();
        for index in 0..8 {
            if index % 2 == 0 {
                logger.log(format!("service record-{index}"));
            } else {
                core.log(format!("Core stdout record-{index}"));
            }
        }
        logger.flush(Duration::from_secs(1)).unwrap();
        let mut text = String::new();
        let mut files = 0;
        for candidate in std::iter::once(path.clone())
            .chain((1..=MAX_ROTATED_FILES).map(|index| rotated_path(&path, index)))
        {
            if candidate.exists() {
                files += 1;
                assert!(fs::metadata(&candidate).unwrap().len() <= 180);
                text.push_str(&fs::read_to_string(candidate).unwrap());
            }
        }
        assert!(files > 1, "fixture must cross an actual rotation");
        for index in 0..8 {
            assert_eq!(text.matches(&format!("record-{index}")).count(), 1);
        }
        assert_eq!(text.lines().count(), 8);
    }

    #[test]
    fn resource_r1_actual_file_write_failure_is_sticky_after_reopen() {
        let root = LogDirectory::new();
        let path = root.0.join("helper.log");
        fs::write(&path, []).unwrap();
        let read_only = File::open(&path).unwrap();
        let (sender, receiver) = mpsc::sync_channel(CHANNEL_CAPACITY);
        let logger = ServiceLogger::from_sender(sender);
        let writer_path = path.clone();
        let writer = thread::spawn(move || {
            write_messages(writer_path, receiver, MAX_FILE_BYTES, Some(read_only))
        });
        logger.log("lost-readonly-write");
        assert!(matches!(
            logger.flush(Duration::from_secs(1)),
            Err(LogFlushError::Output(_))
        ));
        logger.log("reopened-successfully");
        assert!(matches!(
            logger.flush(Duration::from_secs(1)),
            Err(LogFlushError::Output(_))
        ));
        let text = fs::read_to_string(path).unwrap();
        assert!(!text.contains("lost-readonly-write"));
        assert!(text.contains("reopened-successfully"));
        drop(logger);
        writer.join().unwrap();
    }

    #[test]
    fn resource_log_flush_is_bounded_when_queue_is_full_or_closed() {
        let (sender, receiver) = mpsc::sync_channel(1);
        let logger = ServiceLogger::from_sender(sender);
        logger.log("fills queue");
        let started = std::time::Instant::now();
        assert_eq!(
            logger.flush(Duration::from_millis(25)),
            Err(LogFlushError::QueueFull)
        );
        assert!(started.elapsed() < Duration::from_secs(1));
        drop(receiver);
        assert_eq!(
            logger.flush(Duration::from_millis(25)),
            Err(LogFlushError::WriterDisconnected)
        );
    }
}
