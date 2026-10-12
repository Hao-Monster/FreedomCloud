use crate::service::hub::run_service;
use crate::service::logging::ServiceLogger;

use std::ffi::OsString;
use std::future::Future;
use std::time::Duration;

use tokio::runtime::Runtime;

use windows_service::{
    define_windows_service,
    service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    },
    service_control_handler::{self, ServiceControlHandlerResult},
    service_dispatcher, Result,
};

const SERVICE_NAME: &str = "FlClashHelperService";

const SERVICE_TYPE: ServiceType = ServiceType::OWN_PROCESS;

pub fn main() -> Result<()> {
    start_service()
}

pub fn start_service() -> Result<()> {
    match service_dispatcher::start(SERVICE_NAME, serveice) {
        Ok(()) => Ok(()),
        Err(error) => {
            let logger = ServiceLogger::new_default();
            logger.log(format!("service dispatcher failed: {error}"));
            if let Err(flush_error) = logger.flush(Duration::from_millis(500)) {
                eprintln!("FlClashHelperService: dispatcher diagnostics incomplete: {flush_error}");
            }
            Err(error)
        }
    }
}

define_windows_service!(serveice, service_main);

pub fn service_main(_arguments: Vec<OsString>) {
    let logger = ServiceLogger::new_default();
    match Runtime::new() {
        Ok(rt) => {
            if let Err(error) = rt.block_on(run_windows_service(logger.clone())) {
                logger.log(format!("service main failed: {error:#}"));
            }
        }
        Err(error) => {
            logger.log(format!("service runtime creation failed: {error}"));
        }
    }
    if let Err(error) = logger.flush(Duration::from_millis(500)) {
        eprintln!("FlClashHelperService: final diagnostics incomplete: {error}");
    }
}

/// The worker, not the SCM callback, waits for the child. Errors keep the service
/// alive with its owned child handle; only a confirmed exit permits Stopped.
async fn stop_attempt<F, R>(stop: F, mut report: R) -> std::result::Result<(), String>
where
    F: Future<Output = std::result::Result<(), String>>,
    R: FnMut(ServiceState, u32, bool),
{
    report(ServiceState::StopPending, 1, false);
    tokio::pin!(stop);
    let mut checkpoint = 1u32;
    let mut tick = tokio::time::interval_at(
        tokio::time::Instant::now() + Duration::from_secs(1),
        Duration::from_secs(1),
    );
    loop {
        tokio::select! {
            result = &mut stop => {
                if result.is_err() { report(ServiceState::Running, 0, true); }
                return result;
            }
            _ = tick.tick() => {
                checkpoint = checkpoint.saturating_add(1);
                report(ServiceState::StopPending, checkpoint, false);
            }
        }
    }
}

