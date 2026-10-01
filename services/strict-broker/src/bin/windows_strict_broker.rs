#[cfg(not(windows))]
compile_error!("FlClashStrictBroker is a Windows-only service executable");

#[cfg(windows)]
fn main() {
    if std::env::args_os().nth(1).as_deref() == Some(std::ffi::OsStr::new("--strict-canary")) {
        std::process::exit(if flclash_strict_broker::run_windows_strict_canary_child().is_ok() { 0 } else { 1 });
    }
    let logger = flclash_strict_broker::logging::StrictBrokerLogger::new_default();
    logger.log("Strict Broker process starting");
    if let Err(error) = flclash_strict_broker::run_windows_strict_broker_service() {
        logger.log(format!("Strict Broker process failed: {error:#}"));
        eprintln!("FlClashStrictBroker: {error:#}");
        std::process::exit(1);
    }
    logger.log("Strict Broker process stopped");
}
