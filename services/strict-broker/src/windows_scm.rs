use std::ffi::c_void;
use std::io;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr::null_mut;
use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU32, Ordering};
use std::sync::Mutex;

use anyhow::{bail, Context, Result};
use windows_sys::Win32::Foundation::{
    ERROR_CALL_NOT_IMPLEMENTED, ERROR_SERVICE_SPECIFIC_ERROR, NO_ERROR,
};
use windows_sys::Win32::System::Services::{
    RegisterServiceCtrlHandlerExW, SetServiceStatus, StartServiceCtrlDispatcherW,
    SERVICE_ACCEPT_PRESHUTDOWN, SERVICE_ACCEPT_SHUTDOWN, SERVICE_ACCEPT_STOP,
    SERVICE_CONTROL_INTERROGATE, SERVICE_CONTROL_PRESHUTDOWN, SERVICE_CONTROL_SHUTDOWN,
    SERVICE_CONTROL_STOP, SERVICE_RUNNING, SERVICE_START_PENDING, SERVICE_STATUS,
    SERVICE_STATUS_HANDLE, SERVICE_STOPPED, SERVICE_STOP_PENDING, SERVICE_TABLE_ENTRYW,
    SERVICE_WIN32_OWN_PROCESS,
};

use crate::WindowsPipeShutdown;

const START_WAIT_HINT_MS: u32 = 10_000;
const STOP_WAIT_HINT_MS: u32 = 5_000;

type ServiceBootstrap = Box<dyn FnOnce(WindowsScmContext) -> Result<()> + Send + 'static>;

struct ServiceRegistration {
    name: Vec<u16>,
    bootstrap: ServiceBootstrap,
}

static SERVICE_REGISTRATION: Mutex<Option<ServiceRegistration>> = Mutex::new(None);
static SERVICE_RESULT: Mutex<Option<Result<()>>> = Mutex::new(None);

pub struct WindowsScmContext {
    shutdown: WindowsPipeShutdown,
    control: &'static ServiceControlContext,
}

impl WindowsScmContext {
    pub fn shutdown(&self) -> WindowsPipeShutdown {
        self.shutdown.clone()
    }

    pub fn report_running(&self) -> Result<()> {
        self.control.report_running()
    }
}

pub fn run_windows_scm_service(
    service_name: &str,
    bootstrap: impl FnOnce(WindowsScmContext) -> Result<()> + Send + 'static,
) -> Result<()> {
    let service_name = validate_service_name(service_name)?;
    {
        let mut registration = SERVICE_REGISTRATION
            .lock()
            .map_err(|_| anyhow::anyhow!("strict Broker service registration lock is poisoned"))?;
        if registration.is_some() {
            bail!("strict Broker service dispatcher is already registered");
        }
        *registration = Some(ServiceRegistration {
            name: service_name.clone(),
            bootstrap: Box::new(bootstrap),
        });
    }
    *SERVICE_RESULT
        .lock()
        .map_err(|_| anyhow::anyhow!("strict Broker service result lock is poisoned"))? = None;

    let mut table = [
        SERVICE_TABLE_ENTRYW {
            lpServiceName: service_name.as_ptr().cast_mut(),
            lpServiceProc: Some(service_main_entry),
        },
        SERVICE_TABLE_ENTRYW::default(),
    ];
    // SAFETY: the table and its NUL-terminated service name remain live until dispatch returns.
    if unsafe { StartServiceCtrlDispatcherW(table.as_mut_ptr()) } == 0 {
        clear_registration();
        return Err(io::Error::last_os_error())
            .context("start strict Broker service control dispatcher");
    }
    SERVICE_RESULT
        .lock()
        .map_err(|_| anyhow::anyhow!("strict Broker service result lock is poisoned"))?
        .take()
        .unwrap_or_else(|| Err(anyhow::anyhow!("strict Broker service returned no result")))
}

