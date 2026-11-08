use std::io;
use std::process::Child;
use std::time::{Duration, Instant};

pub(super) trait ManagedProcess {
    fn has_exited(&mut self) -> io::Result<bool>;
    fn request_kill(&mut self) -> io::Result<()>;
    fn wait_for_exit(&mut self, timeout: Duration) -> io::Result<bool> {
        let deadline = Instant::now() + timeout;
        loop {
            if self.has_exited()? {
                return Ok(true);
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Ok(false);
            }
            std::thread::sleep(remaining.min(Duration::from_millis(10)));
        }
    }
}

impl ManagedProcess for Child {
    fn has_exited(&mut self) -> io::Result<bool> {
        self.try_wait().map(|status| status.is_some())
    }

    fn request_kill(&mut self) -> io::Result<()> {
        self.kill()
    }

    #[cfg(windows)]
    fn wait_for_exit(&mut self, timeout: Duration) -> io::Result<bool> {
        use std::os::windows::io::AsRawHandle;
        use windows_sys::Win32::Foundation::{WAIT_FAILED, WAIT_OBJECT_0, WAIT_TIMEOUT};
        use windows_sys::Win32::System::Threading::WaitForSingleObject;

        if self.has_exited()? {
            return Ok(true);
        }
        let wait_ms = u32::try_from(timeout.as_millis()).unwrap_or(u32::MAX - 1);
        // SAFETY: `self` owns a valid Windows process handle for the duration of the wait.
        let wait_status = unsafe { WaitForSingleObject(self.as_raw_handle() as _, wait_ms) };
        match wait_status {
            WAIT_OBJECT_0 => {
                let _ = self.try_wait()?;
                Ok(true)
            }
            WAIT_TIMEOUT => self.has_exited(),
            WAIT_FAILED => Err(io::Error::last_os_error()),
            other => Err(io::Error::other(format!(
                "unexpected WaitForSingleObject status 0x{other:08x}"
            ))),
        }
    }
}

pub(super) struct ManagedCore<P> {
    pub process: Option<P>,
    pub owner: Option<String>,
    service_stopping: bool,
}

impl<P> Default for ManagedCore<P> {
    fn default() -> Self {
        Self {
            process: None,
            owner: None,
            service_stopping: false,
        }
    }
}

impl<P: ManagedProcess> ManagedCore<P> {
    /// The same lock guards prepare_start: confirmed service shutdown cannot
    /// race a new child into the gap before the SCM worker exits.
    pub fn stop_for_service(&mut self, wait_limit: Duration) -> Result<(), String> {
        self.service_stopping = true;
        let result = self.stop(None, wait_limit);
        if result.is_err() { self.service_stopping = false; }
        result
    }

    pub fn stop(&mut self, owner: Option<&str>, wait_limit: Duration) -> Result<(), String> {
        if let Some(owner) = owner {
            validate_owner(owner)?;
            if self.owner.as_deref() != Some(owner) {
                return Err(
                    "Core owner is unknown or does not match; exit is unconfirmed".to_owned(),
                );
            }
        }
        stop_managed_process(&mut self.process, wait_limit)
    }

    /// Returns false for an idempotent start of the same live session. Owned
    /// starts never kill another session; it must be explicitly stopped first.
    pub fn prepare_start(
        &mut self,
        owner: Option<&str>,
        wait_limit: Duration,
    ) -> Result<bool, String> {
        if self.service_stopping { return Err("Helper service is stopping".to_owned()); }
        if let Some(owner) = owner {
            validate_owner(owner)?;
            if let Some(child) = self.process.as_mut() {
                if !child
                    .has_exited()
                    .map_err(|_| "Core exit is unconfirmed".to_owned())?
                {
                    return if self.owner.as_deref() == Some(owner) {
                        Ok(false)
                    } else {
                        Err("Another Core session is still active".to_owned())
                    };
                }
                self.process = None;
            }
            if self.owner.as_deref() == Some(owner) {
                return Err("Core owner session has already ended".to_owned());
            }
            self.owner = Some(owner.to_owned());
        } else {
            stop_managed_process(&mut self.process, wait_limit)?;
            self.owner = None;
        }
        Ok(true)
    }
}

