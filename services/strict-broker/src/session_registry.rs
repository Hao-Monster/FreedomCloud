use anyhow::{bail, Context, Result};

pub trait BrokerSessionResource {
    /// Liveness must be derived from an owned OS/process/session handle, not a PID lookup.
    fn is_alive(&self) -> Result<bool>;

    /// Stops accepting work and releases session resources. It must be bounded and idempotent.
    fn shutdown(&mut self) -> Result<()>;
}

pub struct BrokerSessionRegistry<S> {
    active: Option<S>,
    generation: u64,
}

impl<S> Default for BrokerSessionRegistry<S> {
    fn default() -> Self {
        Self {
            active: None,
            generation: 0,
        }
    }
}

impl<S: BrokerSessionResource> BrokerSessionRegistry<S> {
    pub fn active(&self) -> Option<&S> {
        self.active.as_ref()
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    /// Installs a new session only when no live owner exists. If the old owner exited,
    /// fail-closed cleanup must succeed before its resources are stopped or replaced.
    pub fn activate(
        &mut self,
        candidate: S,
        fail_closed_cleanup: impl FnOnce() -> Result<()>,
    ) -> Result<u64> {
        if let Some(active) = self.active.as_ref() {
            if active
                .is_alive()
                .context("query active strict Broker Agent session")?
            {
                bail!("a live strict Broker Agent session already exists");
            }
        }
        if let Some(active) = self.active.as_mut() {
            fail_closed_cleanup()?;
            active.shutdown()?;
        }
        let generation = self
            .generation
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("strict Broker session generation overflow"))?;
        self.active = Some(candidate);
        self.generation = generation;
        Ok(generation)
    }

    /// Reaps only an exited owner. A live session is left untouched.
    pub fn reap_exited(
        &mut self,
        fail_closed_cleanup: impl FnOnce() -> Result<()>,
    ) -> Result<bool> {
        let Some(active) = self.active.as_mut() else {
            return Ok(false);
        };
        if active.is_alive()? {
            return Ok(false);
        }
        fail_closed_cleanup()?;
        active.shutdown()?;
        self.active = None;
        Ok(true)
    }

    /// Service shutdown always transitions enforcement before releasing the owner session.
    pub fn shutdown(&mut self, fail_closed_cleanup: impl FnOnce() -> Result<()>) -> Result<bool> {
        let Some(active) = self.active.as_mut() else {
            return Ok(false);
        };
        fail_closed_cleanup()?;
        active.shutdown()?;
        self.active = None;
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;
    use std::rc::Rc;

    use super::*;

    struct FakeSession {
        alive: bool,
        shutdowns: Rc<Cell<u32>>,
        fail_shutdown: bool,
    }

    impl FakeSession {
        fn new(alive: bool, shutdowns: Rc<Cell<u32>>) -> Self {
            Self {
                alive,
                shutdowns,
                fail_shutdown: false,
            }
        }
    }

    impl BrokerSessionResource for FakeSession {
        fn is_alive(&self) -> Result<bool> {
            Ok(self.alive)
        }

        fn shutdown(&mut self) -> Result<()> {
            self.shutdowns.set(self.shutdowns.get() + 1);
            if self.fail_shutdown {
                bail!("injected shutdown failure");
            }
            Ok(())
        }
    }

    #[test]
    fn live_session_takeover_is_rejected_without_cleanup() {
        let shutdowns = Rc::new(Cell::new(0));
        let cleanups = Cell::new(0);
        let mut registry = BrokerSessionRegistry::default();
        registry
            .activate(FakeSession::new(true, shutdowns.clone()), || Ok(()))
            .unwrap();

        assert!(registry
            .activate(FakeSession::new(true, shutdowns.clone()), || {
                cleanups.set(cleanups.get() + 1);
                Ok(())
            })
            .is_err());
        assert_eq!(registry.generation(), 1);
        assert_eq!(cleanups.get(), 0);
        assert_eq!(shutdowns.get(), 0);
    }

    #[test]
    fn exited_session_is_cleaned_before_replacement() {
        let shutdowns = Rc::new(Cell::new(0));
        let order = Rc::new(Cell::new(0));
        let mut registry = BrokerSessionRegistry::default();
        registry
            .activate(FakeSession::new(false, shutdowns.clone()), || Ok(()))
            .unwrap();

        let cleanup_order = order.clone();
        registry
            .activate(FakeSession::new(true, shutdowns.clone()), || {
                assert_eq!(shutdowns.get(), 0);
                cleanup_order.set(1);
                Ok(())
            })
            .unwrap();
        assert_eq!(order.get(), 1);
        assert_eq!(shutdowns.get(), 1);
        assert_eq!(registry.generation(), 2);
        assert!(registry.active().unwrap().is_alive().unwrap());
    }

    #[test]
    fn failed_cleanup_retains_the_exited_session() {
        let shutdowns = Rc::new(Cell::new(0));
        let mut registry = BrokerSessionRegistry::default();
        registry
            .activate(FakeSession::new(false, shutdowns.clone()), || Ok(()))
            .unwrap();

        assert!(registry
            .activate(FakeSession::new(true, shutdowns.clone()), || {
                bail!("injected cleanup failure")
            })
            .is_err());
        assert_eq!(registry.generation(), 1);
        assert_eq!(shutdowns.get(), 0);
        assert!(!registry.active().unwrap().is_alive().unwrap());
    }

    #[test]
    fn reap_and_shutdown_are_idempotent_for_an_empty_registry() {
        let shutdowns = Rc::new(Cell::new(0));
        let mut registry = BrokerSessionRegistry::default();
        registry
            .activate(FakeSession::new(false, shutdowns.clone()), || Ok(()))
            .unwrap();
        assert!(registry.reap_exited(|| Ok(())).unwrap());
        assert!(!registry.reap_exited(|| Ok(())).unwrap());
        assert!(!registry.shutdown(|| Ok(())).unwrap());
        assert_eq!(shutdowns.get(), 1);
    }
}