async fn run_windows_service(logger: std::sync::Arc<ServiceLogger>) -> anyhow::Result<()> {
    let (stop_tx, mut stop_rx) = tokio::sync::mpsc::channel(1);
    let status_handle = service_control_handler::register(
        SERVICE_NAME,
        move |event| -> ServiceControlHandlerResult {
            match event {
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                ServiceControl::Stop => match stop_tx.try_send(()) {
                    Ok(()) | Err(tokio::sync::mpsc::error::TrySendError::Full(())) => {
                        ServiceControlHandlerResult::NoError
                    }
                    Err(tokio::sync::mpsc::error::TrySendError::Closed(())) => {
                        ServiceControlHandlerResult::Other(1062)
                    }
                },
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        },
    )?;

    let report = |state, checkpoint, failed| {
        let status = ServiceStatus {
            service_type: SERVICE_TYPE,
            current_state: state,
            controls_accepted: if state == ServiceState::Running {
                ServiceControlAccept::STOP
            } else {
                ServiceControlAccept::empty()
            },
            exit_code: ServiceExitCode::Win32(if failed { 31 } else { 0 }),
            checkpoint,
            wait_hint: if state == ServiceState::StopPending {
                Duration::from_secs(10)
            } else {
                Duration::ZERO
            },
            process_id: None,
        };
        if let Err(error) = status_handle.set_service_status(status) {
            logger.log(format!("service status update failed: {error}"));
        }
    };
    report(ServiceState::Running, 0, false);
    let mut server = tokio::spawn(run_service(logger.clone()));
    let mut server_failed = false;
    loop {
        tokio::select! {
            request = stop_rx.recv() => {
                if request.is_none() { std::future::pending::<()>().await; }
            }
            result = &mut server, if !server_failed => {
                logger.log(format!("service HTTP server ended unexpectedly: {result:?}"));
                server_failed = true;
            }
        }
        let stop_logger = logger.clone();
        let result = stop_attempt(
            async move {
                tokio::task::spawn_blocking(move || {
                    crate::service::hub::stop_for_service(&stop_logger)
                })
                .await
                .map_err(|error| format!("Core stop worker failed: {error}"))?
            },
            &report,
        )
        .await;
        if let Err(error) = result {
            logger.log(format!(
                "service stop rejected; ownership retained for retry: {error}"
            ));
            continue;
        }
        // The same ownership lock now rejects new starts. End HTTP only after
        // the owned Core has exited, then acknowledge SCM shutdown.
        if !server_failed {
            server.abort();
            let _ = server.await;
        }
        finish_confirmed_stop(logger.clone(), server_failed, report).await;
        return Ok(());
    }
}

async fn finish_confirmed_stop<R>(
    logger: std::sync::Arc<ServiceLogger>,
    server_failed: bool,
    mut report: R,
) where
    R: FnMut(ServiceState, u32, bool),
{
    let result = tokio::task::spawn_blocking(move || {
        logger.finish_core_output(Duration::from_secs(2), Duration::from_millis(500))
    })
    .await;
    let logs_failed = match result {
        Ok(Ok(())) => false,
        Ok(Err(error)) => {
            eprintln!("FlClashHelperService: {error}");
            true
        }
        Err(error) => {
            eprintln!("FlClashHelperService: log finish worker failed: {error}");
            true
        }
    };
    // A log failure must be visible, but cannot undo the verified Core exit.
    report(ServiceState::Stopped, 0, server_failed || logs_failed);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn resource_r1_log_failure_reports_stopped_without_reversing_core_exit() {
        let mut events = Vec::new();
        finish_confirmed_stop(
            ServiceLogger::discard_for_test(),
            false,
            |state, checkpoint, failed| {
                events.push((state, checkpoint, failed));
            },
        )
        .await;
        assert_eq!(events, vec![(ServiceState::Stopped, 0, true)]);
    }

    #[tokio::test]
    async fn resource_scm_failed_stop_does_not_report_stopped_and_can_retry() {
        let mut events = Vec::new();
        let failed = stop_attempt(
            async { Err("Core exit unconfirmed".to_owned()) },
            |state, checkpoint, failed| events.push((state, checkpoint, failed)),
        )
        .await;
        assert!(failed.is_err());
        assert_eq!(
            events,
            vec![
                (ServiceState::StopPending, 1, false),
                (ServiceState::Running, 0, true)
            ]
        );
        events.clear();
        assert!(
            stop_attempt(async { Ok(()) }, |state, checkpoint, failed| events
                .push((state, checkpoint, failed)))
            .await
            .is_ok()
        );
        assert_eq!(events, vec![(ServiceState::StopPending, 1, false)]);
    }

    #[tokio::test]
    async fn resource_scm_delayed_exit_updates_checkpoint_before_completion() {
        let mut events = Vec::new();
        assert!(stop_attempt(
            async {
                tokio::time::sleep(Duration::from_millis(1100)).await;
                Ok(())
            },
            |state, checkpoint, _| events.push((state, checkpoint))
        )
        .await
        .is_ok());
        assert_eq!(events[0], (ServiceState::StopPending, 1));
        assert!(events
            .iter()
            .any(|(state, checkpoint)| *state == ServiceState::StopPending && *checkpoint >= 2));
        assert!(events
            .iter()
            .all(|(state, _)| *state != ServiceState::Stopped));
    }
}
