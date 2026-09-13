use std::time::Duration;

/// The retry policy is deliberately small and deterministic.  It is a state
/// primitive for the future strict-policy supervisor; it does not start a
/// task, touch WFP, or change the existing Core supervisor policy.
pub const MAX_STRICT_RECOVERY_ATTEMPTS: u32 = 5;
pub const STRICT_RECOVERY_BASE_DELAY: Duration = Duration::from_secs(1);
pub const STRICT_RECOVERY_MAX_DELAY: Duration = Duration::from_secs(16);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StrictRetryDecision {
    /// One-based attempt number that may be scheduled.
    pub attempt: u32,
    pub delay: Duration,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StrictRecoveryDiagnostics {
    pub attempts: u32,
    pub exhausted: bool,
    pub next_delay: Option<Duration>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StrictRecoveryRetry {
    attempts: u32,
    max_attempts: u32,
    base_delay: Duration,
    max_delay: Duration,
    next_delay: Option<Duration>,
}

impl Default for StrictRecoveryRetry {
    fn default() -> Self {
        Self::new(
            MAX_STRICT_RECOVERY_ATTEMPTS,
            STRICT_RECOVERY_BASE_DELAY,
            STRICT_RECOVERY_MAX_DELAY,
        )
    }
}

impl StrictRecoveryRetry {
    pub const fn new(max_attempts: u32, base_delay: Duration, max_delay: Duration) -> Self {
        Self {
            attempts: 0,
            max_attempts,
            base_delay,
            max_delay,
            next_delay: None,
        }
    }

    /// Records one failed recovery and returns the bounded delay for the next
    /// attempt.  Once the budget is exhausted, no further retry is returned.
    pub fn schedule_failure(&mut self) -> Option<StrictRetryDecision> {
        if self.attempts >= self.max_attempts || self.max_attempts == 0 {
            self.next_delay = None;
            return None;
        }

        self.attempts += 1;
        let shift = self.attempts.saturating_sub(1).min(31);
        let multiplier = 1_u32 << shift;
        let delay = self
            .base_delay
            .checked_mul(multiplier)
            .unwrap_or(self.max_delay)
            .min(self.max_delay);
        self.next_delay = Some(delay);
        Some(StrictRetryDecision {
            attempt: self.attempts,
            delay,
        })
    }

    /// Clears the failure budget after a fresh, authenticated recovery commit
    /// has completed successfully.
    pub fn reset(&mut self) {
        self.attempts = 0;
        self.next_delay = None;
    }

    pub const fn diagnostics(&self) -> StrictRecoveryDiagnostics {
        StrictRecoveryDiagnostics {
            attempts: self.attempts,
            exhausted: self.attempts >= self.max_attempts,
            next_delay: self.next_delay,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recovery_backoff_is_bounded_and_exhausts() {
        let mut retry = StrictRecoveryRetry::default();
        let delays = (0..MAX_STRICT_RECOVERY_ATTEMPTS)
            .map(|_| retry.schedule_failure().expect("budgeted retry").delay)
            .collect::<Vec<_>>();

        assert_eq!(
            delays,
            vec![
                Duration::from_secs(1),
                Duration::from_secs(2),
                Duration::from_secs(4),
                Duration::from_secs(8),
                Duration::from_secs(16),
            ]
        );
        assert_eq!(retry.schedule_failure(), None);
        assert_eq!(retry.diagnostics().attempts, MAX_STRICT_RECOVERY_ATTEMPTS);
        assert!(retry.diagnostics().exhausted);
        assert_eq!(retry.diagnostics().next_delay, None);
    }

    #[test]
    fn reset_requires_a_successful_fresh_commit() {
        let mut retry =
            StrictRecoveryRetry::new(3, Duration::from_millis(250), Duration::from_secs(1));
        assert_eq!(
            retry.schedule_failure().unwrap().delay,
            Duration::from_millis(250)
        );
        assert_eq!(
            retry.schedule_failure().unwrap().delay,
            Duration::from_millis(500)
        );
        retry.reset();
        assert_eq!(
            retry.diagnostics(),
            StrictRecoveryDiagnostics {
                attempts: 0,
                exhausted: false,
                next_delay: None,
            }
        );
        assert_eq!(retry.schedule_failure().unwrap().attempt, 1);
    }

    #[test]
    fn zero_budget_never_schedules_or_reports_a_delay() {
        let mut retry =
            StrictRecoveryRetry::new(0, Duration::from_secs(1), Duration::from_secs(16));
        assert_eq!(retry.schedule_failure(), None);
        assert_eq!(retry.diagnostics().attempts, 0);
        assert!(retry.diagnostics().exhausted);
        assert_eq!(retry.diagnostics().next_delay, None);
    }

    #[test]
    fn overflow_is_clamped_to_the_configured_maximum() {
        let mut retry = StrictRecoveryRetry::new(u32::MAX, Duration::MAX, Duration::from_secs(7));
        assert_eq!(
            retry.schedule_failure().unwrap().delay,
            Duration::from_secs(7)
        );
    }

    #[test]
    fn every_scheduled_retry_is_monotonic_and_within_the_configured_budget() {
        let mut retry = StrictRecoveryRetry::new(4, Duration::from_secs(3), Duration::from_secs(5));
        let decisions = (0..4)
            .map(|_| retry.schedule_failure().expect("retry budget"))
            .collect::<Vec<_>>();

        assert_eq!(
            decisions
                .iter()
                .map(|decision| decision.attempt)
                .collect::<Vec<_>>(),
            vec![1, 2, 3, 4]
        );
        assert_eq!(
            decisions
                .iter()
                .map(|decision| decision.delay)
                .collect::<Vec<_>>(),
            vec![
                Duration::from_secs(3),
                Duration::from_secs(5),
                Duration::from_secs(5),
                Duration::from_secs(5),
            ]
        );
        assert!(decisions
            .windows(2)
            .all(|window| window[1].delay >= window[0].delay));
        assert_eq!(retry.diagnostics().attempts, 4);
        assert_eq!(retry.diagnostics().next_delay, Some(Duration::from_secs(5)));
        assert!(retry.schedule_failure().is_none());
    }
}
