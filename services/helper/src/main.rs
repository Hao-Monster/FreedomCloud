#[cfg(not(all(feature = "windows-service", target_os = "windows")))]
use crate::service::hub::run_service;
#[cfg(not(all(feature = "windows-service", target_os = "windows")))]
use tokio::runtime::Runtime;

mod service;

#[cfg(all(feature = "windows-service", target_os = "windows"))]
pub fn main() -> windows_service::Result<()> {
    service::windows::main()
}

#[cfg(not(all(feature = "windows-service", target_os = "windows")))]
fn main() {
    let logger = service::logging::ServiceLogger::new_default();
    match Runtime::new() {
        Ok(rt) => {
            if let Err(error) = rt.block_on(run_service(logger.clone())) {
                logger.log(format!("service main failed: {error:#}"));
            }
        }
        Err(error) => logger.log(format!("service runtime creation failed: {error}")),
    }
    if let Err(error) = logger.flush(std::time::Duration::from_millis(500)) {
        eprintln!("FlClashHelperService: {error}");
    }
}
