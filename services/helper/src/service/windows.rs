use crate::service::hub::run_service;
use crate::service::logging::ServiceLogger;

use std::ffi::OsString;

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
            ServiceLogger::new_default().log(format!("service dispatcher failed: {error}"));
            Err(error)
        }
    }
}

define_windows_service!(serveice, service_main);

pub fn service_main(_arguments: Vec<OsString>) {
    match Runtime::new() {
        Ok(rt) => {
            if let Err(error) = rt.block_on(run_windows_service()) {
                ServiceLogger::new_default().log(format!("service main failed: {error:#}"));
            }
        }
        Err(error) => {
            ServiceLogger::new_default().log(format!("service runtime creation failed: {error}"));
        }
    }
}
async fn run_windows_service() -> anyhow::Result<()> {
    // The SCM Stop callback runs outside the Warp task. Clean up the elevated
    // Core child before terminating the service process; otherwise a direct
    // `std::process::exit` leaves Core orphaned and the next start races it.
    let stop_logger = ServiceLogger::new_default();
    let status_handle = service_control_handler::register(
        SERVICE_NAME,
        move |event| -> ServiceControlHandlerResult {
            match event {
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                ServiceControl::Stop => {
                    crate::service::hub::stop_process(&stop_logger);
                    std::process::exit(0)
                }
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        },
    )?;

    status_handle.set_service_status(ServiceStatus {
        service_type: SERVICE_TYPE,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    run_service().await
}