unsafe extern "system" fn service_main_entry(_argument_count: u32, _arguments: *mut *mut u16) {
    let result = catch_unwind(AssertUnwindSafe(run_registered_service))
        .unwrap_or_else(|_| Err(anyhow::anyhow!("strict Broker service main panicked")));
    if let Ok(mut slot) = SERVICE_RESULT.lock() {
        *slot = Some(result);
    }
}

fn run_registered_service() -> Result<()> {
    let registration = SERVICE_REGISTRATION
        .lock()
        .map_err(|_| anyhow::anyhow!("strict Broker service registration lock is poisoned"))?
        .take()
        .ok_or_else(|| anyhow::anyhow!("strict Broker service registration is missing"))?;
    let shutdown = WindowsPipeShutdown::new();
    let control = Box::leak(Box::new(ServiceControlContext::new(shutdown.clone())));
    // SAFETY: service name is NUL-terminated and control is intentionally process-lifetime.
    let status_handle = unsafe {
        RegisterServiceCtrlHandlerExW(
            registration.name.as_ptr(),
            Some(service_control_handler),
            (control as *const ServiceControlContext).cast(),
        )
    };
    if status_handle.is_null() {
        return Err(io::Error::last_os_error())
            .context("register strict Broker service control handler");
    }
    control
        .status_handle
        .store(status_handle, Ordering::Release);
    control.report(SERVICE_START_PENDING, 0, 1, START_WAIT_HINT_MS, NO_ERROR, 0)?;

    let context = WindowsScmContext { shutdown, control };
    let service_result = (registration.bootstrap)(context);
    let entered_running = control.entered_running.load(Ordering::Acquire);
    let shutdown_requested = control.shutdown.is_requested();
    if control.phase.load(Ordering::Acquire) == SERVICE_RUNNING {
        control.report_stop_pending()?;
    }
    match service_result {
        Ok(()) if entered_running && shutdown_requested => {
            control.report(SERVICE_STOPPED, 0, 0, 0, NO_ERROR, 0)?;
            Ok(())
        }
        Ok(()) if entered_running => {
            control.report(SERVICE_STOPPED, 0, 0, 0, ERROR_SERVICE_SPECIFIC_ERROR, 2)?;
            bail!("strict Broker service exited without a shutdown request")
        }
        Ok(()) => {
            control.report(SERVICE_STOPPED, 0, 0, 0, ERROR_SERVICE_SPECIFIC_ERROR, 1)?;
            bail!("strict Broker service exited before reporting running")
        }
        Err(error) => {
            control.report(SERVICE_STOPPED, 0, 0, 0, ERROR_SERVICE_SPECIFIC_ERROR, 1)?;
            Err(error).context("strict Broker service body failed")
        }
    }
}

struct ServiceControlContext {
    shutdown: WindowsPipeShutdown,
    status_handle: AtomicPtr<c_void>,
    phase: AtomicU32,
    checkpoint: AtomicU32,
    entered_running: AtomicBool,
}

impl ServiceControlContext {
    fn new(shutdown: WindowsPipeShutdown) -> Self {
        Self {
            shutdown,
            status_handle: AtomicPtr::new(null_mut()),
            phase: AtomicU32::new(SERVICE_START_PENDING),
            checkpoint: AtomicU32::new(1),
            entered_running: AtomicBool::new(false),
        }
    }