pub(super) fn validate_owner(owner: &str) -> Result<(), String> {
    let Some((instance, attempt)) = owner.split_once('-') else {
        return Err("invalid Core owner".to_owned());
    };
    if instance.len() != 64
        || !instance
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
        || attempt.is_empty()
        || attempt.len() > 20
        || !attempt.bytes().all(|c| c.is_ascii_digit())
        || attempt.parse::<u64>().ok().is_none_or(|value| value == 0)
    {
        return Err("invalid Core owner".to_owned());
    }
    Ok(())
}

/// Retain the handle whenever exit cannot be proved. This makes a timed out
/// or failed stop retryable and prevents starting a second Core beside it.
pub(super) fn stop_managed_process<P: ManagedProcess>(
    process: &mut Option<P>,
    wait_limit: Duration,
) -> Result<(), String> {
    let Some(child) = process.as_mut() else {
        return Ok(());
    };
    if child
        .has_exited()
        .map_err(|error| format!("inspect Core exit failed: {error}"))?
    {
        *process = None;
        return Ok(());
    }
    if let Err(error) = child.request_kill() {
        if child
            .has_exited()
            .map_err(|error| format!("recheck Core exit failed: {error}"))?
        {
            *process = None;
            return Ok(());
        }
        return Err(format!("Core kill failed: {error}"));
    }
    if child
        .wait_for_exit(wait_limit)
        .map_err(|error| format!("wait for Core exit failed: {error}"))?
    {
        *process = None;
        return Ok(());
    }
    Err("Core stop timed out; exit remains unconfirmed".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    struct Fixture {
        observations: VecDeque<io::Result<bool>>,
        kill_result: io::Result<()>,
        kill_calls: usize,
    }

    impl ManagedProcess for Fixture {
        fn has_exited(&mut self) -> io::Result<bool> {
            self.observations.pop_front().expect("bounded observations")
        }
        fn request_kill(&mut self) -> io::Result<()> {
            self.kill_calls += 1;
            std::mem::replace(&mut self.kill_result, Ok(()))
        }
        fn wait_for_exit(&mut self, timeout: Duration) -> io::Result<bool> {
            let deadline = Instant::now() + timeout;
            loop {
                if self.has_exited()? {
                    return Ok(true);
                }
                if Instant::now() >= deadline || self.observations.is_empty() {
                    return Ok(false);
                }
            }
        }
    }

    fn fixture(
        observations: Vec<io::Result<bool>>,
        kill_result: io::Result<()>,
    ) -> Option<Fixture> {
        Some(Fixture {
            observations: observations.into(),
            kill_result,
            kill_calls: 0,
        })
    }

    fn denied() -> io::Error {
        io::Error::new(io::ErrorKind::PermissionDenied, "fixture denied")
    }

    #[test]
    fn already_exited_and_missing_processes_are_idempotent() {
        let mut process = fixture(vec![Ok(true)], Err(denied()));
        assert!(stop_managed_process(&mut process, Duration::ZERO).is_ok());
        assert!(process.is_none());
        assert!(stop_managed_process(&mut process, Duration::ZERO).is_ok());
    }

    #[test]
    fn confirmed_exit_releases_the_handle() {
        let mut process = fixture(vec![Ok(false), Ok(true)], Ok(()));
        assert!(stop_managed_process(&mut process, Duration::ZERO).is_ok());
        assert!(process.is_none());
    }

    #[test]
    fn failed_kill_keeps_a_retryable_handle() {
        let mut process = fixture(vec![Ok(false), Ok(false), Ok(true)], Err(denied()));
        assert!(stop_managed_process(&mut process, Duration::ZERO).is_err());
        assert_eq!(process.as_ref().unwrap().kill_calls, 1);
        assert!(stop_managed_process(&mut process, Duration::ZERO).is_ok());
        assert!(process.is_none());
    }

    #[test]
    fn exit_racing_a_failed_kill_is_still_confirmed() {
        let mut process = fixture(vec![Ok(false), Ok(true)], Err(denied()));
        assert!(stop_managed_process(&mut process, Duration::ZERO).is_ok());
        assert!(process.is_none());
    }

    #[test]
    fn unknown_exit_or_timeout_never_drops_the_handle() {
        for observations in [
            vec![Err(denied())],
            vec![Ok(false), Err(denied())],
            vec![Ok(false), Ok(false)],
        ] {
            let mut process = fixture(observations, Ok(()));
            assert!(stop_managed_process(&mut process, Duration::ZERO).is_err());
            assert!(process.is_some());
        }
    }

    #[test]
    fn owned_stop_rejects_lost_or_mismatched_session_without_touching_child() {
        let owner = format!("{}-1", "a".repeat(64));
        let other = format!("{}-2", "a".repeat(64));
        let mut restarted = ManagedCore::<Fixture>::default();
        assert!(restarted.stop(Some(&owner), Duration::ZERO).is_err());
        let mut live = ManagedCore {
            process: fixture(vec![], Ok(())),
            owner: Some(owner),
            service_stopping: false,
        };
        assert!(live.stop(Some(&other), Duration::ZERO).is_err());
        assert_eq!(live.process.as_ref().unwrap().kill_calls, 0);
    }

    #[test]
    fn owned_stop_is_repeatable_and_closed_start_cannot_revive_a_session() {
        let owner = format!("{}-1", "a".repeat(64));
        let mut core = ManagedCore {
            process: fixture(vec![Ok(true)], Ok(())),
            owner: Some(owner.clone()),
            service_stopping: false,
        };
        assert!(core.stop(Some(&owner), Duration::ZERO).is_ok());
        assert!(core.stop(Some(&owner), Duration::ZERO).is_ok());
        assert_eq!(core.owner.as_deref(), Some(owner.as_str()));
        assert!(core.prepare_start(Some(&owner), Duration::ZERO).is_err());
        assert!(core
            .prepare_start(Some(&format!("{}-2", "a".repeat(64))), Duration::ZERO)
            .unwrap());
    }

    #[test]
    fn owned_start_never_kills_a_live_session_and_same_owner_is_idempotent() {
        let owner = format!("{}-1", "a".repeat(64));
        let other = format!("{}-2", "a".repeat(64));
        let mut core = ManagedCore {
            process: fixture(vec![Ok(false), Ok(false)], Ok(())),
            owner: Some(owner.clone()),
            service_stopping: false,
        };
        assert!(core.prepare_start(Some(&other), Duration::ZERO).is_err());
        assert!(!core.prepare_start(Some(&owner), Duration::ZERO).unwrap());
        assert_eq!(core.process.as_ref().unwrap().kill_calls, 0);
    }

    #[test]
    fn owner_identifiers_are_bounded_public_lifecycle_labels() {
        assert!(validate_owner(&format!("{}-1", "a".repeat(64))).is_ok());
        for value in [
            String::new(),
            "owner".into(),
            format!("{}-0", "a".repeat(64)),
            format!("{}-1", "z".repeat(64)),
            format!("{}-18446744073709551616", "a".repeat(64)),
        ] {
            assert!(validate_owner(&value).is_err());
        }
    }

    #[test]
    fn resource_service_stop_failure_retains_owner_and_success_blocks_new_starts() {
        let owner = format!("{}-1", "a".repeat(64));
        for kill_error in [false, true] {
            let mut core = ManagedCore {
                process: fixture(vec![Ok(false), Ok(false), Ok(true)], if kill_error { Err(denied()) } else { Ok(()) }),
                owner: Some(owner.clone()),
                service_stopping: false,
            };
            assert!(core.stop_for_service(Duration::ZERO).is_err());
            assert!(core.process.is_some());
            assert_eq!(core.owner.as_deref(), Some(owner.as_str()));
            assert!(!core.service_stopping);
            assert!(core.stop_for_service(Duration::ZERO).is_ok());
            assert!(core.process.is_none());
            assert_eq!(core.owner.as_deref(), Some(owner.as_str()));
            assert!(core.prepare_start(Some(&format!("{}-2", "a".repeat(64))), Duration::ZERO).is_err());
            assert!(core.stop_for_service(Duration::ZERO).is_ok());
        }
    }

    #[test]
    fn stop_managed_process_wakes_immediately_without_fixed_10ms_polling_sleep() {
        let mut process = fixture(vec![Ok(false), Ok(false), Ok(true)], Ok(()));
        let started = Instant::now();
        assert!(stop_managed_process(&mut process, Duration::from_millis(250)).is_ok());
        assert!(
            started.elapsed() < Duration::from_millis(5),
            "process exit wait slept {:?} instead of event-driven wakeup",
            started.elapsed()
        );
    }
}
