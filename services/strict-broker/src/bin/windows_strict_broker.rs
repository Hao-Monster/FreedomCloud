#[cfg(not(windows))]
compile_error!("FlClashStrictBroker is a Windows-only service executable");

#[cfg(windows)]
fn main() {
    let logger = flclash_strict_broker::logging::StrictBrokerLogger::new_default();
    logger.log("Strict Broker process starting");
    if let Err(error) = flclash_strict_broker::run_windows_strict_broker_service() {
        logger.log(format!("Strict Broker process failed: {error:#}"));
        eprintln!("FlClashStrictBroker: {error:#}");
        std::process::exit(1);
    }
    logger.log("Strict Broker process stopped");
}