    fn report_running(&self) -> Result<()> {
        self.phase
            .compare_exchange(
                SERVICE_START_PENDING,
                SERVICE_RUNNING,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .map_err(|_| anyhow::anyhow!("strict Broker service cannot enter running state"))?;
        self.report(
            SERVICE_RUNNING,
            accepted_controls(SERVICE_RUNNING),
            0,
            0,
            NO_ERROR,
            0,
        )?;
        self.entered_running.store(true, Ordering::Release);
        Ok(())
    }

    fn report_stop_pending(&self) -> Result<()> {
        let previous = self.phase.swap(SERVICE_STOP_PENDING, Ordering::AcqRel);
        if previous == SERVICE_STOPPED {
            bail!("strict Broker service is already stopped");
        }
        let checkpoint = self.checkpoint.fetch_add(1, Ordering::AcqRel) + 1;
        self.report(
            SERVICE_STOP_PENDING,
            0,
            checkpoint,
            STOP_WAIT_HINT_MS,
            NO_ERROR,
            0,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn report(
        &self,
        state: u32,
        controls: u32,
        checkpoint: u32,
        wait_hint: u32,
        win32_exit_code: u32,
        service_exit_code: u32,
    ) -> Result<()> {
        self.phase.store(state, Ordering::Release);
        let status_handle = self.status_handle.load(Ordering::Acquire);
        if status_handle.is_null() {
            bail!("strict Broker service status handle is missing");
        }
        let status = SERVICE_STATUS {
            dwServiceType: SERVICE_WIN32_OWN_PROCESS,
            dwCurrentState: state,
            dwControlsAccepted: controls,
            dwWin32ExitCode: win32_exit_code,
            dwServiceSpecificExitCode: service_exit_code,
            dwCheckPoint: checkpoint,
            dwWaitHint: wait_hint,
        };
        // SAFETY: the status handle is registered and status is initialized.
        if unsafe { SetServiceStatus(status_handle as SERVICE_STATUS_HANDLE, &status) } == 0 {
            return Err(io::Error::last_os_error()).context("report strict Broker service status");
        }
        Ok(())
    }
}

unsafe extern "system" fn service_control_handler(
    control: u32,
    _event_type: u32,
    _event_data: *mut c_void,
    context: *mut c_void,
) -> u32 {
    if context.is_null() {
        return ERROR_CALL_NOT_IMPLEMENTED;
    }
    // SAFETY: the context is a process-lifetime ServiceControlContext allocation.
    let context = unsafe { &*context.cast::<ServiceControlContext>() };
    match control {
        SERVICE_CONTROL_STOP | SERVICE_CONTROL_SHUTDOWN | SERVICE_CONTROL_PRESHUTDOWN => {
            context.shutdown.request();
            let _ = context.report_stop_pending();
            NO_ERROR
        }
        SERVICE_CONTROL_INTERROGATE => NO_ERROR,
        _ => ERROR_CALL_NOT_IMPLEMENTED,
    }
}

fn accepted_controls(state: u32) -> u32 {
    if state == SERVICE_RUNNING {
        SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN | SERVICE_ACCEPT_PRESHUTDOWN
    } else {
        0
    }
}

fn validate_service_name(value: &str) -> Result<Vec<u16>> {
    if value.is_empty()
        || value.len() > 128
        || !value.is_ascii()
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        bail!("strict Broker service name is invalid");
    }
    Ok(value.encode_utf16().chain(Some(0)).collect())
}

fn clear_registration() {
    if let Ok(mut registration) = SERVICE_REGISTRATION.lock() {
        registration.take();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_running_services_accept_stop_controls() {
        assert_eq!(accepted_controls(SERVICE_START_PENDING), 0);
        assert_eq!(accepted_controls(SERVICE_STOP_PENDING), 0);
        assert_eq!(accepted_controls(SERVICE_STOPPED), 0);
        assert_eq!(
            accepted_controls(SERVICE_RUNNING),
            SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN | SERVICE_ACCEPT_PRESHUTDOWN
        );
    }

    #[test]
    fn service_names_are_narrow_and_nul_terminated() {
        let valid = validate_service_name("FlClashX.StrictBroker").unwrap();
        assert_eq!(valid.last(), Some(&0));
        assert!(validate_service_name("").is_err());
        assert!(validate_service_name("FlClashX StrictBroker").is_err());
        assert!(validate_service_name(&"x".repeat(129)).is_err());
    }
}
